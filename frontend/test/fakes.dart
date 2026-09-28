import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/core/storage/auth_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RecordedPost {
  const RecordedPost(this.path, this.body);
  final String path;
  final Object? body;
}

class FakeApiClient extends ApiClient {
  FakeApiClient({Map<String, dynamic>? responses, this.failWrites = false})
    : responses = responses ?? const {},
      super(
        baseUrl: 'http://localhost:3000/api/v1',
        storage: const AuthStorage(FlutterSecureStorage()),
      );

  final Map<String, dynamic> responses;
  final bool failWrites;
  final List<RecordedPost> posts = [];

  dynamic _respond(String path) => responses[path] ?? _emptyPage();

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _respond(path);

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    posts.add(RecordedPost(path, body));
    if (failWrites) {
      throw const ApiException(statusCode: 400, message: 'Rejected');
    }
    return _respond(path);
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    posts.add(RecordedPost(path, body));
    if (failWrites) {
      throw const ApiException(statusCode: 400, message: 'Rejected');
    }
    return _respond(path);
  }

  @override
  Future<dynamic> delete(String path) async => _respond(path);

  static Map<String, dynamic> _emptyPage() => {
    'items': <dynamic>[],
    'total': 0,
    'page': 1,
    'limit': 20,
  };
}

Map<String, dynamic> pageOf(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'limit': 20,
};
