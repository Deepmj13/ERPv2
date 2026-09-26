import { Prisma } from '@prisma/client';
import { TenantContext } from '../common/tenant/tenant-context.js';

const TENANT_MODELS = new Set([
  'User',
  'Customer',
  'ProductCategory',
  'Unit',
  'Product',
  'Warehouse',
  'StockMovement',
  'DocNumberSequence',
  'Quotation',
  'QuotationItem',
  'SalesOrder',
  'SalesOrderItem',
  'Invoice',
  'InvoiceItem',
  'Payment',
  'Expense',
  'AuditLog',
]);

function hasOrganizationId(args: any): boolean {
  return Boolean(args.where && args.where.organizationId);
}

export const tenantExtension = Prisma.defineExtension((prisma) =>
  prisma.$extends({
    query: {
      $allModels: {
        async $allOperations({ model, operation, args, query }) {
          const ctx = TenantContext.get();
          if (!ctx || !TENANT_MODELS.has(model)) return query(args);

          const a: any = args;
          const orgId = ctx.organizationId;

          switch (operation) {
            case 'create': {
              a.data = { ...a.data, organizationId: orgId };
              break;
            }
            case 'createMany': {
              if (!a.data) break;
              if (Array.isArray(a.data)) {
                a.data = a.data.map((d: any) => ({ ...d, organizationId: orgId }));
              } else {
                a.data = { ...a.data, organizationId: orgId };
              }
              break;
            }
            case 'findUnique': {
              const result: any = await query(a);
              return result && result.organizationId === orgId ? result : null;
            }
            case 'findFirst':
            case 'findMany':
            case 'count':
            case 'aggregate':
            case 'groupBy':
            case 'update':
            case 'updateMany':
            case 'upsert':
            case 'delete':
            case 'deleteMany':
              if (!hasOrganizationId(a)) {
                a.where = { ...a.where, organizationId: orgId };
              }
              break;
            default:
              break;
          }

          return query(a);
        },
      },
    },
  }),
);