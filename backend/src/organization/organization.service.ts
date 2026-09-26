import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { UpdateOrganizationDto } from './dto/update-organization.dto.js';

@Injectable()
export class OrganizationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async profile(organizationId: string) {
    const organization = await this.prisma.organization.findUnique({
      where: { id: organizationId },
      include: { users: { select: { id: true, name: true, email: true, role: true, status: true } } },
    });
    if (!organization) throw new NotFoundException('Organization not found');
    return organization;
  }

  async update(organizationId: string, dto: UpdateOrganizationDto) {
    const organization = await this.prisma.organization.update({
      where: { id: organizationId },
      data: dto,
    });
    await this.audit.log('UPDATE', 'ORGANIZATION', organizationId);
    return organization;
  }
}