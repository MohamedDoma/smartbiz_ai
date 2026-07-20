// SmartBiz AI — View Blueprint button behavior tests.
//
// Proves:
//   1. Completed resumed session with Blueprint → direct open, 0 API calls
//   2. Ready unclassified session without Blueprint → classify + generate
//   3. Classified session without Blueprint → skip classify, generate only
//   4. Repeated button clicks cannot create duplicate requests
//   5. Technical messages (classification, blueprint) are hidden
//   6. Genuine AI questions and ready message remain visible

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_client.dart';
import 'package:smartbiz_ai/core/api/discovery_models.dart';
import 'package:smartbiz_ai/core/api/discovery_service.dart';
import 'package:smartbiz_ai/features/onboarding/models/onboarding_models.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

// ═══════════════════════════════════════════════════════════
//  Tracking fake service
// ═══════════════════════════════════════════════════════════

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();
}

class _TrackingDiscoveryService extends DiscoveryService {
  int classifyCount = 0;
  int generateCount = 0;

  final DiscoverySession classifyResult;
  final DiscoveryBlueprintDto generateResult;

  _TrackingDiscoveryService({
    required this.classifyResult,
    required this.generateResult,
  }) : super(_FakeApiClient());

  @override
  Future<DiscoverySession> classify({required String sessionId}) async {
    classifyCount++;
    return classifyResult;
  }

  @override
  Future<DiscoveryBlueprintDto> generateBlueprint({
    required String sessionId,
  }) async {
    generateCount++;
    return generateResult;
  }

  @override
  Future<List<DiscoverySession>> listSessions() async => [];

  @override
  Future<DiscoverySession> getSession({required String sessionId}) =>
      throw UnimplementedError();

  @override
  Future<DiscoverySession> startSession({
    required String businessDescription,
    String locale = 'ar',
  }) =>
      throw UnimplementedError();

