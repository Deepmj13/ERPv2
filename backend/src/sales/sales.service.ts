import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DocStatus, InvoiceStatus, MovementType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { DocumentNumberService } from '../common/services/document-number.service.js';
import {
  CreateQuotationDto,
  UpdateQuotationDto,
  CreateSalesOrderDto,
  CreateInvoiceDto,
  DocumentItemDto,
} from './dto/sales.dto.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Tx = any;

interface ComputedTotals {
  subtotal: Prisma.Decimal;
  taxAmount: Prisma.Decimal;
  totalAmount: Prisma.Decimal;
  lines: { lineTotal: Prisma.Decimal; taxRate: Prisma.Decimal }[];
}

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly numbers: DocumentNumberService,
  ) {}

  private computeTotals(items: DocumentItemDto[]): ComputedTotals {
    let subtotal = new Prisma.Decimal(0);
    let taxAmount = new Prisma.Decimal(0);
    const lines = items.map((it) => {
      const qty = new Prisma.Decimal(it.quantity);
      const price = new Prisma.Decimal(it.unitPrice);
      const rate = new Prisma.Decimal(it.taxRate ?? 0);
      const lineTotal = qty.mul(price);
      const tax = lineTotal.mul(rate).div(100);
      subtotal = subtotal.add(lineTotal);
      taxAmount = taxAmount.add(tax);
      return { lineTotal: new Prisma.Decimal(lineTotal.toFixed(2)), taxRate: rate };
    });
    subtotal = new Prisma.Decimal(subtotal.toFixed(2));
    taxAmount = new Prisma.Decimal(taxAmount.toFixed(2));
    return { subtotal, taxAmount, totalAmount: subtotal.add(taxAmount), lines };
  }

  private itemData(items: DocumentItemDto[], lines: ComputedTotals['lines']) {
    return items.map((it, i) => ({
      productId: it.productId ?? null,
      description: it.description ?? null,
      quantity: it.quantity,
      unitPrice: it.unitPrice,
      taxRate: it.taxRate ?? 0,
      lineTotal: lines[i].lineTotal,
    }));
  }

  private async customerBelongsToOrg(tx: Tx, organizationId: string, customerId: string) {
    const customer = await tx.customer.findFirst({ where: { id: customerId, organizationId } });
    return Boolean(customer);
  }

  private async findQuotation(organizationId: string, id: string) {
    const quotation = await this.prisma.tenant.quotation.findUnique({
      where: { id },
      include: { items: true, customer: true },
    });
    if (!quotation) throw new NotFoundException('Quotation not found');
    return quotation;
  }

  // ---------- Quotations ----------

  async createQuotation(organizationId: string, userId: string, dto: CreateQuotationDto) {
    const totals = this.computeTotals(dto.items);
    const quotation = await this.prisma.tenant.$transaction(async (tx) => {
      const ok = await this.customerBelongsToOrg(tx, organizationId, dto.customerId);
      if (!ok) throw new BadRequestException('Customer not found in your organization');
      const number = await this.numbers.next('QUO', organizationId, tx);
      return tx.quotation.create({
        data: {
          number,
          organizationId,
          customerId: dto.customerId,
          issueDate: dto.issueDate ? new Date(dto.issueDate) : new Date(),
          expiryDate: dto.expiryDate ? new Date(dto.expiryDate) : null,
          subtotal: totals.subtotal,
          taxAmount: totals.taxAmount,
          totalAmount: totals.totalAmount,
          notes: dto.notes ?? null,
          createdById: userId,
          items: { create: this.itemData(dto.items, totals.lines) },
        },
        include: { items: true, customer: true },
      });
    });
    await this.audit.log('CREATE', 'QUOTATION', quotation.id, { number: quotation.number });
    return quotation;
  }

  async listQuotations(organizationId: string, query: PaginationQuery & { status?: DocStatus }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.status) where.status = query.status;
    if (query.search) {
      where.OR = [
        { number: { contains: query.search, mode: 'insensitive' } },
        { customer: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }
    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.quotation.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { customer: true, _count: { select: { items: true } } },
      }),
      this.prisma.tenant.quotation.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async getQuotation(organizationId: string, id: string) {
    const quotation = await this.prisma.tenant.quotation.findUnique({
      where: { id },
      include: { items: true, customer: true, orders: { select: { id: true, number: true, status: true } } },
    });
    if (!quotation) throw new NotFoundException('Quotation not found');
    return quotation;
  }

  async updateQuotation(organizationId: string, id: string, dto: UpdateQuotationDto) {
    const quotation = await this.findQuotation(organizationId, id);
    if (quotation.status !== DocStatus.DRAFT) {
      throw new BadRequestException('Only draft quotations can be edited');
    }

    const totals = dto.items ? this.computeTotals(dto.items) : null;
    const updated = await this.prisma.tenant.$transaction(async (tx) => {
      if (dto.customerId && !(await this.customerBelongsToOrg(tx, organizationId, dto.customerId))) {
        throw new BadRequestException('Customer not found in your organization');
      }
      if (dto.items) await tx.quotationItem.deleteMany({ where: { quotationId: id } });
      return tx.quotation.update({
        where: { id },
        data: {
          ...(dto.customerId ? { customerId: dto.customerId } : {}),
          ...(dto.notes !== undefined ? { notes: dto.notes ?? null } : {}),
          ...(dto.expiryDate ? { expiryDate: new Date(dto.expiryDate) } : {}),
          ...(totals
            ? {
                subtotal: totals.subtotal,
                taxAmount: totals.taxAmount,
                totalAmount: totals.totalAmount,
                items: {
                  create: this.itemData(dto.items!, totals.lines),
                },
              }
            : {}),
        },
        include: { items: true, customer: true },
      });
    });
    await this.audit.log('UPDATE', 'QUOTATION', id);
    return updated;
  }

  async submitQuotation(organizationId: string, id: string) {
    await this.transitionQuotation(organizationId, id, DocStatus.CONFIRMED, [DocStatus.DRAFT], 'SUBMIT_QUOTATION');
    return this.getQuotation(organizationId, id);
  }

  async cancelQuotation(organizationId: string, id: string) {
    await this.transitionQuotation(organizationId, id, DocStatus.CANCELLED, [DocStatus.DRAFT, DocStatus.CONFIRMED], 'CANCEL_QUOTATION');
    return this.getQuotation(organizationId, id);
  }

  private async transitionQuotation(
    organizationId: string,
    id: string,
    to: DocStatus,
    from: DocStatus[],
    auditAction: string,
  ) {
    const quotation = await this.findQuotation(organizationId, id);
    if (!from.includes(quotation.status)) {
      throw new BadRequestException(`Cannot change quotation from ${quotation.status} to ${to}`);
    }
    await this.prisma.tenant.quotation.update({ where: { id }, data: { status: to } });
    await this.audit.log(auditAction, 'QUOTATION', id);
    return quotation;
  }

  async convertQuotation(organizationId: string, userId: string, id: string) {
    const quotation = await this.findQuotation(organizationId, id);
    if (quotation.status !== DocStatus.CONFIRMED) {
      throw new BadRequestException('Only confirmed quotations can be converted to orders');
    }
    const existing = await this.prisma.tenant.salesOrder.findFirst({ where: { quotationId: id } });
    if (existing) throw new ConflictException('Quotation has already been converted');

    const order = await this.prisma.tenant.$transaction(async (tx) => {
      const number = await this.numbers.next('SO', organizationId, tx);
      const created = await tx.salesOrder.create({
        data: {
          number,
          organizationId,
          customerId: quotation.customerId,
          quotationId: id,
          status: DocStatus.CONFIRMED,
          issueDate: new Date(),
          subtotal: quotation.subtotal,
          taxAmount: quotation.taxAmount,
          totalAmount: quotation.totalAmount,
          notes: quotation.notes,
          createdById: userId,
          items: {
            create: quotation.items.map((it) => ({
              productId: it.productId,
              description: it.description,
              quantity: it.quantity,
              unitPrice: it.unitPrice,
              taxRate: it.taxRate,
              lineTotal: it.lineTotal,
            })),
          },
        },
        include: { items: true, customer: true },
      });
      await tx.quotation.update({ where: { id }, data: { status: DocStatus.COMPLETED } });
      return created;
    });
    await this.audit.log('CONVERT_QUOTATION', 'QUOTATION', id, { orderId: order.id });
    return order;
  }

  // ---------- Sales orders ----------

  async getOrder(organizationId: string, id: string) {
    const order = await this.prisma.tenant.salesOrder.findUnique({
      where: { id },
      include: { items: true, customer: true, quotation: true, invoice: true },
    });
    if (!order) throw new NotFoundException('Sales order not found');
    return order;
  }

  async createSalesOrder(organizationId: string, userId: string, dto: CreateSalesOrderDto) {
    const items = dto.items ?? [];
    if (items.length === 0) {
      throw new BadRequestException('At least one item is required');
    }
    if (!dto.customerId && !dto.quotationId) {
      throw new BadRequestException('customerId or quotationId is required');
    }

    const totals = this.computeTotals(items);
    return this.prisma.tenant.$transaction(async (tx) => {
      let customerId = dto.customerId;
      if (dto.quotationId) {
        const quotation = await tx.quotation.findFirst({
          where: { id: dto.quotationId, organizationId, status: DocStatus.CONFIRMED },
        });
        if (!quotation) throw new BadRequestException('Quotation not found or not confirmed');
        customerId = quotation.customerId;
      }
      if (!customerId) throw new BadRequestException('Customer is required');
      if (!(await this.customerBelongsToOrg(tx, organizationId, customerId))) {
        throw new BadRequestException('Customer not found in your organization');
      }

      const number = await this.numbers.next('SO', organizationId, tx);
      const order = await tx.salesOrder.create({
        data: {
          number,
          organizationId,
          customerId,
          quotationId: dto.quotationId ?? null,
          issueDate: dto.issueDate ? new Date(dto.issueDate) : new Date(),
          subtotal: totals.subtotal,
          taxAmount: totals.taxAmount,
          totalAmount: totals.totalAmount,
          notes: dto.notes ?? null,
          createdById: userId,
          items: { create: this.itemData(items, totals.lines) },
        },
        include: { items: true, customer: true },
      });
      if (dto.quotationId) {
        await tx.quotation.update({
          where: { id: dto.quotationId },
          data: { status: DocStatus.COMPLETED },
        });
      }
      return order;
    });
  }

  async listOrders(organizationId: string, query: PaginationQuery & { status?: DocStatus }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.status) where.status = query.status;
    if (query.search) {
      where.OR = [
        { number: { contains: query.search, mode: 'insensitive' } },
        { customer: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }
    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.salesOrder.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { customer: true, _count: { select: { items: true } } },
      }),
      this.prisma.tenant.salesOrder.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async submitOrder(organizationId: string, id: string) {
    const order = await this.getOrder(organizationId, id);
    if (order.status !== DocStatus.DRAFT) {
      throw new BadRequestException(`Cannot submit order from ${order.status}`);
    }
    await this.prisma.tenant.salesOrder.update({ where: { id }, data: { status: DocStatus.CONFIRMED } });
    await this.audit.log('SUBMIT_ORDER', 'SALES_ORDER', id);
    return this.getOrder(organizationId, id);
  }

  async cancelOrder(organizationId: string, id: string) {
    const order = await this.getOrder(organizationId, id);
    const cancellable: DocStatus[] = [DocStatus.DRAFT, DocStatus.CONFIRMED];
    if (!cancellable.includes(order.status)) {
      throw new BadRequestException('Order cannot be cancelled in its current state');
    }
    if (order.invoice) {
      throw new BadRequestException('Order with an invoice cannot be cancelled');
    }
    await this.prisma.tenant.salesOrder.update({ where: { id }, data: { status: DocStatus.CANCELLED } });
    await this.audit.log('CANCEL_ORDER', 'SALES_ORDER', id);
    return this.getOrder(organizationId, id);
  }

  // ---------- Invoices ----------

  async createInvoiceFromOrder(organizationId: string, userId: string, orderId: string) {
    const order = await this.getOrder(organizationId, orderId);
    if (order.status !== DocStatus.CONFIRMED) {
      throw new BadRequestException('Order must be confirmed before invoicing');
    }
    if (order.invoice) throw new ConflictException('Order already has an invoice');

    const invoice = await this.prisma.tenant.$transaction(async (tx) => {
      const number = await this.numbers.next('INV', organizationId, tx);
      const created = await tx.invoice.create({
        data: {
          number,
          organizationId,
          customerId: order.customerId,
          orderId,
          issueDate: new Date(),
          subtotal: order.subtotal,
          taxAmount: order.taxAmount,
          totalAmount: order.totalAmount,
          notes: order.notes,
          createdById: userId,
          items: {
            create: order.items.map((it) => ({
              productId: it.productId,
              description: it.description,
              quantity: it.quantity,
              unitPrice: it.unitPrice,
              taxRate: it.taxRate,
              lineTotal: it.lineTotal,
            })),
          },
        },
        include: { items: true, customer: true },
      });
      await tx.salesOrder.update({ where: { id: orderId }, data: { status: DocStatus.COMPLETED } });
      return created;
    });
    await this.audit.log('CREATE_INVOICE', 'INVOICE', invoice.id, { orderId });
    return invoice;
  }

  async createInvoiceDirect(organizationId: string, userId: string, dto: CreateInvoiceDto) {
    const items = dto.items ?? [];
    if (items.length === 0) {
      throw new BadRequestException('At least one item is required');
    }
    if (!dto.customerId) throw new BadRequestException('customerId is required');

    const totals = this.computeTotals(items);
    return this.prisma.tenant.$transaction(async (tx) => {
      if (!(await this.customerBelongsToOrg(tx, organizationId, dto.customerId!))) {
        throw new BadRequestException('Customer not found in your organization');
      }
      const number = await this.numbers.next('INV', organizationId, tx);
      return tx.invoice.create({
        data: {
          number,
          organizationId,
          customerId: dto.customerId!,
          issueDate: dto.issueDate ? new Date(dto.issueDate) : new Date(),
          dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
          subtotal: totals.subtotal,
          taxAmount: totals.taxAmount,
          totalAmount: totals.totalAmount,
          notes: dto.notes ?? null,
          createdById: userId,
          items: { create: this.itemData(items, totals.lines) },
        },
        include: { items: true, customer: true },
      });
    });
  }

  async listInvoices(organizationId: string, query: PaginationQuery & { status?: InvoiceStatus }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.status) where.status = query.status;
    if (query.search) {
      where.OR = [
        { number: { contains: query.search, mode: 'insensitive' } },
        { customer: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }
    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.invoice.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { customer: true, _count: { select: { items: true, payments: true } } },
      }),
      this.prisma.tenant.invoice.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async getInvoice(organizationId: string, id: string) {
    const invoice = await this.prisma.tenant.invoice.findUnique({
      where: { id },
      include: { items: true, customer: true, order: true, payments: true },
    });
    if (!invoice) throw new NotFoundException('Invoice not found');
    return invoice;
  }

  async postInvoice(organizationId: string, id: string) {
    const invoice = await this.prisma.tenant.invoice.findUnique({
      where: { id },
      include: { items: true },
    });
    if (!invoice) throw new NotFoundException('Invoice not found');
    if (invoice.status !== InvoiceStatus.DRAFT) {
      throw new BadRequestException('Only draft invoices can be posted');
    }

    await this.prisma.tenant.$transaction(async (tx) => {
      await tx.invoice.update({
        where: { id },
        data: { status: InvoiceStatus.POSTED, postedAt: new Date() },
      });
      if (invoice.items.length > 0) {
        const movements = invoice.items
          .filter((it) => it.productId)
          .map((it) => ({
            organizationId,
            productId: it.productId!,
            warehouseId: null,
            movementType: MovementType.SALE,
            quantity: new Prisma.Decimal(it.quantity).negated(),
            referenceType: 'INVOICE',
            referenceId: id,
          }));
        if (movements.length > 0) {
          await tx.stockMovement.createMany({ data: movements });
        }
      }
    });
    await this.audit.log('INVOICE_POST', 'INVOICE', id, { number: invoice.number });
    return this.getInvoice(organizationId, id);
  }

  async cancelInvoice(organizationId: string, id: string) {
    const invoice = await this.prisma.tenant.invoice.findUnique({
      where: { id },
      include: { items: true, payments: true },
    });
    if (!invoice) throw new NotFoundException('Invoice not found');
    if (invoice.status === InvoiceStatus.CANCELLED) {
      throw new BadRequestException('Invoice already cancelled');
    }
    if (invoice.status === InvoiceStatus.PAID) {
      throw new BadRequestException('Paid invoices cannot be cancelled');
    }
    if (invoice.payments.length > 0) {
      throw new BadRequestException('Invoice with payments cannot be cancelled');
    }

    await this.prisma.tenant.$transaction(async (tx) => {
      await tx.invoice.update({
        where: { id },
        data: { status: InvoiceStatus.CANCELLED },
      });
      if (invoice.status === InvoiceStatus.POSTED && invoice.items.length > 0) {
        const movements = invoice.items
          .filter((it) => it.productId)
          .map((it) => ({
            organizationId,
            productId: it.productId!,
            warehouseId: null,
            movementType: MovementType.RETURN,
            quantity: it.quantity,
            referenceType: 'INVOICE_CANCEL',
            referenceId: id,
          }));
        if (movements.length > 0) {
          await tx.stockMovement.createMany({ data: movements });
        }
      }
    });
    await this.audit.log('CANCEL_INVOICE', 'INVOICE', id);
    return this.getInvoice(organizationId, id);
  }

  async outstanding(organizationId: string, id: string) {
    const invoice = await this.prisma.tenant.invoice.findUnique({
      where: { id },
      include: { payments: { where: { status: 'CONFIRMED' } } },
    });
    if (!invoice) throw new NotFoundException('Invoice not found');
    const paid = invoice.payments.reduce(
      (sum, p) => sum.add(new Prisma.Decimal(p.amount)),
      new Prisma.Decimal(0),
    );
    const total = new Prisma.Decimal(invoice.totalAmount);
    return { invoiceId: id, total: total, paid, outstanding: total.sub(paid).lte(0) ? new Prisma.Decimal(0) : total.sub(paid) };
  }
}