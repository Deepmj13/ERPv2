import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/features/audit/audit_screen.dart';
import 'package:basic_erp/features/customers/customers_screen.dart';
import 'package:basic_erp/features/dashboard/dashboard_screen.dart';
import 'package:basic_erp/features/expenses/expenses_screen.dart';
import 'package:basic_erp/features/inventory/inventory_screen.dart';
import 'package:basic_erp/features/payments/payments_screen.dart';
import 'package:basic_erp/features/products/products_screen.dart';
import 'package:basic_erp/features/sales/invoices_screen.dart';
import 'package:basic_erp/features/sales/sales_orders_screen.dart';
import 'package:basic_erp/shared/widgets/common.dart';
import 'package:basic_erp/shared/widgets/sale_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen,
  FakeApiClient api,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final screens = <String, Widget>{
    'customers': const CustomersScreen(),
    'products': const ProductsScreen(),
    'inventory': const InventoryScreen(),
    'sales orders': const SalesOrdersScreen(),
    'invoices': const InvoicesScreen(),
    'payments': const PaymentsScreen(),
    'expenses': const ExpensesScreen(),
    'audit': const AuditScreen(),
  };

  screens.forEach((name, screen) {
    testWidgets('$screen shows an empty state with no data', (tester) async {
      await pumpScreen(tester, screen, FakeApiClient());
      expect(find.byType(EmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('dashboard renders with a zeroed summary', (tester) async {
    await pumpScreen(tester, const DashboardScreen(), FakeApiClient());
    expect(tester.takeException(), isNull);
  });

  group('SaleComposer', () {
    Future<void> openComposer(
      WidgetTester tester,
      FakeApiClient api,
      SaleKind kind,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => SaleComposer(kind: kind, onCreated: (_) {}),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<FakeApiClient> submitComposer(
      WidgetTester tester,
      SaleKind kind,
    ) async {
      final api = FakeApiClient(
        responses: {
          '/customers': pageOf([
            {'id': 'c1', 'name': 'Acme'},
          ]),
          '/products': pageOf([
            {'id': 'p1', 'name': 'Widget', 'salePrice': '10', 'taxRate': '0'},
          ]),
        },
      );
      await openComposer(tester, api, kind);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Widget (stock: 0)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('posts a quotation to /quotations', (tester) async {
      final api = await submitComposer(tester, SaleKind.quotation);
      expect(api.posts.single.path, '/quotations');
    });

    testWidgets('posts an order to /sales-orders', (tester) async {
      final api = await submitComposer(tester, SaleKind.order);
      expect(api.posts.single.path, '/sales-orders');
    });

    testWidgets('posts an invoice to /invoices', (tester) async {
      final api = await submitComposer(tester, SaleKind.invoice);
      expect(api.posts.single.path, '/invoices');
    });

    testWidgets('sends the chosen customer and line items', (tester) async {
      final api = await submitComposer(tester, SaleKind.quotation);
      final body = api.posts.single.body as Map<String, dynamic>;

      expect(body['customerId'], 'c1');
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map<String, dynamic>)['productId'], 'p1');
    });
  });
}
