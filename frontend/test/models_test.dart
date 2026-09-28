import 'package:basic_erp/shared/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product.fromJson', () {
    test('reads camelCase money keys as strings', () {
      final p = Product.fromJson({
        'id': 'p1',
        'name': 'Widget',
        'sku': 'W-1',
        'salePrice': '19.99',
        'costPrice': '7.50',
        'taxRate': '5',
      });

      expect(p.salePrice, '19.99');
      expect(p.costPrice, '7.50');
      expect(p.taxRate, '5');
    });

    test('flattens nested category and unit relations', () {
      final p = Product.fromJson({
        'id': 'p1',
        'name': 'Widget',
        'category': <String, dynamic>{'id': 'c1', 'name': 'Tools'},
        'unit': <String, dynamic>{'id': 'u1', 'name': 'pcs'},
      });

      expect(p.category, 'Tools');
      expect(p.unit, 'pcs');
    });

    test('parses stock quantity from number, string and legacy key', () {
      expect(
        Product.fromJson({
          'id': 'p',
          'name': 'W',
          'stockQuantity': 4,
        }).stockQuantity,
        4,
      );
      expect(
        Product.fromJson({
          'id': 'p',
          'name': 'W',
          'stockQuantity': '4.5',
        }).stockQuantity,
        4.5,
      );
      expect(
        Product.fromJson({
          'id': 'p',
          'name': 'W',
          'quantity': 12,
        }).stockQuantity,
        12,
      );
      expect(Product.fromJson({'id': 'p', 'name': 'W'}).stockQuantity, isNull);
    });
  });

  group('DocNumber total', () {
    test('prefers totalAmount over total', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'number': 'QUO-2026-00001',
        'status': 'DRAFT',
        'totalAmount': '250.00',
        'total': '999',
      });

      expect(q.total, '250.00');
      expect(q.number, 'QUO-2026-00001');
    });

    test('falls back to total', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'number': 'QUO-2026-00002',
        'status': 'SUBMITTED',
        'total': 42,
      });

      expect(q.total, '42');
    });
  });

  group('Quotation.fromJson', () {
    test('reads customer name and item count from _count', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'number': 'QUO-2026-00001',
        'status': 'DRAFT',
        'customer': <String, dynamic>{'id': 'c1', 'name': 'Acme'},
        '_count': <String, dynamic>{'items': 3},
      });

      expect(q.customerName, 'Acme');
      expect(q.itemCount, 3);
    });

    test('counts items from an inline list when _count is absent', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'number': 'QUO-2026-00001',
        'status': 'DRAFT',
        'items': [
          {'id': 'i1'},
          {'id': 'i2'},
        ],
      });

      expect(q.itemCount, 2);
    });
  });

  group('StockMovement.fromJson', () {
    test('parses decimal string quantity and nested product name', () {
      final m = StockMovement.fromJson({
        'id': 'm1',
        'type': 'SALE',
        'quantity': '-3.5',
        'referenceType': 'INVOICE',
        'product': <String, dynamic>{'id': 'p1', 'name': 'Widget'},
      });

      expect(m.quantity, -3.5);
      expect(m.productName, 'Widget');
      expect(m.reference, 'INVOICE');
    });
  });

  group('PageResult.fromJsonList', () {
    test('maps items and metadata', () {
      final result = PageResult.fromJsonList({
        'items': [
          {'id': 'w1', 'name': 'Main'},
          {'id': 'w2', 'name': 'Overflow'},
        ],
        'total': 2,
        'page': 1,
        'limit': 20,
      }, Warehouse.fromJson);

      expect(result.items.map((w) => w.name), ['Main', 'Overflow']);
      expect(result.total, 2);
      expect(result.hasMore, isFalse);
    });

    test('reports more pages when total exceeds the window', () {
      final result = PageResult.fromJsonList({
        'items': [
          {'id': 'w1', 'name': 'Main'},
        ],
        'total': 45,
        'page': 1,
        'limit': 20,
      }, Warehouse.fromJson);

      expect(result.hasMore, isTrue);
    });

    test('tolerates a missing items list', () {
      final result = PageResult.fromJsonList({}, Warehouse.fromJson);

      expect(result.items, isEmpty);
      expect(result.total, 0);
    });
  });
}
