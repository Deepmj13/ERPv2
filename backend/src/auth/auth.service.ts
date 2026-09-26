import { createHash, randomBytes } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { StringValue } from 'ms';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { TenantContext } from '../common/tenant/tenant-context.js';
import { RegisterDto } from './dto/register.dto.js';
import { LoginDto } from './dto/login.dto.js';
import { ChangePasswordDto } from './dto/change-password.dto.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

interface AuthUser {
  id: string;
  email: string;
  organizationId: string;
  role: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly audit: AuditService,
  ) {}

  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private sanitizeUser(user: any): any {
    const { passwordHash: _passwordHash, ...rest } = user;
    return rest;
  }

  private async issueTokens(user: AuthUser): Promise<TokenPair> {
    const payload = { sub: user.id, email: user.email, org: user.organizationId, role: user.role };
    const accessToken = this.jwt.sign(payload, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: (process.env.JWT_ACCESS_EXPIRES || '15m') as StringValue,
    });
    const refreshToken = randomBytes(48).toString('hex');
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: this.hashToken(refreshToken),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
    return { accessToken, refreshToken };
  }

  async register(dto: RegisterDto) {
    const existing = await this.prisma.user.findFirst({ where: { email: dto.email } });
    if (existing) throw new ConflictException('Email is already registered');

    const slugExists = await this.prisma.organization.findUnique({
      where: { slug: dto.organizationSlug },
    });
    if (slugExists) throw new ConflictException('Organization slug is already taken');

    const passwordHash = await bcrypt.hash(dto.password, 10);

    const created = await this.prisma.$transaction(async (tx) => {
      const organization = await tx.organization.create({
        data: { name: dto.organizationName, slug: dto.organizationSlug },
      });
      const user = await tx.user.create({
        data: {
          organizationId: organization.id,
          name: dto.name,
          email: dto.email,
          passwordHash,
          role: 'ADMIN',
        },
      });
      return { organization, user };
    });

    const tokens = await this.issueTokens(created.user);
    await TenantContext.run(
      { organizationId: created.user.organizationId, userId: created.user.id, role: created.user.role },
      () => this.audit.log('REGISTER', 'USER', created.user.id),
    );

    return {
      user: this.sanitizeUser(created.user),
      organization: created.organization,
      ...tokens,
    };
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findFirst({ where: { email: dto.email } });
    if (!user) throw new UnauthorizedException('Invalid credentials');
    if (user.status === 'DISABLED') throw new UnauthorizedException('Account disabled');

    const ok = await bcrypt.compare(dto.password, user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');

    const tokens = await this.issueTokens(user);
    await TenantContext.run(
      { organizationId: user.organizationId, userId: user.id, role: user.role },
      () => this.audit.log('LOGIN', 'USER', user.id),
    );

    return { user: this.sanitizeUser(user), ...tokens };
  }

  async refresh(refreshToken: string) {
    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({ where: { tokenHash } });
    if (!stored || stored.revokedAt || stored.expiresAt < new Date()) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const user = await this.prisma.user.findUnique({ where: { id: stored.userId } });
    if (!user || user.status === 'DISABLED') throw new UnauthorizedException('Account disabled');

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });

    const tokens = await this.issueTokens(user);
    return { user: this.sanitizeUser(user), ...tokens };
  }

  async logout(refreshToken: string) {
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: this.hashToken(refreshToken) },
    });
    if (stored) {
      await this.prisma.refreshToken.update({
        where: { id: stored.id },
        data: { revokedAt: new Date() },
      });
    }
    return { success: true };
  }

  async me(userId: string, organizationId: string) {
    const user = await this.prisma.tenant.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    const organization = await this.prisma.organization.findUnique({
      where: { id: organizationId },
    });
    return { user: this.sanitizeUser(user), organization };
  }

  async changePassword(userId: string, dto: ChangePasswordDto) {
    const user = await this.prisma.tenant.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    const ok = await bcrypt.compare(dto.oldPassword, user.passwordHash);
    if (!ok) throw new BadRequestException('Current password is incorrect');

    const passwordHash = await bcrypt.hash(dto.newPassword, 10);
    await this.prisma.tenant.user.update({
      where: { id: userId },
      data: { passwordHash },
    });
    return { success: true };
  }
}