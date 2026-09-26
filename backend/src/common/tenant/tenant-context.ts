import { AsyncLocalStorage } from 'node:async_hooks';

export interface TenantContextShape {
  organizationId: string;
  userId: string;
  role: string;
}

export const tenantStorage = new AsyncLocalStorage<TenantContextShape | null>();

export class TenantContext {
  static run<T>(ctx: TenantContextShape | null, fn: () => T): T {
    return tenantStorage.run(ctx, fn);
  }

  static get(): TenantContextShape | null {
    return tenantStorage.getStore() ?? null;
  }
}

export function requireOrgId(): string {
  const ctx = TenantContext.get();
  if (!ctx) throw new Error('Tenant context missing');
  return ctx.organizationId;
}