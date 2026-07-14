// SmartBiz AI — AI API service (Step 59.1).
import '../api/api_client.dart';
import '../api/ai_models.dart';

class AiService {
  final ApiClient _c;
  AiService(this._c);

  // ── Test ───────────────────────────────────────────────────
  Future<AiTestResult> testAi() async {
    final r = await _c.post('/ai/test');
    return AiTestResult.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Chat ───────────────────────────────────────────────────
  Future<AiChatResponse> sendChatMessage(String message, {String? conversationId}) async {
    final r = await _c.post('/ai/chat', data: {
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
    });
    try {
      final d = r.data['data'];
      if (d is Map<String, dynamic>) {
        return AiChatResponse.fromJson(d);
      }
      return AiChatResponse(success: false, error: 'Unexpected response format');
    } catch (e) {
      return AiChatResponse(success: false, error: 'Failed to parse response: $e');
    }
  }

  // ── Conversations ─────────────────────────────────────────
  Future<List<AiConversationSummary>> listConversations() async {
    final r = await _c.get('/ai/conversations');
    return (r.data['data'] as List)
        .map((e) => AiConversationSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getConversation(String id) async {
    final r = await _c.get('/ai/conversations/$id');
    return r.data['data'] as Map<String, dynamic>;
  }

  // ── Platform AI Usage (Super Admin) ───────────────────────
  Future<AiUsageSummary> getPlatformAiUsage({String period = '30d'}) async {
    final r = await _c.get('/platform/ai-usage', queryParameters: {'period': period});
    return AiUsageSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<AiWorkspaceUsageSummary>> getPlatformAiWorkspaces({String period = '30d'}) async {
    final r = await _c.get('/platform/ai-usage/workspaces', queryParameters: {'period': period});
    return (r.data['data'] as List)
        .map((e) => AiWorkspaceUsageSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
