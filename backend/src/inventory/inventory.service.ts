import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { MovementType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import {
  CreateWarehouseDto,
  UpdateWarehouseDto,
  StockAdjustmentDto,
  StockTransferDto,
} from './dto/inventory.dto.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';
import { requireOrgId } from '../common/tenant/tenant-context.js';

@Injectable()
export class InventoryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async listWarehouses() {
    return this.prisma.tenant.warehouse.findMany({ orderBy: { name: 'asc' } });
  }

  async createWarehouse(dto: CreateWarehouseDto) {
    const warehouse = await this.prisma.tenant.warehouse.create({
      data: Object.assign({}, dto, { organizationId: requireOrgId() }),
    });
    await this.audit.log('CREATE', 'WAREHOUSE', warehouse.id);
    return warehouse;
  }

  async updateWarehouse(id: string, dto: UpdateWarehouseDto) {
    const existing = await this.prisma.tenant.warehouse.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Warehouse not found');
    const warehouse = await this.prisma.tenant.warehouse.update({ where: { id }, data: dto });
    await this.audit.log('UPDATE', 'WAREHOUSE', id);
    return warehouse;
  }

  async stockForProducts(productIds: string[]): Promise<Map<string, Prisma.Decimal>> {
    if (productIds.length === 0) return new Map();
    const rows = await this.prisma.tenant.stockMovement.groupBy({
      by: ['productId'],
      where: { productId: { in: productIds } },
      _sum: { quantity: true },
    });
    return new Map(rows.map((r) => [r.productId, r._sum.quantity ?? new Prisma.Decimal(0)]));
  }

  async stockBalance(productId: string, warehouseId?: string) {
    const product = await this.prisma.tenant.product.findUnique({ where: { id: productId } });
    if (!product) throw new NotFoundException('Product not found');

    const where: any = { productId };
    if (warehouseId) where.warehouseId = warehouseId;

    const [rows, recent] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.stockMovement.aggregate({ where, _sum: { quantity: true } }),
      this.prisma.tenant.stockMovement.findMany({
        where,
        take: 10,
        orderBy: { createdAt: 'desc' },
      }),
    ]);
    return { productId, warehouseId: warehouseId ?? null, balance: rows._sum.quantity ?? 0, recent };
  }

  async listMovements(query: PaginationQuery & { productId?: string; warehouseId?: string }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.productId) where.productId = query.productId;
    if (query.warehouseId) where.warehouseId = query.warehouseId;

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.stockMovement.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { product: { select: { id: true, name: true, sku: true } }, warehouse: true },
      }),
      this.prisma.tenant.stockMovement.count({ where }),
    ]);
    return buildPaginated(items, total, page, limit);
  }

  async createAdjustment(dto: StockAdjustmentDto) {
    if (dto.quantity === 0) throw new BadRequestException('Quantity must not be zero');
    const movementType = dto.movementType ?? MovementType.ADJUSTMENT;
    const movement = await this.prisma.tenant.stockMovement.create({
      data: {
        organizationId: requireOrgId(),
        productId: dto.productId,
        warehouseId: dto.warehouseId ?? null,
        movementType,
        quantity: dto.quantity,
        referenceType: 'STOCK_ADJUSTMENT',
        note: dto.note,
      },
    });
    await this.audit.log('STOCK_ADJUST', 'PRODUCT', dto.productId, {
      movementId: movement.id,
      quantity: dto.quantity,
    });
    return movement;
  }

  async transfer(dto: StockTransferDto) {
    if (dto.fromWarehouseId === dto.toWarehouseId) {
      throw new BadRequestException('Source and destination warehouse must differ');
    }

    const from = await this.prisma.tenant.warehouse.findUnique({ where: { id: dto.fromWarehouseId } });
    const to = await this.prisma.tenant.warehouse.findUnique({ where: { id: dto.toWarehouseId } });
    if (!from || !to) throw new NotFoundException('Warehouse not found');

    await this.prisma.tenant.stockMovement.createMany({
      data: [
        {
          organizationId: requireOrgId(),
          productId: dto.productId,
          warehouseId: dto.fromWarehouseId,
          movementType: MovementType.TRANSFER_OUT,
          quantity: new Prisma.Decimal(dto.quantity).negated(),
          referenceType: 'TRANSFER',
        },
        {
          organizationId: requireOrgId(),
          productId: dto.productId,
          warehouseId: dto.toWarehouseId,
          movementType: MovementType.TRANSFER_IN,
          quantity: new Prisma.Decimal(dto.quantity),
          referenceType: 'TRANSFER',
        },
      ],
    });
    await this.audit.log('STOCK_ADJUST', 'PRODUCT', dto.productId, {
      type: 'TRANSFER',
      quantity: dto.quantity,
      from: dto.fromWarehouseId,
      to: dto.toWarehouseId,
    });
    return { success: true };
  }

  async lowStock(threshold: number) {
    const rows = await this.prisma.tenant.stockMovement.groupBy({ by: ['productId'] });
    const map = await this.stockForProducts(rows.map((r) => r.productId));
    const low: any[] = [];

    for (const [productId, stock] of map) {
      if (Number(stock) <= threshold) {
        const product = await this.prisma.tenant.product.findUnique({
          where: { id: productId },
          select: { id: true, name: true, sku: true, salePrice: true },
        });
        if (product) low.push({ ...product, stock });
      }
    }
    return low.sort((a, b) => Number(a.stock) - Number(b.stock));
  }
}