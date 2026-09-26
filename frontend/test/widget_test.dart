import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_erp/app/app.dart';
import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/core/storage/auth_storage.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(
          baseUrl: 'http://localhost:3000/api/v1',
          storage: const AuthStorage(FlutterSecureStorage()),
        );

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => {
        'items': <dynamic>[],
        'total': 0,
        'page': 1,
        'limit': 20,
      };

  @override
  Future<dynamic> post(String path, {Object? body}) async =>
      throw UnimplementedError('not used in test');

  @override
  Future<dynamic> patch(String path, {Object? body}) async =>
      throw UnimplementedError('not used in test');

  @override
  Future<dynamic> delete(String path) async =>
      throw UnimplementedError('not used in test');
}

void main() {
  testWidgets('app builds with router', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
        child: const App(),
      ),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}