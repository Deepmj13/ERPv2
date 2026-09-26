import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuditService } from './audit.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import {
  buildPaginated,
  normalizePagination,
  Paginated,
  PaginationQuery,
} from '../common/utils/pagination.js';

interface AuditQuery extends PaginationQuery {
  entityType?: string;
  action?: string;
}

@ApiTags('audit')
@ApiBearerAuth()
@Controller('audit-logs')
export class AuditController {
  constructor(
    private readonly audit: AuditService,
    private readonly prisma: PrismaService,
  ) {}

  @Get()
  async list(@Query() query: AuditQuery): Promise<Paginated<any>> {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.entityType) where.entityType = query.entityType;
    if (query.action) where.action = query.action;

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.auditLog.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { user: { select: { id: true, name: true, email: true } } },
      }),
      this.prisma.tenant.auditLog.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }
}