import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { CreateUserDto } from './dto/create-user.dto.js';
import { UpdateUserDto, ResetPasswordDto } from './dto/update-user.dto.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  private sanitize(user: any): any {
    const { passwordHash: _passwordHash, ...rest } = user;
    return rest;
  }

  async list(query: PaginationQuery & { role?: Role }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.search) {
      where.OR = [
        { name: { contains: query.search, mode: 'insensitive' } },
        { email: { contains: query.search, mode: 'insensitive' } },
      ];
    }
    if (query.role) where.role = query.role;

    const items = await this.prisma.tenant.user.findMany({
      where,
      take,
      skip,
      orderBy: { createdAt: 'desc' },
    });
    const total = await this.prisma.tenant.user.count({ where });
    return buildPaginated(items.map((u) => this.sanitize(u)), total, page, limit);
  }

  async create(organizationId: string, dto: CreateUserDto) {
    const existing = await this.prisma.tenant.user.findFirst({ where: { email: dto.email } });
    if (existing) throw new ConflictException('Email already exists in this organization');

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.prisma.tenant.user.create({
      data: {
        organizationId,
        name: dto.name,
        email: dto.email,
        passwordHash,
        role: dto.role,
      },
    });
    await this.audit.log('CREATE', 'USER', user.id, { role: dto.role });
    return this.sanitize(user);
  }

  async update(id: string, dto: UpdateUserDto) {
    const user = await this.prisma.tenant.user.findFirst({ where: { id } });
    if (!user) throw new NotFoundException('User not found');

    const updated = await this.prisma.tenant.user.update({ where: { id }, data: dto });
    if (dto.role && dto.role !== user.role) {
      await this.audit.log('USER_ROLE_CHANGE', 'USER', id, {
        from: user.role,
        to: dto.role,
      });
    } else {
      await this.audit.log('UPDATE', 'USER', id);
    }
    return this.sanitize(updated);
  }

  async resetPassword(id: string, dto: ResetPasswordDto) {
    const user = await this.prisma.tenant.user.findFirst({ where: { id } });
    if (!user) throw new NotFoundException('User not found');

    const passwordHash = await bcrypt.hash(dto.newPassword, 10);
    await this.prisma.tenant.user.update({ where: { id }, data: { passwordHash } });
    await this.audit.log('PASSWORD_RESET', 'USER', id);
    return { success: true };
  }
}