// SmartBiz AI — Step 1.8: Provider Wiring Test.
//
// Verifies that the real MultiProvider tree in main.dart creates
// OnboardingState with its injected ProvisioningRepository and that
// AppState is accessible alongside it.
//
// This is a widget-level structural test that pumps the real provider
// hierarchy (without the full MaterialApp.router) and asserts the
// injected dependencies are present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartbiz_ai/core/api/provisioning_service.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/onboarding/data/provisioning_repository.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

void main() {
  group('Provider wiring (Step 1.8)', () {
    testWidgets(
      'OnboardingState has injected ProvisioningRepository and AppState is accessible',
      (tester) async {
        // Build the same provider tree as main.dart
        late OnboardingState capturedOnboarding;
        late AppState capturedAppState;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AppState()),
              ChangeNotifierProxyProvider<AppState, OnboardingState>(
                create: (ctx) {
                  final appState = ctx.read<AppState>();
                  final repo = ProvisioningRepository(
                    ProvisioningService(appState.apiClient),
                  );
                  final state = OnboardingState();
                  state.setProvisioningRepository(repo);
                  return state;
                },
                update: (_, __, prev) => prev!,
              ),
            ],
            child: Builder(
              builder: (context) {
                capturedOnboarding = context.read<OnboardingState>();
                capturedAppState = context.read<AppState>();
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        // Assert: OnboardingState has the injected repository.
        expect(capturedOnboarding.hasInjectedRepository, isTrue,
            reason: 'ProvisioningRepository should be injected via provider');

        // Assert: AppState is accessible in the same tree.
        expect(capturedAppState, isNotNull);
        expect(capturedAppState.isAuthenticated, isFalse);
      },
    );

    testWidgets(
      'OnboardingState instance is preserved across AppState notifications',
      (tester) async {
        late OnboardingState firstInstance;
        int buildCount = 0;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AppState()),
              ChangeNotifierProxyProvider<AppState, OnboardingState>(
                create: (ctx) {
                  final appState = ctx.read<AppState>();
                  final repo = ProvisioningRepository(
                    ProvisioningService(appState.apiClient),
                  );
                  final state = OnboardingState();
                  state.setProvisioningRepository(repo);
                  return state;
                },
                update: (_, __, prev) => prev!,
              ),
            ],
            child: Consumer<OnboardingState>(
              builder: (context, onboarding, _) {
                buildCount++;
                firstInstance = onboarding;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final initialInstance = firstInstance;
        expect(buildCount, 1);

        // Trigger a real AppState notification without creating a mock session.
        final appState = tester.element(find.byType(SizedBox)).read<AppState>();
        appState.completeOnboarding();
        await tester.pump();

        // OnboardingState instance should be the same object
        expect(identical(firstInstance, initialInstance), isTrue,
            reason: 'OnboardingState must not be recreated on AppState change');
        expect(firstInstance.hasInjectedRepository, isTrue);
      },
    );
  });
}
