// SmartBiz AI — Step 1.8: Session Refresh Completion Tests.
//
// Verifies the two real state-flow paths after finalize:
//   1. Completed session (onboardingCompleted == true)  → provisioning done, phase complete
//   2. Incomplete session (onboardingCompleted == false) → error, phase stays blueprint

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_client.dart';
import 'package:smartbiz_ai/core/api/provisioning_models.dart';
import 'package:smartbiz_ai/core/api/provisioning_service.dart';
import 'package:smartbiz_ai/features/onboarding/data/provisioning_repository.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';

// ═══════════════════════════════════════════════════════════
//  Fake Repository — all steps succeed
// ═══════════════════════════════════════════════════════════

class _SucceedingRepo extends ProvisioningRepository {
  _SucceedingRepo() : super(ProvisioningService(ApiClient()));

  @override
  Future<ProvisioningResult<ProvisioningRun?>> getActiveConfig() async {
    return ProvisioningResult.success(null);
  }

  @override
  Future<ProvisioningResult<PreviewResult>> preview({
    required String blueprintId,
  }) async {
    return ProvisioningResult.success(
      const PreviewResult(runId: 'run-1', status: 'preview'),
    );
  }

  @override
  Future<ProvisioningResult<ApplyResult>> apply({
    required String blueprintId,
  }) async {
    return ProvisioningResult.success(
      const ApplyResult(runId: 'run-1', status: 'foundation_applied'),
    );
  }

  @override
  Future<ProvisioningResult<ApplyResult>> applyOperational({
    required String runId,
  }) async {
    return ProvisioningResult.success(
      ApplyResult(runId: runId, status: 'applied'),
    );
  }

  @override
  Future<ProvisioningResult<FinalizeResult>> finalize({
    required String runId,
  }) async {
    return ProvisioningResult.success(
      FinalizeResult(
        runId: runId,
        status: 'onboarding_complete',
        onboardingCompleted: true,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Fake AppState — controllable onboarding completion flag
// ═══════════════════════════════════════════════════════════

class _FakeAppState extends AppState {
  int sessionRefreshCount = 0;
  final bool _simulatedOnboardingCompleted;

  _FakeAppState({required bool simulatedOnboardingCompleted})
      : _simulatedOnboardingCompleted = simulatedOnboardingCompleted;

  @override
  Future<bool> loadCurrentSession() async {
    sessionRefreshCount++;
    if (_simulatedOnboardingCompleted) {
      completeOnboarding();
    } else {
      resetOnboarding();
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════

void main() {
  group('Session refresh completion (Step 1.8)', () {
    test('completed session → provisioning done, phase complete, no error', () async {
      final fakeAppState = _FakeAppState(simulatedOnboardingCompleted: true);
      final repo = _SucceedingRepo();
      final state = OnboardingState();
      state.setProvisioningRepository(repo);

      await state.startRealProvisioning(fakeAppState);

      // Session refresh ran exactly once.
      expect(fakeAppState.sessionRefreshCount, 1,
          reason: 'Session refresh should run exactly once after finalize');

      // State assertions for the completed path.
      expect(state.provisioningDone, isTrue,
          reason: 'provisioningDone must be true after successful session sync');
      expect(state.phase, OnboardingPhase.complete,
          reason: 'Phase must transition to complete');
      expect(state.provisioningError, isNull,
          reason: 'No error should exist on success');
      expect(state.isProvisioning, isFalse,
          reason: 'Provisioning should no longer be in progress');
      expect(state.provisioningStep, ProvisioningStep.idle,
          reason: 'Step should return to idle after completion');
    });

    test('incomplete session → error, phase stays blueprint, dashboard blocked', () async {
      final fakeAppState = _FakeAppState(simulatedOnboardingCompleted: false);
      final repo = _SucceedingRepo();
      final state = OnboardingState();
      state.setProvisioningRepository(repo);

      await state.startRealProvisioning(fakeAppState);

      // Session refresh ran exactly once.
      expect(fakeAppState.sessionRefreshCount, 1,
          reason: 'Session refresh should run exactly once');

      // State assertions for the incomplete/failed path.
      expect(state.provisioningDone, isFalse,
          reason: 'provisioningDone must be false when session sync fails');
      expect(state.phase, isNot(OnboardingPhase.complete),
          reason: 'Phase must NOT become complete');
      expect(state.phase, OnboardingPhase.blueprint,
          reason: 'Phase should revert to blueprint for retry');
      expect(state.provisioningError, isNotNull,
          reason: 'A retryable error must be shown');
      expect(state.provisioningError, contains('Session sync failed'),
          reason: 'Error message should indicate session sync failure');
      expect(state.isProvisioning, isFalse,
          reason: 'Provisioning should stop on failure');

      // Dashboard navigation is gated by AppState.isOnboardingCompleted.
      expect(fakeAppState.isOnboardingCompleted, isFalse,
          reason: 'Dashboard navigation must remain blocked');
    });
  });
}
