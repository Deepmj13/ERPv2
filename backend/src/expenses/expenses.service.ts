import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { CreateExpenseDto } from './dto/create-expense.dto.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

@Injectable()
export class ExpensesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async create(organizationId: string, userId: string, dto: CreateExpenseDto) {
    const expense = await this.prisma.tenant.expense.create({
      data: {
        organizationId,
        amount: dto.amount,
        category: dto.category ?? null,
        description: dto.description ?? null,
        expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : new Date(),
        createdById: userId,
      },
    });
    await this.audit.log('CREATE', 'EXPENSE', expense.id, { amount: dto.amount });
    return expense;
  }

  async list(query: PaginationQuery & { category?: string }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.category) where.category = query.category;
    if (query.search) {
      where.OR = [
        { description: { contains: query.search, mode: 'insensitive' } },
        { category: { contains: query.search, mode: 'insensitive' } },
      ];
    }

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.expense.findMany({
        where,
        take,
        skip,
        orderBy: { expenseDate: 'desc' },
        include: { createdBy: { select: { id: true, name: true } } },
      }),
      this.prisma.tenant.expense.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }
}