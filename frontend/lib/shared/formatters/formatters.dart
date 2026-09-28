import 'package:intl/intl.dart';

final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
final _dateOnly = DateFormat('yyyy-MM-dd');
final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

String money(dynamic value) {
  final n = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (n == null) return _money.format(0);
  return _money.format(n);
}

String dateOnly(String? value) {
  if (value == null || value.isEmpty) return '-';
  final d = DateTime.tryParse(value);
  return d == null ? value : _dateOnly.format(d.toLocal());
}

String dateTime(String? value) {
  if (value == null || value.isEmpty) return '-';
  final d = DateTime.tryParse(value);
  return d == null ? value : _dateTime.format(d.toLocal());
}

String statusLabel(String status) {
  switch (status) {
    case 'DRAFT':
      return 'Draft';
    case 'SUBMITTED':
      return 'Submitted';
    case 'CONFIRMED':
      return 'Confirmed';
    case 'FULFILLED':
      return 'Fulfilled';
    case 'OPEN':
      return 'Open';
    case 'PARTIALLY_PAID':
      return 'Partially paid';
    case 'PAID':
      return 'Paid';
    case 'CANCELLED':
      return 'Cancelled';
    case 'VOID':
      return 'Void';
    case 'PENDING':
      return 'Pending';
    case 'COMPLETED':
      return 'Completed';
    default:
      return status;
  }
}

// ignore: non_constant_identifier_names
final Map<String, int> _statusColorCode = {
  'DRAFT': 0xFF9E9E9E,
  'SUBMITTED': 0xFF1E88E5,
  'CONFIRMED': 0xFF00897B,
  'OPEN': 0xFF00897B,
  'PARTIALLY_PAID': 0xFFFB8C00,
  'PAID': 0xFF43A047,
  'CANCELLED': 0xFFE53935,
  'VOID': 0xFFE53935,
  'PENDING': 0xFFFFB300,
  'FULFILLED': 0xFF7CB342,
  'COMPLETED': 0xFF43A047,
};

int statusColor(String status) => _statusColorCode[status] ?? 0xFF607D8B;
