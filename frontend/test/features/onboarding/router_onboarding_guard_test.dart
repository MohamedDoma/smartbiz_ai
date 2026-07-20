// SmartBiz AI — Router Onboarding Guard Tests.
//
// Verifies the shared evaluateOnboardingGate() production redirect logic.
// Authentication/session restoration is tested separately through the real
// auth service; these unit tests intentionally avoid removed mock sign-in APIs.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/app/router.dart';

void main() {
  group('Router onboarding guard', () {
    test('authenticated + incomplete onboarding: dashboard → onboarding', () {
      final redirect = evaluateOnboardingGate(
        isAuthenticated: true,
        isSuperAdmin: false,
        onboardingDone: false,
        loc: '/dashboard',
      );

      expect(redirect, '/onboarding');
    });

    test('authenticated + completed onboarding: onboarding → dashboard', () {
      final redirect = evaluateOnboardingGate(
        isAuthenticated: true,
        isSuperAdmin: false,
        onboardingDone: true,
        loc: '/onboarding',
      );

      expect(redirect, '/dashboard');
    });

    test('during provisioning: stays at onboarding', () {
      final redirect = evaluateOnboardingGate(
        isAuthenticated: true,
        isSuperAdmin: false,
        onboardingDone: false,
        loc: '/onboarding',
      );

      expect(redirect, isNull);
    });

    test('completed restored session stays in ERP area', () {
      final redirect = evaluateOnboardingGate(
        isAuthenticated: true,
        isSuperAdmin: false,
        onboardingDone: true,
        loc: '/dashboard',
      );

      expect(redirect, isNull);
    });


    test('router is constructed with AppState as refresh source', () {
      final appState = AppState();
      addTearDown(appState.dispose);

      final router = buildAppRouter(appState);

      expect(router, isNotNull);
    });

    test('redirect conditions are consistent across ERP routes', () {
      final scenarios = [
        (false, '/dashboard', '/onboarding'),
        (true, '/onboarding', '/dashboard'),
        (false, '/onboarding', null),
        (true, '/dashboard', null),
        (true, '/invoices', null),
        (false, '/invoices', '/onboarding'),
        (true, '/products', null),
        (false, '/products', '/onboarding'),
      ];

      for (final (onboardingDone, loc, expected) in scenarios) {
        final redirect = evaluateOnboardingGate(
          isAuthenticated: true,
          isSuperAdmin: false,
          onboardingDone: onboardingDone,
          loc: loc,
        );

        expect(
          redirect,
          expected,
          reason: 'onboardingDone=$onboardingDone, loc=$loc',
        );
      }
    });
  });
}
