import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { InventoryService } from './inventory.service.js';
import {
  CreateWarehouseDto,
  UpdateWarehouseDto,
  StockAdjustmentDto,
  StockTransferDto,
} from './dto/inventory.dto.js';

@ApiTags('inventory')
@ApiBearerAuth()
@Controller()
export class InventoryController {
  constructor(private readonly inventory: InventoryService) {}

  @Get('warehouses')
  listWarehouses() {
    return this.inventory.listWarehouses();
  }

  @Post('warehouses')
  createWarehouse(@Body() dto: CreateWarehouseDto) {
    return this.inventory.createWarehouse(dto);
  }

  @Patch('warehouses/:id')
  updateWarehouse(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateWarehouseDto) {
    return this.inventory.updateWarehouse(id, dto);
  }

  @Get('inventory/movements')
  listMovements(
    @Query('page') page?: number,
    @Query('limit') limit?: number,
    @Query('productId') productId?: string,
    @Query('warehouseId') warehouseId?: string,
  ) {
    return this.inventory.listMovements({ page, limit, productId, warehouseId });
  }

  @Get('inventory/products/:productId/stock')
  stockBalance(
    @Param('productId', ParseUUIDPipe) productId: string,
    @Query('warehouseId') warehouseId?: string,
  ) {
    return this.inventory.stockBalance(productId, warehouseId);
  }

  @Get('inventory/low-stock')
  lowStock(@Query('threshold') threshold?: number) {
    return this.inventory.lowStock(Number(threshold) || 10);
  }

  @Post('inventory/adjustments')
  adjust(@Body() dto: StockAdjustmentDto) {
    return this.inventory.createAdjustment(dto);
  }

  @Post('inventory/transfers')
  transfer(@Body() dto: StockTransferDto) {
    return this.inventory.transfer(dto);
  }
}