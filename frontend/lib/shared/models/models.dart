class PageResult<T> {
  const PageResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<T> items;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => page * limit < total;

  static PageResult<T> fromJsonList<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) mapper,
  ) {
    final items = (json['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(mapper)
        .toList();
    return PageResult(
      items: items,
      total: json['total'] as int? ?? items.length,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 20,
    );
  }
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.status,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? status;
  final String? createdAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String? ?? 'MEMBER',
        status: json['status'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
      );
}

class Category {
  const Category({required this.id, required this.name});
  final String id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as String, name: json['name'] as String);
}

class Unit {
  const Unit({required this.id, required this.name, this.abbreviation});
  final String id;
  final String name;
  final String? abbreviation;

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        id: json['id'] as String,
        name: json['name'] as String,
        abbreviation: json['abbreviation'] as String?,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.sku,
    this.category,
    this.unit,
    this.salePrice,
    this.costPrice,
    this.taxRate,
    this.stockQuantity,
    this.active,
  });

  final String id;
  final String name;
  final String? sku;
  final String? category;
  final String? unit;
  final String? salePrice;
  final String? costPrice;
  final String? taxRate;
  final num? stockQuantity;
  final bool? active;

  factory Product.fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final unit = json['unit'];
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      category: category is Map<String, dynamic>
          ? category['name'] as String?
          : category?.toString(),
      unit: unit is Map<String, dynamic>
          ? unit['name'] as String?
          : unit?.toString(),
      salePrice: json['salePrice']?.toString(),
      costPrice: json['costPrice']?.toString(),
      taxRate: json['taxRate']?.toString(),
      stockQuantity: (json['stockQuantity'] ?? json['quantity']) is String
          ? num.tryParse(json['stockQuantity'].toString())
          : (json['stockQuantity'] ?? json['quantity']) as num?,
      active: json['active'] as bool?,
    );
  }
}

class Warehouse {
  const Warehouse({required this.id, required this.name, this.location});
  final String id;
  final String name;
  final String? location;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String?,
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.type,
    required this.quantity,
    this.reference,
    this.note,
    this.createdAt,
    this.productId,
    this.productName,
  });

  final String id;
  final String type;
  final num quantity;
  final String? reference;
  final String? note;
  final String? createdAt;
  final String? productId;
  final String? productName;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return StockMovement(
      id: json['id'] as String,
      type: json['type'] as String,
      quantity: json['quantity'] is String
          ? num.parse(json['quantity'] as String)
          : json['quantity'] as num,
      reference: json['reference'] as String?,
      note: json['note'] as String?,
      createdAt: json['createdAt'] as String?,
      productId: json['productId'] as String?,
      productName: product is Map<String, dynamic>
          ? product['name'] as String?
          : null,
    );
  }
}

class DocNumber {
  const DocNumber({required this.number, required this.status, this.total});
  final String number;
  final String status;
  final String? total;

  factory DocNumber.fromJson(Map<String, dynamic> json) => DocNumber(
        number: json['number'] as String,
        status: json['status'] as String? ?? '',
        total: json['']?.toString() ??
            json['']?.toString(),
      );
}

class Quotation extends DocNumber {
  const Quotation({
    required super.number,
    required super.status,
    super.total,
    required this.id,
    this.customerId,
    this.customerName,
    this.itemCount,
  });

  final String id;
  final String? customerId;
  final String? customerName;
  final int? itemCount;

  factory Quotation.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    return Quotation(
      id: json['id'] as String,
      number: json['number'] as String,
      status: json['status'] as String? ?? '',
      total: json['']?.toString(),
      customerId: json['customerId'] as String?,
      customerName: customer is Map<String, dynamic>
          ? customer['name'] as String?
          : null,
      itemCount: (json['items'] as List?)?.length ?? json['itemCount'] as int?,
    );
  }
}

class SalesOrder extends DocNumber {
  const SalesOrder({
    required super.number,
    required super.status,
    super.total,
    required this.id,
    this.customerName,
  });

  final String id;
  final String? customerName;

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    return SalesOrder(
      id: json['id'] as String,
      number: json['number'] as String,
      status: json['status'] as String? ?? '',
      total: json['']?.toString(),
      customerName: customer is Map<String, dynamic>
          ? customer['name'] as String?
          : null,
    );
  }
}

class Invoice extends DocNumber {
  const Invoice({
    required super.number,
    required super.status,
    super.total,
    required this.id,
    this.customerName,
    this.outstanding,
    this.paidAt,
  });

  final String id;
  final String? customerName;
  final String? outstanding;
  final String? paidAt;

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    return Invoice(
      id: json['id'] as String,
      number: json['number'] as String,
      status: json['status'] as String? ?? '',
      total: json['']?.toString(),
      customerName: customer is Map<String, dynamic>
          ? customer['name'] as String?
          : null,
      outstanding: json['']?.toString(),
      paidAt: json['paidAt'] as String?,
    );
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.number,
    required this.amount,
    required this.method,
    this.status,
    this.invoiceNumber,
    this.createdAt,
  });

  final String id;
  final String number;
  final String amount;
  final String method;
  final String? status;
  final String? invoiceNumber;
  final String? createdAt;

  factory Payment.fromJson(Map<String, dynamic> json) {
    final invoice = json['invoice'];
    return Payment(
      id: json['id'] as String,
      number: json['number'] as String,
      amount: json['']?.toString() ?? '0',
      method: json['method'] as String? ?? '',
      status: json['status'] as String?,
      invoiceNumber: invoice is Map<String, dynamic>
          ? invoice['number'] as String?
          : null,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    this.action,
    this.entityType,
    this.entityId,
    this.actorName,
    this.createdAt,
  });

  final String id;
  final String? action;
  final String? entityType;
  final String? entityId;
  final String? actorName;
  final String? createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    return AuditLogEntry(
      id: json['id'] as String,
      action: json['action'] as String?,
      entityType: json['entityType'] as String?,
      entityId: json['entityId'] as String?,
      actorName: actor is Map<String, dynamic>
          ? actor['name'] as String?
          : null,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    this.totalCustomers,
    this.totalProducts,
    this.totalInvoices,
    this.totalRevenue,
    this.dueAmount,
    this.openQuotations,
    this.lowStock,
    this.salesThisMonth,
    this.receiptsThisMonth,
  });

  final num? totalCustomers;
  final num? totalProducts;
  final num? totalInvoices;
  final String? totalRevenue;
  final String? dueAmount;
  final num? openQuotations;
  final num? lowStock;
  final String? salesThisMonth;
  final String? receiptsThisMonth;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalCustomers: json['totalCustomers'] as num?,
        totalProducts: json['totalProducts'] as num?,
        totalInvoices: json['totalInvoices'] as num?,
        totalRevenue: json['']?.toString(),
        dueAmount: json['']?.toString(),
        openQuotations: json['openQuotations'] as num?,
        lowStock: json['lowStockCount'] as num? ?? json['lowStock'] as num?,
        salesThisMonth: json['']?.toString(),
        receiptsThisMonth: json['']?.toString(),
      );
}