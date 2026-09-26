import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { CreateCustomerDto } from './dto/create-customer.dto.js';
import { UpdateCustomerDto } from './dto/update-customer.dto.js';
import { requireOrgId } from '../common/tenant/tenant-context.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

@Injectable()
export class CustomersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async list(query: PaginationQuery & { status?: string }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.search) {
      where.OR = [
        { name: { contains: query.search, mode: 'insensitive' } },
        { email: { contains: query.search, mode: 'insensitive' } },
        { taxNumber: { contains: query.search, mode: 'insensitive' } },
      ];
    }
    if (query.status) where.status = query.status;

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.customer.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { _count: { select: { invoices: true, quotations: true } } },
      }),
      this.prisma.tenant.customer.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async getOne(id: string) {
    const customer = await this.prisma.tenant.customer.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException('Customer not found');
    return customer;
  }

  async create(dto: CreateCustomerDto) {
    const customer = await this.prisma.tenant.customer.create({
      data: Object.assign({}, dto, { organizationId: requireOrgId() }),
    });
    await this.audit.log('CREATE', 'CUSTOMER', customer.id);
    return customer;
  }

  async update(id: string, dto: UpdateCustomerDto) {
    const existing = await this.prisma.tenant.customer.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Customer not found');

    const customer = await this.prisma.tenant.customer.update({ where: { id }, data: dto });
    await this.audit.log('UPDATE', 'CUSTOMER', id);
    return customer;
  }

  async setStatus(id: string, status: 'ACTIVE' | 'INACTIVE') {
    const existing = await this.prisma.tenant.customer.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Customer not found');

    const customer = await this.prisma.tenant.customer.update({ where: { id }, data: { status } });
    await this.audit.log('UPDATE', 'CUSTOMER', id, { status });
    return customer;
  }
}