  @override
  Future<DiscoverySession> submitAnswer({
    required String sessionId,
    required String messageId,
    required List<Map<String, String>> answers,
    String locale = 'ar',
  }) =>
      throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════════
//  Fixtures
// ═══════════════════════════════════════════════════════════

const _sessionId = 'a246cf92-32d9-4976-8e92-d6bb9302ea0e';
const _blueprintId = 'a246cfd0-032a-4688-b066-e0d5aec82b92';

final _blueprintDto = DiscoveryBlueprintDto(
  id: _blueprintId,
  sessionId: _sessionId,
  businessType: 'retail',
  blueprint: const {'modules': [], 'roles': []},
  version: 1,
  generatorMethod: 'canonical_v1',
);

DiscoverySession _makeSession({
  required String status,
  DiscoveryBlueprintDto? blueprint,
}) =>
    DiscoverySession(
      id: _sessionId,
      workspaceId: 'ws-1',
      status: status,
      readyForBlueprint: true,
      completeness: 86,
      blueprint: blueprint,
    );

void main() {
  group('View Blueprint button', () {
    test('1. completed session with Blueprint → direct open, 0 API calls',
        () async {
      final svc = _TrackingDiscoveryService(
        classifyResult: _makeSession(status: 'classified'),
        generateResult: _blueprintDto,
      );

      final state = OnboardingState();
      state.setDiscoveryService(svc);

      // Simulate resumed session with existing Blueprint
      state.setSessionForTesting(
        _makeSession(status: 'completed', blueprint: _blueprintDto),
      );
      state.setBlueprintForTesting(_blueprintDto);

      await state.classifyAndGenerateBlueprint();

      expect(state.phase, OnboardingPhase.blueprint);
      expect(svc.classifyCount, 0, reason: 'Must not re-classify');
      expect(svc.generateCount, 0, reason: 'Must not re-generate');
      expect(state.realBlueprint!.id, _blueprintId);
    });

    test('2. ready unclassified session → classify + generate', () async {
      final svc = _TrackingDiscoveryService(
        classifyResult: _makeSession(status: 'classified'),
        generateResult: _blueprintDto,
      );

      final state = OnboardingState();
      state.setDiscoveryService(svc);
      state.setSessionForTesting(
        _makeSession(status: 'questioning'), // not classified yet
      );

      await state.classifyAndGenerateBlueprint();

      expect(state.phase, OnboardingPhase.blueprint);
      expect(svc.classifyCount, 1);
      expect(svc.generateCount, 1);
    });

    test('3. classified session without Blueprint → skip classify, generate only',
        () async {
      final svc = _TrackingDiscoveryService(
        classifyResult: _makeSession(status: 'classified'),
        generateResult: _blueprintDto,
      );

      final state = OnboardingState();
      state.setDiscoveryService(svc);
      state.setSessionForTesting(
        _makeSession(status: 'classified'), // already classified
      );

      await state.classifyAndGenerateBlueprint();

      expect(state.phase, OnboardingPhase.blueprint);
      expect(svc.classifyCount, 0, reason: 'Must skip classify');
      expect(svc.generateCount, 1);
    });

    test('4. repeated clicks cannot create duplicate requests', () async {
      final svc = _TrackingDiscoveryService(
        classifyResult: _makeSession(status: 'classified'),
        generateResult: _blueprintDto,
      );

      final state = OnboardingState();
      state.setDiscoveryService(svc);
      state.setSessionForTesting(_makeSession(status: 'questioning'));

      // First call
      await state.classifyAndGenerateBlueprint();
      expect(svc.classifyCount, 1);
      expect(svc.generateCount, 1);

      // Second call — Blueprint now exists → fast path
      await state.classifyAndGenerateBlueprint();
      expect(svc.classifyCount, 1, reason: 'No second classify');
      expect(svc.generateCount, 1, reason: 'No second generate');
    });

    test('5. technical messages (classification, blueprint) are hidden', () {
      final state = OnboardingState();

      // Add mixed messages including technical ones
      state.addMessageForTesting(DiscoveryMessage(
        id: 'msg-1',
        text: 'User description',
        sender: MessageSender.user,
        timestamp: DateTime.now(),
        messageType: 'description',
      ));
      state.addMessageForTesting(DiscoveryMessage(
        id: 'msg-2',
        text: 'AI ready message',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'ready',
      ));
      state.addMessageForTesting(DiscoveryMessage(
        id: 'msg-3',
        text: 'Business classified as: retail',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'classification',
      ));
      state.addMessageForTesting(DiscoveryMessage(
        id: 'msg-4',
        text: 'ERP blueprint has been generated.',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'blueprint',
      ));
      state.addMessageForTesting(DiscoveryMessage(
        id: 'msg-5',
        text: 'A follow-up question',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'follow_up_question',
      ));

      final visible = state.messages;

      expect(visible, hasLength(3)); // user, ready, follow_up
      expect(visible.any((m) => m.messageType == 'classification'), false);
      expect(visible.any((m) => m.messageType == 'blueprint'), false);
      expect(visible.any((m) => m.messageType == 'description'), true);
      expect(visible.any((m) => m.messageType == 'ready'), true);
      expect(visible.any((m) => m.messageType == 'follow_up_question'), true);
    });

    test('6. genuine AI questions and ready message remain visible', () {
      final state = OnboardingState();

      state.addMessageForTesting(DiscoveryMessage(
        id: 'q1',
        text: 'What departments do you have?',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'follow_up_question',
      ));
      state.addMessageForTesting(DiscoveryMessage(
        id: 'r1',
        text: 'Ready to generate blueprint',
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        messageType: 'ready',
      ));

      final visible = state.messages;
      expect(visible, hasLength(2));
      expect(visible[0].messageType, 'follow_up_question');
      expect(visible[1].messageType, 'ready');
    });

    test('completed session without Blueprint → skip classify, generate only',
        () async {
      final svc = _TrackingDiscoveryService(
        classifyResult: _makeSession(status: 'classified'),
        generateResult: _blueprintDto,
      );

      final state = OnboardingState();
      state.setDiscoveryService(svc);
      state.setSessionForTesting(
        _makeSession(status: 'completed'), // completed but no local blueprint
      );

      await state.classifyAndGenerateBlueprint();

      expect(svc.classifyCount, 0, reason: 'completed → skip classify');
      expect(svc.generateCount, 1);
      expect(state.phase, OnboardingPhase.blueprint);
    });
  });
}
