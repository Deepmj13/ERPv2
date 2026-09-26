import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { AuditService } from '../audit/audit.service.js';
import { InventoryService } from '../inventory/inventory.service.js';
import { CreateCategoryDto } from './dto/create-category.dto.js';
import { CreateUnitDto } from './dto/create-unit.dto.js';
import { CreateProductDto } from './dto/create-product.dto.js';
import { UpdateProductDto } from './dto/update-product.dto.js';
import { requireOrgId } from '../common/tenant/tenant-context.js';
import {
  buildPaginated,
  normalizePagination,
  PaginationQuery,
} from '../common/utils/pagination.js';

@Injectable()
export class ProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly inventory: InventoryService,
  ) {}

  async listCategories() {
    return this.prisma.tenant.productCategory.findMany({ orderBy: { name: 'asc' } });
  }

  async createCategory(dto: CreateCategoryDto) {
    try {
      const category = await this.prisma.tenant.productCategory.create({
        data: Object.assign({}, dto, { organizationId: requireOrgId() }),
      });
      await this.audit.log('CREATE', 'CATEGORY', category.id);
      return category;
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException('Category already exists');
      throw error;
    }
  }

  async deleteCategory(id: string) {
    const existing = await this.prisma.tenant.productCategory.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Category not found');
    await this.prisma.tenant.productCategory.delete({ where: { id } });
    await this.audit.log('DELETE', 'CATEGORY', id);
    return { success: true };
  }

  async listUnits() {
    return this.prisma.tenant.unit.findMany({ orderBy: { name: 'asc' } });
  }

  async createUnit(dto: CreateUnitDto) {
    try {
      const unit = await this.prisma.tenant.unit.create({
        data: Object.assign({}, dto, { organizationId: requireOrgId() }),
      });
      await this.audit.log('CREATE', 'UNIT', unit.id);
      return unit;
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException('Unit already exists');
      throw error;
    }
  }

  async listProducts(query: PaginationQuery & { categoryId?: string; status?: string }) {
    const { page, limit, skip, take } = normalizePagination(query);
    const where: any = {};
    if (query.search) {
      where.OR = [
        { name: { contains: query.search, mode: 'insensitive' } },
        { sku: { contains: query.search, mode: 'insensitive' } },
      ];
    }
    if (query.categoryId) where.categoryId = query.categoryId;
    if (query.status) where.status = query.status;

    const [items, total] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.product.findMany({
        where,
        take,
        skip,
        orderBy: { createdAt: 'desc' },
        include: { category: true, unit: true },
      }),
      this.prisma.tenant.product.count({ where }),
    ]);
    const stock = await this.inventory.stockForProducts(items.map((p) => p.id));
    const enriched = items.map((p) => {
      const { costPrice, ...rest } = p;
      return { ...rest, costPrice, stock: stock.get(p.id) ?? 0 };
    });
    return buildPaginated(enriched, total, page, limit);
  }

  async getOne(id: string) {
    const product = await this.prisma.tenant.product.findUnique({
      where: { id },
      include: { category: true, unit: true },
    });
    if (!product) throw new NotFoundException('Product not found');
    const stock = await this.inventory.stockForProducts([id]);
    return { ...product, stock: stock.get(id) ?? 0 };
  }

  async create(dto: CreateProductDto) {
    try {
      const product = await this.prisma.tenant.product.create({
        data: {
          organizationId: requireOrgId(),
          name: dto.name,
          sku: dto.sku,
          categoryId: dto.categoryId ?? null,
          unitId: dto.unitId ?? null,
          salePrice: dto.salePrice,
          costPrice: dto.costPrice,
          taxRate: dto.taxRate ?? 0,
        },
      });
      await this.audit.log('CREATE', 'PRODUCT', product.id);
      return product;
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException('SKU already exists');
      throw error;
    }
  }

  async update(id: string, dto: UpdateProductDto) {
    const existing = await this.prisma.tenant.product.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Product not found');

    const data: any = Object.assign({}, dto);
    if (dto.categoryId === undefined) data.categoryId = undefined;
    if (dto.unitId === undefined) data.unitId = undefined;

    try {
      const product = await this.prisma.tenant.product.update({ where: { id }, data });
      await this.audit.log('UPDATE', 'PRODUCT', id);
      return product;
    } catch (error: any) {
      if (error?.code === 'P2002') throw new ConflictException('SKU already exists');
      throw error;
    }
  }

  async setStatus(id: string, status: 'ACTIVE' | 'DISABLED') {
    const existing = await this.prisma.tenant.product.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Product not found');
    const product = await this.prisma.tenant.product.update({ where: { id }, data: { status } });
    await this.audit.log('UPDATE', 'PRODUCT', id, { status });
    return product;
  }
}