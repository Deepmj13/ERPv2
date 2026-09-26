import 'package:flutter_riverpod/flutter_riverpod.dart';

class StringNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class NullableStringNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}