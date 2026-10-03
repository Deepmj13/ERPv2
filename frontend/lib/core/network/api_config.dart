import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');
  static const String _hostDefault = 'http://localhost:3000/api/v1';

  /// `localhost` inside the Android emulator points at the emulator itself,
  /// so the host machine is reached through the 10.0.2.2 alias.
  static const String _androidEmulatorDefault = 'http://10.0.2.2:3000/api/v1';

  static String get defaultBaseUrl =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? _androidEmulatorDefault
      : _hostDefault;

  static final String baseUrl = _override.isEmpty ? defaultBaseUrl : _override;
}
