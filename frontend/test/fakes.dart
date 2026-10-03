import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/core/storage/auth_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RecordedPost {
  const RecordedPost(this.path, this.body);
  final String path;
  final Object? body;
}

/// In-memory [AuthStorage] so auth flows can be exercised without the
/// flutter_secure_storage platform channel.
class FakeAuthStorage extends AuthStorage {
  FakeAuthStorage({this.access, this.refresh})
    : super(const FlutterSecureStorage());

  String? access;
  String? refresh;

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens(String access, String refresh) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class FakeApiClient extends ApiClient {
  FakeApiClient({
    Map<String, dynamic>? responses,
    this.failWrites = false,
    Map<String, Object>? errors,
    this.storageOverride,
  }) : responses = responses ?? <String, dynamic>{},
       errors = errors ?? <String, Object>{},
       super(
         baseUrl: 'http://localhost:3000/api/v1',
         storage: storageOverride ?? const AuthStorage(FlutterSecureStorage()),
       );

  final Map<String, dynamic> responses;

  /// Thrown instead of returning a response, keyed by path.
  final Map<String, Object> errors;
  final bool failWrites;
  final List<RecordedPost> posts = [];
  final AuthStorage? storageOverride;

  dynamic _respond(String path) {
    final error = errors[path];
    if (error != null) throw error;
    return responses[path] ?? _emptyPage();
  }

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
