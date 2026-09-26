import { Module } from '@nestjs/common';
import { ProductsService } from './products.service.js';
import { ProductsController, CategoriesController, UnitsController } from './products.controller.js';
import { InventoryModule } from '../inventory/inventory.module.js';

@Module({
  imports: [InventoryModule],
  controllers: [ProductsController, CategoriesController, UnitsController],
  providers: [ProductsService],
})
export class ProductsModule {}