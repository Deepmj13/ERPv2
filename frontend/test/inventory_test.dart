import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/features/inventory/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeApiClient api;

  setUp(() {
    api = FakeApiClient(
      responses: {
        '/products': pageOf([
          {
            'id': 'p1',
            'name': 'Widget',
            'sku': 'W-1',
            'salePrice': '10',
            'taxRate': '0',
          },
        ]),
        '/warehouses': pageOf([
          {'id': 'w1', 'name': 'Main'},
          {'id': 'w2', 'name': 'Overflow'},
        ]),
      },
    );
  });

  Future<void> open(WidgetTester tester, StockAction action) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      StockActionDialog(action: action, onSaved: () {}),
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

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pickDropdown(
    WidgetTester tester,
    int index,
    String label,
  ) async {
    await tapVisible(
      tester,
      find.byType(DropdownButtonFormField<String>).at(index),
    );
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> enterQuantity(WidgetTester tester, String value) async {
    final field = find.widgetWithText(TextFormField, 'Quantity *');
    await tapVisible(tester, field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  testWidgets('receive posts a PURCHASE movement', (tester) async {
    await open(tester, StockAction.receive);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await enterQuantity(tester, '25');
    await tapVisible(tester, find.byType(FilledButton));

    final body = api.posts.single.body as Map<String, dynamic>;
    expect(api.posts.single.path, '/inventory/adjustments');
    expect(body['productId'], 'p1');
    expect(body['quantity'], 25.0);
    expect(body['movementType'], 'PURCHASE');
  });

  testWidgets('receive sends the chosen warehouse', (tester) async {
    await open(tester, StockAction.receive);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await pickDropdown(tester, 1, 'Main');
    await enterQuantity(tester, '5');
    await tapVisible(tester, find.byType(FilledButton));

    final body = api.posts.single.body as Map<String, dynamic>;
    expect(body['warehouseId'], 'w1');
  });

  testWidgets('adjust keeps a negative quantity and the movement type', (
    tester,
  ) async {
    await open(tester, StockAction.adjust);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await pickDropdown(tester, 2, 'Return');
    await enterQuantity(tester, '-3');
    await tapVisible(tester, find.byType(FilledButton));

    final body = api.posts.single.body as Map<String, dynamic>;
    expect(api.posts.single.path, '/inventory/adjustments');
    expect(body['quantity'], -3.0);
    expect(body['movementType'], 'RETURN');
  });

  testWidgets('transfer posts both warehouse ids', (tester) async {
    await open(tester, StockAction.transfer);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await pickDropdown(tester, 1, 'Main');
    await pickDropdown(tester, 2, 'Overflow');
    await enterQuantity(tester, '7');
    await tapVisible(tester, find.byType(FilledButton));

    final body = api.posts.single.body as Map<String, dynamic>;
    expect(api.posts.single.path, '/inventory/transfers');
    expect(body['fromWarehouseId'], 'w1');
    expect(body['toWarehouseId'], 'w2');
    expect(body['quantity'], 7.0);
  });

  testWidgets('rejects a zero quantity before calling the API', (tester) async {
    await open(tester, StockAction.receive);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await enterQuantity(tester, '0');
    await tapVisible(tester, find.byType(FilledButton));

    expect(api.posts, isEmpty);
    expect(find.text('Must not be zero'), findsOneWidget);
  });

  testWidgets('rejects a transfer to the same warehouse', (tester) async {
    await open(tester, StockAction.transfer);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await pickDropdown(tester, 1, 'Main');
    await pickDropdown(tester, 2, 'Main');
    await enterQuantity(tester, '4');
    await tapVisible(tester, find.byType(FilledButton));

    expect(api.posts, isEmpty);
  });

  testWidgets('surfaces a rejected write', (tester) async {
    api = FakeApiClient(failWrites: true, responses: api.responses);
    await open(tester, StockAction.receive);
    await pickDropdown(tester, 0, 'Widget (W-1)');
    await enterQuantity(tester, '2');
    await tapVisible(tester, find.byType(FilledButton));

    expect(find.text('Rejected'), findsOneWidget);
  });
}
