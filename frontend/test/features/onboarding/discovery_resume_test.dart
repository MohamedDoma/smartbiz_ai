// SmartBiz AI — Discovery Resume After Refresh Tests.
//
// Proves:
//   1. Refresh restores an in-progress session
//   2. Refresh restores a ready session at 86%
//   3. Refresh restores a session that already has a Blueprint
//   4. The real Blueprint ID is preserved
//   5. No welcome greeting is added to a resumed conversation
//   6. No duplicate discovery session is created
//   7. A genuinely fresh account still receives the welcome greeting

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_client.dart';
import 'package:smartbiz_ai/core/api/discovery_models.dart';
import 'package:smartbiz_ai/core/api/discovery_service.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

// ═══════════════════════════════════════════════════════════
//  Fake DiscoveryService for deterministic resume tests
// ═══════════════════════════════════════════════════════════

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();
}

class _FakeDiscoveryService extends DiscoveryService {
  final List<DiscoverySession> sessions;
  final Map<String, DiscoverySession> fullSessions;
  int listCallCount = 0;
  int getCallCount = 0;

  _FakeDiscoveryService({
    this.sessions = const [],
    this.fullSessions = const {},
  }) : super(_FakeApiClient());

  @override
  Future<List<DiscoverySession>> listSessions() async {
    listCallCount++;
    return sessions;
  }

  @override
  Future<DiscoverySession> getSession({required String sessionId}) async {
    getCallCount++;
    return fullSessions[sessionId]!;
  }

  @override
  Future<DiscoverySession> startSession({required String businessDescription}) =>
      throw UnimplementedError('Should not be called during resume');

  @override
  Future<DiscoverySession> submitAnswer({
    required String sessionId,
    required String messageId,
    required List<Map<String, String>> answers,
  }) =>
      throw UnimplementedError();

  @override
  Future<DiscoverySession> classify({required String sessionId}) =>
      throw UnimplementedError();

  @override
  Future<DiscoveryBlueprintDto> generateBlueprint({required String sessionId}) =>
      throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════════
//  Fixtures
// ═══════════════════════════════════════════════════════════

const _sessionId = 'a246cf92-32d9-4976-8e92-d6bb9302ea0e';
const _blueprintId = 'a246cfd0-032a-4688-b066-e0d5aec82b92';

DiscoverySession _makeSessionSummary(String status) => DiscoverySession(
      id: _sessionId,
      workspaceId: 'ws-1',
      status: status,
    );

DiscoverySession _makeFullSession({
  required String status,
  double completeness = 86,
  bool readyForBlueprint = true,
  DiscoveryBlueprintDto? blueprint,
}) =>
    DiscoverySession(
      id: _sessionId,
      workspaceId: 'ws-1',
      status: status,
      completeness: completeness,
      readyForBlueprint: readyForBlueprint,
      messages: const [
        DiscoveryMessageDto(
          id: 'msg-1',
          sessionId: _sessionId,
          role: 'user',
          content: 'شركة لبيع السيارات',
          messageType: 'description',
        ),
        DiscoveryMessageDto(
          id: 'msg-2',
          sessionId: _sessionId,
          role: 'ai',
          content: 'Ready for blueprint',
          messageType: 'ready',
        ),
      ],
      blueprint: blueprint,
    );

final _blueprintDto = DiscoveryBlueprintDto(
  id: _blueprintId,
  sessionId: _sessionId,
  businessType: 'retail',
  blueprint: const {'modules': [], 'roles': []},
  version: 1,
  generatorMethod: 'canonical_v1',
);

void main() {
  group('Discovery resume after refresh', () {
    test('1. restores an in-progress session (questioning)', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('questioning')],
        fullSessions: {
          _sessionId: _makeFullSession(
            status: 'questioning',
            completeness: 40,
            readyForBlueprint: false,
          ),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.discoverySession, isNotNull);
      expect(state.discoverySession!.id, _sessionId);
      expect(state.completeness, 40);
      expect(state.messages, hasLength(2));
      expect(state.resumeAttempted, true);
    });

    test('2. restores a ready session at 86% (completed status)', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('completed')],
        fullSessions: {
          _sessionId: _makeFullSession(
            status: 'completed',
            completeness: 86,
            readyForBlueprint: true,
          ),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.discoverySession, isNotNull);
      expect(state.completeness, 86);
      expect(state.readyForBlueprint, true);
      expect(state.phase, OnboardingPhase.discovery);
    });

    test('3. restores a session that already has a Blueprint', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('completed')],
        fullSessions: {
          _sessionId: _makeFullSession(
            status: 'completed',
            blueprint: _blueprintDto,
          ),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.realBlueprint, isNotNull);
      expect(state.realBlueprint!.id, _blueprintId);
    });

    test('4. real Blueprint ID is preserved', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('completed')],
        fullSessions: {
          _sessionId: _makeFullSession(
            status: 'completed',
            blueprint: _blueprintDto,
          ),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.realBlueprint!.id, _blueprintId);
      expect(state.discoverySession!.id, _sessionId);
    });

    test('5. no welcome greeting added to resumed conversation', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('completed')],
        fullSessions: {
          _sessionId: _makeFullSession(status: 'completed'),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      final appState = AppState();
      state.ensureWelcomeGreeting(appState);

      // Should have only the 2 backend messages, no greeting
      expect(state.messages, hasLength(2));
      expect(
        state.messages.any((m) => m.messageType == 'greeting'),
        false,
        reason: 'Greeting must not be added to a resumed conversation',
      );
    });

    test('6. no duplicate session created during resume', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('questioning')],
        fullSessions: {
          _sessionId: _makeFullSession(
            status: 'questioning',
            completeness: 40,
            readyForBlueprint: false,
          ),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(fake.listCallCount, 1);
      expect(fake.getCallCount, 1);
      // No startSession call — the fake throws if it's called
    });

    test('7. genuinely fresh account receives welcome greeting', () async {
      final fake = _FakeDiscoveryService(
        sessions: [], // No sessions on backend
        fullSessions: {},
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.resumeAttempted, true);
      expect(state.messages, isEmpty);

      final appState = AppState();
      state.ensureWelcomeGreeting(appState);

      expect(state.messages, hasLength(1));
      expect(state.messages.first.messageType, 'greeting');
    });

    test('greeting blocked until resumeAttempted is true', () {
      final state = OnboardingState();
      // Inject a service but don't call resumeDiscovery
      state.setDiscoveryService(_FakeDiscoveryService());

      final appState = AppState();
      state.ensureWelcomeGreeting(appState);

      // Should NOT add greeting yet — resume hasn't been attempted
      expect(state.messages, isEmpty);
    });

    test('no service → resumeAttempted set immediately', () async {
      final state = OnboardingState();
      // No service injected
      await state.resumeDiscovery();

      expect(state.resumeAttempted, true);
    });

    test('classified status is resumable', () async {
      final fake = _FakeDiscoveryService(
        sessions: [_makeSessionSummary('classified')],
        fullSessions: {
          _sessionId: _makeFullSession(status: 'classified'),
        },
      );

      final state = OnboardingState();
      state.setDiscoveryService(fake);
      await state.resumeDiscovery();

      expect(state.discoverySession, isNotNull);
      expect(state.discoverySession!.id, _sessionId);
    });
  });
}
