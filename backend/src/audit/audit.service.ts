import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { TenantContext } from '../common/tenant/tenant-context.js';

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async log(
    action: string,
    entityType: string,
    entityId?: string,
    metadata?: Record<string, unknown>,
  ): Promise<void> {
    const ctx = TenantContext.get();
    if (!ctx) return;
    await this.prisma.tenant.auditLog.create({
      data: {
        organizationId: ctx.organizationId,
        userId: ctx.userId,
        action,
        entityType,
        entityId,
        metadata,
      },
    });
  }
}