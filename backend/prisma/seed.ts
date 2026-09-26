import { PrismaClient, Role } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  const orgEmail = 'acme@example.com';
  const existing = await prisma.organization.findUnique({ where: { slug: 'acme' } });
  if (existing) {
    console.log('Seed already applied (org slug=acme). Nothing to do.');
    return;
  }

  const passwordHash = await bcrypt.hash('Admin@123', 10);

  const org = await prisma.organization.create({
    data: {
      name: 'Acme Corp',
      slug: 'acme',
      email: orgEmail,
      phone: '+1-555-0100',
      address: '1 Main Street, Springfield',
      currency: 'USD',
      timezone: 'America/New_York',
    },
  });

  const admin = await prisma.user.create({
    data: {
      organizationId: org.id,
      name: 'Admin',
      email: 'admin@acme.com',
      passwordHash,
      role: Role.ADMIN,
    },
  });

  const rawCategory = await prisma.productCategory.create({
    data: { organizationId: org.id, name: 'Raw Materials' },
  });
  const finishedCategory = await prisma.productCategory.create({
    data: { organizationId: org.id, name: 'Finished Goods' },
  });

  const pc = await prisma.unit.create({
    data: { organizationId: org.id, name: 'Piece', abbreviation: 'pcs' },
  });
  const kg = await prisma.unit.create({
    data: { organizationId: org.id, name: 'Kilogram', abbreviation: 'kg' },
  });

  const steel = await prisma.product.create({
    data: {
      organizationId: org.id,
      categoryId: rawCategory.id,
      unitId: kg.id,
      name: 'Steel Sheet 2mm',
      sku: 'RM-STEEL-2',
      salePrice: 25,
      costPrice: 18,
      taxRate: 10,
    },
  });
  const widget = await prisma.product.create({
    data: {
      organizationId: org.id,
      categoryId: finishedCategory.id,
      unitId: pc.id,
      name: 'Standard Widget',
      sku: 'FG-WIDGET-1',
      salePrice: 45.5,
      costPrice: 28,
      taxRate: 10,
    },
  });

  const warehouse = await prisma.warehouse.create({
    data: { organizationId: org.id, name: 'Main Warehouse', location: 'Springfield' },
  });

  const customer = await prisma.customer.create({
    data: {
      organizationId: org.id,
      name: 'Global Traders LLC',
      email: 'orders@globaltraders.com',
      phone: '+1-555-0143',
      address: '45 Harbor Road, Springfield',
      taxNumber: 'TAX-8841',
    },
  });

  await prisma.stockMovement.createMany({
    data: [
      {
        organizationId: org.id,
        productId: steel.id,
        warehouseId: warehouse.id,
        movementType: 'PURCHASE',
        quantity: 150,
        referenceType: 'INITIAL_STOCK',
        note: 'Opening stock',
      },
      {
        organizationId: org.id,
        productId: widget.id,
        warehouseId: warehouse.id,
        movementType: 'PURCHASE',
        quantity: 80,
        referenceType: 'INITIAL_STOCK',
        note: 'Opening stock',
      },
    ],
  });

  console.log(
    `Seeded org "${org.slug}" with admin ${admin.email} (password: Admin@123) and sample master data.`,
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());