import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/auth_storage.dart';

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.initialized = false,
    this.errorMessage,
    this.isServerUnreachable = false,
  });

  final Map<String, dynamic>? user;
  final bool isLoading;
  final bool initialized;
  final String? errorMessage;

  /// Set when the last failure was a transport failure (server down, wrong
  /// host, timeout) rather than a rejected request. Drives the retry UI.
  final bool isServerUnreachable;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    Map<String, dynamic>? user,
    bool? isLoading,
    bool? initialized,
    String? errorMessage,
    bool? isServerUnreachable,
    bool clearUser = false,
    bool clearError = false,
  }) => AuthState(
    user: clearUser ? null : user ?? this.user,
    isLoading: isLoading ?? this.isLoading,
    initialized: initialized ?? this.initialized,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    isServerUnreachable: clearError
        ? false
        : isServerUnreachable ?? this.isServerUnreachable,
  );
}

class AuthController extends Notifier<AuthState> {
  ApiClient get _api => ref.read(apiClientProvider);
  AuthStorage get _storage => ref.read(authStorageProvider);

  @override
  AuthState build() {
    _bootstrap();
    return const AuthState(isLoading: true);
  }

  void clearError() {
    if (state.errorMessage == null && !state.isServerUnreachable) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> _bootstrap() async {
    try {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken == null) {
        state = const AuthState(initialized: true);
        return;
      }
      final res = await _api.post(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      state = AuthState(user: _readUser(res), initialized: true);
    } catch (_) {
      try {
        await _storage.clear();
      } catch (_) {}
      state = const AuthState(initialized: true);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.post(
        '/auth/login',
        body: {'email': email, 'password': password},
      );
      final tokens = _readTokens(res);
      await _storage.saveTokens(tokens.$1, tokens.$2);
      state = AuthState(user: _readUser(res), initialized: true);
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      if (state.isLoading) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> register({
    required String organizationName,
    required String organizationSlug,
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.post(
        '/auth/register',
        body: {
          'organizationName': organizationName,
          'organizationSlug': organizationSlug,
          'name': name,
          'email': email,
          'password': password,
        },
      );
      final tokens = _readTokens(res);
      await _storage.saveTokens(tokens.$1, tokens.$2);
      state = AuthState(user: _readUser(res), initialized: true);
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      if (state.isLoading) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/change-password',
      body: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await _storage.clear();
    state = const AuthState(initialized: true);
  }

  void _fail(Object error) {
    final api = error is ApiException ? error : null;
    state = state.copyWith(
      isLoading: false,
      errorMessage: _messageOf(error),
      isServerUnreachable: api?.isConnectionError ?? false,
    );
  }

  static String _messageOf(Object error) {
    if (error is ApiException) return error.message;
    final text = error.toString();
    return text.isEmpty ? 'Something went wrong' : text;
  }

  static Map<String, dynamic>? _readUser(dynamic res) {
    if (res is! Map<String, dynamic>) return null;
    final user = res['user'];
    return user is Map<String, dynamic> ? user : null;
  }

  /// Returns (accessToken, refreshToken), throwing a readable ApiException
  /// instead of a TypeError when the server sends an unexpected body.
  static (String, String) _readTokens(dynamic res) {
    if (res is! Map<String, dynamic>) {
      throw const ApiException(message: 'Unexpected response from the server');
    }
    final access = res['accessToken'];
    final refresh = res['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const ApiException(message: 'Unexpected response from the server');
    }
    return (access, refresh);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
