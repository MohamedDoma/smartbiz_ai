// SmartBiz AI — Step 1.8: Duplicate Request Interaction Test.
//
// Verifies that calling startRealProvisioning() twice before the first
// completes results in exactly one set of API calls. Uses a controllable
// fake repository and fake session refresher to count exact call counts.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_client.dart';
import 'package:smartbiz_ai/core/api/provisioning_models.dart';
import 'package:smartbiz_ai/core/api/provisioning_service.dart';
import 'package:smartbiz_ai/features/onboarding/data/provisioning_repository.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';

// ═══════════════════════════════════════════════════════════
//  Controllable Fake Repository
// ═══════════════════════════════════════════════════════════

/// Tracks exact call counts per method. Each call completes after a
/// configurable delay to simulate real network latency.
class FakeProvisioningRepository extends ProvisioningRepository {
  int previewCount = 0;
  int applyCount = 0;
  int applyOperationalCount = 0;
  int finalizeCount = 0;
  int getActiveConfigCount = 0;

  /// Delay per call to simulate network latency.
  final Duration callDelay;

  FakeProvisioningRepository({this.callDelay = const Duration(milliseconds: 50)})
      : super(ProvisioningService(ApiClient()));

  @override
  Future<ProvisioningResult<ProvisioningRun?>> getActiveConfig() async {
    getActiveConfigCount++;
    await Future.delayed(callDelay);
    // Return no active run → start from scratch
    return ProvisioningResult.success(null);
  }

  @override
  Future<ProvisioningResult<PreviewResult>> preview({
    required String blueprintId,
  }) async {
    previewCount++;
    await Future.delayed(callDelay);
    return ProvisioningResult.success(
      const PreviewResult(runId: 'fake-run-1', status: 'preview'),
    );
  }

  @override
  Future<ProvisioningResult<ApplyResult>> apply({
    required String blueprintId,
  }) async {
    applyCount++;
    await Future.delayed(callDelay);
    return ProvisioningResult.success(
      const ApplyResult(runId: 'fake-run-1', status: 'foundation_applied'),
    );
  }

  @override
  Future<ProvisioningResult<ApplyResult>> applyOperational({
    required String runId,
  }) async {
    applyOperationalCount++;
    await Future.delayed(callDelay);
    return ProvisioningResult.success(
      ApplyResult(runId: runId, status: 'applied'),
    );
  }

  @override
  Future<ProvisioningResult<FinalizeResult>> finalize({
    required String runId,
  }) async {
    finalizeCount++;
    await Future.delayed(callDelay);
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
//  Fake AppState for session refresh tracking
// ═══════════════════════════════════════════════════════════

/// Extends real AppState but overrides loadCurrentSession to avoid
/// network calls and count invocations.
class FakeAppState extends AppState {
  int sessionRefreshCount = 0;
  bool fakeOnboardingCompleted;

  FakeAppState({this.fakeOnboardingCompleted = true});

  @override
  Future<bool> loadCurrentSession() async {
    sessionRefreshCount++;
    // Simulate the session refresh setting the onboarding flag.
    if (fakeOnboardingCompleted) {
      completeOnboarding();
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════

void main() {
  group('Duplicate request prevention (Step 1.8)', () {
    late FakeProvisioningRepository fakeRepo;
    late FakeAppState fakeAppState;
    late OnboardingState state;

    setUp(() {
      fakeRepo = FakeProvisioningRepository(
        callDelay: const Duration(milliseconds: 50),
      );
      fakeAppState = FakeAppState(fakeOnboardingCompleted: true);
      state = OnboardingState();
      state.setProvisioningRepository(fakeRepo);
    });

    test('second call returns without starting another chain', () async {
      // Fire two calls without awaiting the first.
      final first = state.startRealProvisioning(fakeAppState);
      final second = state.startRealProvisioning(fakeAppState);

      // Wait for both to complete.
      await Future.wait([first, second]);

      // Exact call counts: each endpoint called exactly once.
      expect(fakeRepo.getActiveConfigCount, 1,
          reason: 'getActiveConfig called once');
      expect(fakeRepo.previewCount, 1,
          reason: 'preview called exactly once');
      expect(fakeRepo.applyCount, 1,
          reason: 'core apply called exactly once');
      expect(fakeRepo.applyOperationalCount, 1,
          reason: 'operational apply called exactly once');
      expect(fakeRepo.finalizeCount, 1,
          reason: 'finalize called exactly once');
      expect(fakeAppState.sessionRefreshCount, 1,
          reason: 'session refresh called exactly once');

      // State verifications.
      expect(state.provisioningDone, isTrue);
      expect(state.isProvisioning, isFalse);
      expect(state.phase, OnboardingPhase.complete);
      expect(state.provisioningError, isNull);
    });

    test('guard resets after first call completes, allowing retry', () async {
      // First call completes normally.
      await state.startRealProvisioning(fakeAppState);

      expect(fakeRepo.previewCount, 1);
      expect(state.provisioningDone, isTrue);

      // Reset to allow retry.
      state.resetOnboarding();

      // Second call is allowed.
      await state.startRealProvisioning(fakeAppState);

      expect(fakeRepo.previewCount, 2,
          reason: 'After reset, second call should proceed');
      expect(fakeRepo.applyCount, 2);
      expect(fakeRepo.applyOperationalCount, 2);
      expect(fakeRepo.finalizeCount, 2);
    });
  });
}
