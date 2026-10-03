import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../storage/auth_storage.dart';
import 'api_config.dart';

class ApiException implements Exception {
  const ApiException({
    this.statusCode,
    required this.message,
    this.isConnectionError = false,
  });
  final int? statusCode;
  final String message;

  /// True when the request never reached the server (offline, wrong host,
  /// connection refused, timeout). Drives the retry affordance in the UI.
  final bool isConnectionError;

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
    _refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
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
          String? token;
          try {
            token = await storage.readAccessToken();
          } catch (_) {}
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final alreadyRetried = error.requestOptions.extra['retried'] == true;
          final path = error.requestOptions.path;
          final canRefresh =
              error.response?.statusCode == 401 &&
              !alreadyRetried &&
              !_isAuthEndpoint(path);
          if (canRefresh) {
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

  static bool _isAuthEndpoint(String path) =>
      path.endsWith('/auth/login') ||
      path.endsWith('/auth/register') ||
      path.endsWith('/auth/refresh') ||
      path.endsWith('/auth/change-password');

  late final Dio _dio;
  late final Dio _refreshDio;
  Future<void>? _refreshInFlight;
  final AuthStorage storage;

  /// Refreshes through a bare, interceptor-free client so a failing refresh
  /// can never re-enter [onError] and recurse forever.
  Future<void> _refreshTokens() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _doRefresh() async {
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }
    final response = await _refreshDio.post<dynamic>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        statusCode: 401,
        message: 'Unexpected response from the server',
      );
    }
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const ApiException(statusCode: 401, message: 'Session expired');
    }
    await storage.saveTokens(access, refresh);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
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
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      if (data['message'] is List) {
        final messages = (data['message'] as List).map((m) => '$m').join(', ');
        return ApiException(statusCode: status, message: messages);
      }
      final message = data['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return ApiException(statusCode: status, message: message);
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(
          message: 'Cannot reach the server',
          isConnectionError: true,
        );
      case DioExceptionType.cancel:
        return const ApiException(message: 'Request cancelled');
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'The server certificate could not be verified',
          isConnectionError: true,
        );
      case DioExceptionType.transformTimeout:
        return const ApiException(
          message: 'The server took too long to respond',
          isConnectionError: true,
        );
      case DioExceptionType.badResponse:
        return ApiException(
          statusCode: status,
          message: _serverMessage(status),
        );
      case DioExceptionType.unknown:
        final detail = e.error?.toString();
        return ApiException(
          statusCode: status,
          message: (detail == null || detail.isEmpty)
              ? 'Request failed'
              : 'Request failed: $detail',
        );
    }
  }

  static String _serverMessage(int? status) {
    if (status == null) return 'Request failed';
    if (status == 429) return 'Too many requests. Please wait a moment.';
    if (status >= 500) return 'The server ran into a problem ($status).';
    return 'Request failed ($status).';
  }
}
