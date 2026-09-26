import { Injectable, NestMiddleware } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { NextFunction, Request, Response } from 'express';
import { TenantContext } from './tenant-context.js';

@Injectable()
export class TenantContextMiddleware implements NestMiddleware {
  constructor(private readonly jwt: JwtService) {}

  use(req: Request, _res: Response, next: NextFunction): void {
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
      try {
        const payload = this.jwt.verify(header.slice(7), {
          secret: process.env.JWT_ACCESS_SECRET,
        });
        if (
          payload &&
          typeof payload === 'object' &&
          (payload as any).sub &&
          (payload as any).org &&
          (payload as any).role
        ) {
          TenantContext.run(
            {
              organizationId: (payload as any).org,
              userId: (payload as any).sub,
              role: (payload as any).role,
            },
            next,
          );
          return;
        }
      } catch {
        // invalid token -> handled by JwtAuthGuard; run without context
      }
    }
    TenantContext.run(null, next);
  }
}