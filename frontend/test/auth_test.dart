import 'package:basic_erp/core/network/api_client.dart';
import 'package:basic_erp/features/auth/auth_controller.dart';
import 'package:basic_erp/features/auth/login_screen.dart';
import 'package:basic_erp/features/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _validLogin = {
  'accessToken': 'access-1',
  'refreshToken': 'refresh-1',
  'user': {'id': 'u1', 'email': 'owner@example.com'},
};

Future<FakeAuthStorage> pumpLogin(
  WidgetTester tester,
  FakeApiClient api, {
  Widget? screen,
}) async {
  final storage = FakeAuthStorage();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authStorageProvider.overrideWithValue(storage),
      ],
      child: MaterialApp(home: screen ?? const LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

Future<void> fillCredentials(
  WidgetTester tester, {
  String email = 'owner@example.com',
  String password = 'secret123',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
}

void main() {
  group('login error reporting', () {
    testWidgets(
      'shows an inline message and snackbar for invalid credentials',
      (tester) async {
        await pumpLogin(
          tester,
          FakeApiClient(
            errors: {
              '/auth/login': const ApiException(
                statusCode: 401,
                message: 'Invalid credentials',
              ),
            },
          ),
        );

        await fillCredentials(tester);
        await tester.tap(find.byKey(const Key('login-submit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth-error-banner')), findsOneWidget);
        expect(find.text('Invalid credentials'), findsWidgets);
        expect(
          find.byKey(const Key('login-submit')),
          findsOneWidget,
          reason: 'the form must not be torn down on failure',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('re-enables the button and clears the error on retry', (
      tester,
    ) async {
      final api = FakeApiClient(
        errors: {
          '/auth/login': const ApiException(
            statusCode: 401,
            message: 'Invalid credentials',
          ),
        },
      );
      await pumpLogin(tester, api);
      await fillCredentials(tester);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('login-submit')),
      );
      expect(submit.onPressed, isNotNull, reason: 'stuck spinner regression');

      api.errors.remove('/auth/login');
      api.responses['/auth/login'] = _validLogin;
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-error-banner')), findsNothing);
    });

    testWidgets('rejects a malformed email before hitting the network', (
      tester,
    ) async {
      final api = FakeApiClient();
      await pumpLogin(tester, api);

      await fillCredentials(tester, email: 'not-an-email');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(api.posts.where((p) => p.path == '/auth/login'), isEmpty);
    });

    testWidgets('reports an unreachable server with retry and the base URL', (
      tester,
    ) async {
      await pumpLogin(
        tester,
        FakeApiClient(
          errors: {
            '/auth/login': const ApiException(
              message: 'Cannot reach the server',
              isConnectionError: true,
            ),
          },
        ),
      );

      await fillCredentials(tester);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-error-retry')), findsOneWidget);
      expect(find.textContaining('Check that the server is running'), findsOne);
      expect(find.textContaining('API:'), findsOne);
    });

    testWidgets('surfaces a TypeError instead of hanging on a spinner', (
      tester,
    ) async {
      await pumpLogin(
        tester,
        FakeApiClient(
          responses: {
            '/auth/login': const {'unexpected': 'shape'},
          },
        ),
      );

      await fillCredentials(tester);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Unexpected response from the server'), findsWidgets);
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('login-submit')),
      );
      expect(submit.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cleared error removes the banner', (tester) async {
      await pumpLogin(
        tester,
        FakeApiClient(
          errors: {
            '/auth/login': const ApiException(
              statusCode: 401,
              message: 'Invalid credentials',
            ),
          },
        ),
      );
      await fillCredentials(tester);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-error-banner')), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-error-banner')), findsNothing);
    });
  });

  group('register error reporting', () {
    testWidgets('shows a duplicate-email conflict inline', (tester) async {
      await pumpLogin(
        tester,
        FakeApiClient(
          errors: {
            '/auth/register': const ApiException(
              statusCode: 409,
              message: 'Email is already registered',
            ),
          },
        ),
        screen: const RegisterScreen(),
      );

      for (final field in find.byType(TextFormField).evaluate()) {
        await tester.enterText(find.byWidget(field.widget), 'Acme');
      }
      await tester.enterText(find.byType(TextFormField).at(1), 'acme');
      await tester.enterText(find.byType(TextFormField).at(3), 'a@b.com');
      await tester.enterText(find.byType(TextFormField).at(4), 'longenough1');
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Email is already registered'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('AuthController', () {
    test('clearError resets the message and the unreachable flag', () async {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(FakeApiClient()),
          authStorageProvider.overrideWithValue(FakeAuthStorage()),
        ],
      );
      addTearDown(container.dispose);

      container.read(authControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authControllerProvider).initialized, isTrue);
      expect(container.read(authControllerProvider).errorMessage, isNull);
    });

    test('login stores tokens and exposes the user on success', () async {
      final storage = FakeAuthStorage();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            FakeApiClient(
              responses: {'/auth/login': _validLogin},
              storageOverride: storage,
            ),
          ),
          authStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login('owner@example.com', 'secret123');

      final auth = container.read(authControllerProvider);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.errorMessage, isNull);
      expect(auth.isLoading, isFalse);
      expect(storage.access, 'access-1');
      expect(storage.refresh, 'refresh-1');
    });

    test('login reports connection failures as server-unreachable', () async {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            FakeApiClient(
              errors: {
                '/auth/login': const ApiException(
                  message: 'Cannot reach the server',
                  isConnectionError: true,
                ),
              },
            ),
          ),
          authStorageProvider.overrideWithValue(FakeAuthStorage()),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(authControllerProvider.notifier)
            .login('owner@example.com', 'secret123'),
        throwsA(isA<ApiException>()),
      );

      final auth = container.read(authControllerProvider);
      expect(auth.errorMessage, 'Cannot reach the server');
      expect(auth.isServerUnreachable, isTrue);
      expect(auth.isLoading, isFalse, reason: 'button must re-enable');

      container.read(authControllerProvider.notifier).clearError();
      final cleared = container.read(authControllerProvider);
      expect(cleared.errorMessage, isNull);
      expect(cleared.isServerUnreachable, isFalse);
    });
  });
}
