import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/auth_storage.dart';

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.initialized = false,
    this.errorMessage,
  });

  final Map<String, dynamic>? user;
  final bool isLoading;
  final bool initialized;
  final String? errorMessage;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    Map<String, dynamic>? user,
    bool? isLoading,
    bool? initialized,
    String? errorMessage,
    bool clearUser = false,
  }) =>
      AuthState(
        user: clearUser ? null : user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        initialized: initialized ?? this.initialized,
        errorMessage: errorMessage ?? this.errorMessage,
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

  Future<void> _bootstrap() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) {
      state = const AuthState(initialized: true);
      return;
    }
    try {
      final res = await _api.post(
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
      );
      state = AuthState(
        user: res == null ? null : (res['user'] as Map<String, dynamic>?),
        initialized: true,
      );
    } catch (_) {
      await _storage.clear();
      state = const AuthState(initialized: true);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _api.post(
        '/auth/login',
        body: {'email': email, 'password': password},
      );
      await _storage.saveTokens(
        res['accessToken'] as String,
        res['refreshToken'] as String,
      );
      state = AuthState(
        user: res['user'] as Map<String, dynamic>?,
        initialized: true,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      rethrow;
    }
  }

  Future<void> register({
    required String organizationName,
    required String organizationSlug,
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
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
      await _storage.saveTokens(
        res['accessToken'] as String,
        res['refreshToken'] as String,
      );
      state = AuthState(
        user: res['user'] as Map<String, dynamic>?,
        initialized: true,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      rethrow;
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
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);