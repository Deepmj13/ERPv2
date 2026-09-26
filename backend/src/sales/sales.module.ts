import { Module } from '@nestjs/common';
import { SalesService } from './sales.service.js';
import { QuotationsController } from './quotations.controller.js';
import { SalesOrdersController } from './sales-orders.controller.js';
import { InvoicesController } from './invoices.controller.js';

@Module({
  controllers: [QuotationsController, SalesOrdersController, InvoicesController],
  providers: [SalesService],
})
export class SalesModule {}