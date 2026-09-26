import { Injectable } from '@nestjs/common';
import { InvoiceStatus, PaymentStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { InventoryService } from '../inventory/inventory.service.js';

@Injectable()
export class DashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly inventory: InventoryService,
  ) {}

  async summary() {
    const now = new Date();
    const startOfMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const endOfMonth = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
    );

    const [totalCustomers, totalProducts, salesThisMonth, outstanding, paymentsThisMonth, expensesThisMonth] =
      await this.prisma.tenant.$transaction([
        this.prisma.tenant.customer.count({ where: { status: 'ACTIVE' } }),
        this.prisma.tenant.product.count({ where: { status: 'ACTIVE' } }),
        this.prisma.tenant.invoice.aggregate({
          where: {
            status: { in: [InvoiceStatus.POSTED, InvoiceStatus.PAID] },
            issueDate: { gte: startOfMonth, lt: endOfMonth },
          },
          _sum: { totalAmount: true },
        }),
        this.prisma.tenant.invoice.aggregate({
          where: { status: InvoiceStatus.POSTED },
          _sum: { totalAmount: true },
          _count: true,
        }),
        this.prisma.tenant.payment.aggregate({
          where: {
            status: PaymentStatus.CONFIRMED,
            paidAt: { gte: startOfMonth, lt: endOfMonth },
          },
          _sum: { amount: true },
        }),
        this.prisma.tenant.expense.aggregate({
          where: { expenseDate: { gte: startOfMonth, lt: endOfMonth } },
          _sum: { amount: true },
        }),
      ]);

    // payments allocated to outstanding invoices reduce the outstanding figure
    const postedPayments = await this.prisma.tenant.payment.aggregate({
      where: { status: PaymentStatus.CONFIRMED },
      _sum: { amount: true },
    });

    const outstandingTotal = new Prisma.Decimal(outstanding._sum.totalAmount ?? 0).sub(
      postedPayments._sum.amount ?? 0,
    );

    const lowStock = await this.inventory.lowStock(10);

    const [recentInvoices, recentPayments] = await this.prisma.tenant.$transaction([
      this.prisma.tenant.invoice.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        include: { customer: true, _count: { select: { payments: true, items: true } } },
      }),
      this.prisma.tenant.payment.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        include: { customer: true, invoice: true },
      }),
    ]);

    return {
      totalCustomers,
      totalProducts,
      salesThisMonth: salesThisMonth._sum.totalAmount ?? 0,
      outstandingInvoices: {
        count: outstanding._count,
        total: outstandingTotal.lt(0) ? 0 : outstandingTotal,
      },
      paymentsThisMonth: paymentsThisMonth._sum.amount ?? 0,
      expensesThisMonth: expensesThisMonth._sum.amount ?? 0,
      lowStockProducts: lowStock,
      recentInvoices,
      recentPayments,
    };
  }
}