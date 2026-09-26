import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../storage/auth_storage.dart';
import 'api_config.dart';

class ApiException implements Exception {
  const ApiException({this.statusCode, required this.message});
  final int? statusCode;
  final String message;

  @override
  String toString() => message;
}

final authStorageProvider = Provider<AuthStorage>(
  (ref) => AuthStorage(FlutterSecureStorage()),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: ApiConfig.baseUrl,
    storage: ref.watch(authStorageProvider),
  ),
);

class ApiClient {
  ApiClient({required String baseUrl, required this.storage}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final alreadyRetried =
              error.requestOptions.extra['retried'] == true;
          if (error.response?.statusCode == 401 && !alreadyRetried) {
            error.requestOptions.extra['retried'] = true;
            try {
              await _refreshTokens();
              final token = await storage.readAccessToken();
              if (token != null) {
                error.requestOptions.headers['Authorization'] = 'Bearer $token';
              }
              final response = await _dio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } catch (_) {
              await storage.clear();
            }
            handler.reject(error);
          } else {
            handler.reject(error);
          }
        },
      ),
    );
  }

  late final Dio _dio;
  final AuthStorage storage;

  Future<void> _refreshTokens() async {
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }
    final response = await _dio.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data as Map<String, dynamic>;
    final access = data['accessToken'] as String?;
    final refresh = data['refreshToken'] as String?;
    if (access == null || refresh == null) {
      throw const ApiException(statusCode: 401, message: 'Session expired');
    }
    await storage.saveTokens(access, refresh);
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return res.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<dynamic> post(String path, {Object? body}) async {
    try {
      final res = await _dio.post<dynamic>(path, data: body);
      return res.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    try {
      final res = await _dio.patch<dynamic>(path, data: body);
      return res.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final res = await _dio.delete<dynamic>(path);
      return res.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      if (data['message'] is List) {
        final messages = (data['message'] as List).map((m) => '$m').join(', ');
        return ApiException(
          statusCode: e.response?.statusCode,
          message: messages,
        );
      }
      final message = data['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return ApiException(
          statusCode: e.response?.statusCode,
          message: message,
        );
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const ApiException(message: 'Cannot reach the server');
    }
    return ApiException(
      statusCode: e.response?.statusCode,
      message: e.message ?? 'Request failed',
    );
  }
}