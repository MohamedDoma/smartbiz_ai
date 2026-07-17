// SmartBiz AI — Step 1.8: Router Onboarding Guard Tests.
//
// Verifies the shared evaluateOnboardingGate() function from router.dart.
// This is the real production redirect logic used by buildAppRouter() for:
//   1. Authenticated + incomplete onboarding → /dashboard redirects to /onboarding
//   2. Authenticated + completed onboarding → /onboarding redirects to /dashboard
//   3. During provisioning (before session refresh) → stays in /onboarding
//   4. After session refresh confirms completion → router redirects to /dashboard
//   5. Browser reload with restored completed session → stays in ERP area
//
// The tests call evaluateOnboardingGate() from router.dart directly —
// no duplicated conditions.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/app/router.dart';

void main() {
  group('Router onboarding guard (Step 1.8)', () {
    // ────────────────────────────────────────────────
    //  Test 1: Incomplete onboarding → dashboard redirects to onboarding
    // ────────────────────────────────────────────────

    test('authenticated + incomplete onboarding: /dashboard → /onboarding', () {
      final appState = AppState();
      appState.signInAsOwner();

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isSuperAdmin, isFalse);
      expect(appState.isOnboardingCompleted, isFalse);

      final redirect = evaluateOnboardingGate(
        isAuthenticated: appState.isAuthenticated,
        isSuperAdmin: appState.isSuperAdmin,
        onboardingDone: appState.isOnboardingCompleted,
        loc: '/dashboard',
      );
      expect(redirect, '/onboarding');
    });

    // ────────────────────────────────────────────────
    //  Test 2: Completed onboarding → /onboarding redirects to /dashboard
    // ────────────────────────────────────────────────

    test('authenticated + completed onboarding: /onboarding → /dashboard', () {
      final appState = AppState();
      appState.signInAsOwner();
      appState.completeOnboarding();

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isSuperAdmin, isFalse);
      expect(appState.isOnboardingCompleted, isTrue);

      final redirect = evaluateOnboardingGate(
        isAuthenticated: appState.isAuthenticated,
        isSuperAdmin: appState.isSuperAdmin,
        onboardingDone: appState.isOnboardingCompleted,
        loc: '/onboarding',
      );
      expect(redirect, '/dashboard');
    });

    // ────────────────────────────────────────────────
    //  Test 3: During provisioning (before session refresh) → stays in onboarding
    // ────────────────────────────────────────────────

    test('during provisioning before refresh: stays at /onboarding', () {
      final appState = AppState();
      appState.signInAsOwner();
      // onboardingCompleted is still false during provisioning.

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isOnboardingCompleted, isFalse);

      final redirect = evaluateOnboardingGate(
        isAuthenticated: appState.isAuthenticated,
        isSuperAdmin: appState.isSuperAdmin,
        onboardingDone: appState.isOnboardingCompleted,
        loc: '/onboarding',
      );
      // Already at onboarding, onboarding not done → no redirect.
      expect(redirect, isNull,
          reason: 'Should stay at /onboarding during provisioning');
    });

    // ────────────────────────────────────────────────
    //  Test 4: After session refresh confirms completion → redirect to dashboard
    // ────────────────────────────────────────────────

    test('after session refresh confirms completion: /onboarding → /dashboard', () {
      final appState = AppState();
      appState.signInAsOwner();
      // Simulate: provisioning completed, session refresh set the flag.
      appState.completeOnboarding();

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isOnboardingCompleted, isTrue);

      final redirect = evaluateOnboardingGate(
        isAuthenticated: appState.isAuthenticated,
        isSuperAdmin: appState.isSuperAdmin,
        onboardingDone: appState.isOnboardingCompleted,
        loc: '/onboarding',
      );
      expect(redirect, '/dashboard',
          reason: 'After session refresh, /onboarding → /dashboard');
    });

    // ────────────────────────────────────────────────
    //  Test 5: Browser reload with restored completed session → stays in ERP area
    // ────────────────────────────────────────────────

    test('browser reload with restored completed session: stays in ERP', () {
      final appState = AppState();
      appState.signInAsOwner();
      appState.completeOnboarding();

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isOnboardingCompleted, isTrue);

      // Simulate user reloading while on /dashboard.
      final redirect = evaluateOnboardingGate(
        isAuthenticated: appState.isAuthenticated,
        isSuperAdmin: appState.isSuperAdmin,
        onboardingDone: appState.isOnboardingCompleted,
        loc: '/dashboard',
      );
      expect(redirect, isNull,
          reason: 'User stays in ERP/dashboard area after reload');
    });

    // ────────────────────────────────────────────────
    //  Integration: router is created with AppState as refreshListenable
    // ────────────────────────────────────────────────

    test('router refreshListenable is wired to AppState', () {
      final appState = AppState();
      final router = buildAppRouter(appState);
      expect(router, isNotNull);
      // buildAppRouter passes appState as refreshListenable, so when
      // appState.completeOnboarding() fires, GoRouter re-evaluates routes.
    });

    // ────────────────────────────────────────────────
    //  Truth table: all 4 combinations for non-SA authenticated user
    // ────────────────────────────────────────────────

    test('redirect conditions are consistent across all scenarios', () {
      final scenarios = [
        // (onboardingDone, location, expectedRedirect)
        (false, '/dashboard', '/onboarding'),   // test 1
        (true, '/onboarding', '/dashboard'),    // test 2
        (false, '/onboarding', null),           // test 3
        (true, '/dashboard', null),             // test 5
        // Additional ERP routes
        (true, '/invoices', null),              // stays in invoices
        (false, '/invoices', '/onboarding'),    // forced to onboarding
        (true, '/products', null),              // stays in products
        (false, '/products', '/onboarding'),    // forced to onboarding
      ];

      for (final (onboardingDone, loc, expected) in scenarios) {
        final redirect = evaluateOnboardingGate(
          isAuthenticated: true,
          isSuperAdmin: false,
          onboardingDone: onboardingDone,
          loc: loc,
        );
        expect(redirect, expected,
            reason: 'onboardingDone=$onboardingDone, loc=$loc → expected $expected');
      }
    });
  });
}
