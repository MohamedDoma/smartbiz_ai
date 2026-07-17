// SmartBiz AI — Discovery API service.
//
// Remote data-source for the adaptive discovery endpoints:
//   POST /discovery/sessions         — start session
//   GET  /discovery/sessions/{id}    — show session (resume)
//   GET  /discovery/sessions         — list sessions (find active)
//   POST /discovery/sessions/{id}/answer — submit answers
//   POST /discovery/sessions/{id}/classify — classify business
//   POST /discovery/sessions/{id}/generate-blueprint — generate Blueprint
//
// Follows the same ApiClient pattern as ProvisioningService.

import 'api_client.dart';
import 'discovery_models.dart';

class DiscoveryService {
  final ApiClient _client;

  DiscoveryService(this._client);

  // ═══════════════════════════════════════════════════════════
  //  Start a new discovery session
  // ═══════════════════════════════════════════════════════════

  /// POST /api/discovery/sessions
  ///
  /// Starts a new adaptive discovery session with the initial business
  /// description. If an active session already exists for the workspace,
  /// the backend returns it instead of creating a duplicate.
  ///
  /// The response includes the first AI analysis and possibly an immediate
  /// ready_for_blueprint flag if the description was detailed enough.
  Future<DiscoverySession> startSession({
    required String businessDescription,
    String locale = 'ar',
  }) async {
    final response = await _client.post('/discovery/sessions', data: {
      'business_description': businessDescription,
      'locale': locale,
    });

    final data = response.data as Map<String, dynamic>;
    final sessionJson = data['data'] as Map<String, dynamic>? ?? data;
    return DiscoverySession.fromJson(sessionJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Show session (for resume)
  // ═══════════════════════════════════════════════════════════

  /// GET /api/discovery/sessions/{id}
  ///
  /// Retrieves a session with messages and blueprint (for resume).
  Future<DiscoverySession> getSession({required String sessionId}) async {
    final response = await _client.get('/discovery/sessions/$sessionId');

    final data = response.data as Map<String, dynamic>;
    final sessionJson = data['data'] as Map<String, dynamic>? ?? data;
    return DiscoverySession.fromJson(sessionJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  List sessions (find active for resume)
  // ═══════════════════════════════════════════════════════════

  /// GET /api/discovery/sessions
  ///
  /// Lists all discovery sessions for the workspace. Used to find
  /// an active (intake/questioning) session for resume.
  Future<List<DiscoverySession>> listSessions() async {
    final response = await _client.get('/discovery/sessions');

    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .map((s) => DiscoverySession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  //  Submit answers (adaptive follow-up)
  // ═══════════════════════════════════════════════════════════

  /// POST /api/discovery/sessions/{id}/answer
  ///
  /// Submits the user's answer to a follow-up question. The backend
  /// re-analyzes the full conversation and returns:
  ///   - ready_for_blueprint: true → discovery is complete
  ///   - a new follow_up_question message → another question needed
  ///
  /// [messageId]: the ID of the AI follow_up_question being answered.
  /// [answers]: list of answer objects, each with at least {answer: string}.
  Future<DiscoverySession> submitAnswer({
    required String sessionId,
    required String messageId,
    required List<Map<String, String>> answers,
    String locale = 'ar',
  }) async {
    final response = await _client.post(
      '/discovery/sessions/$sessionId/answer',
      data: {
        'message_id': messageId,
        'answers': answers,
        'locale': locale,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final sessionJson = data['data'] as Map<String, dynamic>? ?? data;
    return DiscoverySession.fromJson(sessionJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Classify business type
  // ═══════════════════════════════════════════════════════════

  /// POST /api/discovery/sessions/{id}/classify
  ///
  /// Classifies the business type using LLM + rule-based fallback.
  /// Transitions the session to blueprint_ready status.
  Future<DiscoverySession> classify({required String sessionId}) async {
    final response =
        await _client.post('/discovery/sessions/$sessionId/classify');

    final data = response.data as Map<String, dynamic>;
    final sessionJson = data['data'] as Map<String, dynamic>? ?? data;
    return DiscoverySession.fromJson(sessionJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Generate Blueprint
  // ═══════════════════════════════════════════════════════════

  /// POST /api/discovery/sessions/{id}/generate-blueprint
  ///
  /// Generates the real ERP blueprint for a classified session.
  /// Returns the persisted DiscoveryBlueprintDto.
  Future<DiscoveryBlueprintDto> generateBlueprint({
    required String sessionId,
  }) async {
    final response = await _client
        .post('/discovery/sessions/$sessionId/generate-blueprint');

    final data = response.data as Map<String, dynamic>;
    final bpJson = data['data'] as Map<String, dynamic>? ?? data;
    return DiscoveryBlueprintDto.fromJson(bpJson);
  }
}
