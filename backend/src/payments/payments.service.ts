import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InvoiceStatus, PaymentStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { DocumentNumberService } from '../common/services/document-number.service.js';
import { CreatePaymentDto } from '../sales/dto/sales.dto.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly numbers: DocumentNumberService,
  ) {}

  async createPayment(organizationId: string, userId: string, dto: CreatePaymentDto) {
    const amount = new Prisma.Decimal(dto.amount);

    return this.prisma.tenant.$transaction(async (tx) => {
      const invoice = await tx.invoice.findFirst({
        where: { id: dto.invoiceId, organizationId },
        include: { payments: { where: { status: PaymentStatus.CONFIRMED } } },
      });
      if (!invoice) throw new NotFoundException('Invoice not found');
      if (invoice.status === InvoiceStatus.DRAFT) {
        throw new BadRequestException('Invoice must be posted before payment');
      }
      if (invoice.status === InvoiceStatus.CANCELLED) {
        throw new BadRequestException('Cancelled invoices cannot be paid');
      }

      const paid = invoice.payments.reduce(
        (sum, p) => sum.add(new Prisma.Decimal(p.amount)),
        new Prisma.Decimal(0),
      );
      const total = new Prisma.Decimal(invoice.totalAmount);
      const outstanding = total.sub(paid);
      if (outstanding.lte(0)) {
        throw new BadRequestException('Invoice is already fully paid');
      }
      if (amount.gt(outstanding)) {
        throw new BadRequestException('Amount exceeds the outstanding balance');
      }

      const number = await this.numbers.next('PAY', organizationId, tx);
      const payment = await tx.payment.create({
        data: {
          number,
          organizationId,
          invoiceId: invoice.id,
          customerId: invoice.customerId,
          amount,
          method: dto.method ?? 'CASH',
          status: PaymentStatus.CONFIRMED,
          reference: dto.reference ?? null,
          paidAt: dto.paidAt ? new Date(dto.paidAt) : new Date(),
          createdById: userId,
        },
      });

      if (outstanding.sub(amount).lte(0)) {
        await tx.invoice.update({
          where: { id: invoice.id },
          data: { status: InvoiceStatus.PAID, paidAt: new Date() },
        });
      }
      return payment;
    });
  }

  async listPayments(organizationId: string, query: PaginationQuery & { invoiceId?: string }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.invoiceId) where.invoiceId = query.invoiceId;
    if (query.search) {
      where.OR = [
        { number: { contains: query.search, mode: 'insensitive' } },
        { reference: { contains: query.search, mode: 'insensitive' } },
        { customer: { name: { contains: query.search, mode: 'insensitive' } } },
      ];
    }

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.payment.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { invoice: true, customer: true },
      }),
      this.prisma.tenant.payment.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async getPayment(organizationId: string, id: string) {
    const payment = await this.prisma.tenant.payment.findUnique({
      where: { id },
      include: { invoice: true, customer: true },
    });
    if (!payment) throw new NotFoundException('Payment not found');
    return payment;
  }
}