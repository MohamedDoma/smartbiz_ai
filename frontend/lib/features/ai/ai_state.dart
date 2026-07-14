// SmartBiz AI — AI state management (Step 59.1).
import 'package:flutter/foundation.dart';
import '../../core/api/ai_models.dart';
import '../../core/api/ai_service.dart';

class AiState extends ChangeNotifier {
  final AiService _svc;
  AiState(this._svc);

  // ── Chat ───────────────────────────────────────────────────
  List<AiMessageData> messages = [];
  String? currentConversationId;
  bool sending = false;
  String? chatError;

  Future<void> sendMessage(String text) async {
    sending = true;
    chatError = null;
    messages.add(AiMessageData(id: 'local_${DateTime.now().millisecondsSinceEpoch}', role: 'user', content: text));
    notifyListeners();
    try {
      final resp = await _svc.sendChatMessage(text, conversationId: currentConversationId);
      if (resp.success && resp.message != null) {
        currentConversationId = resp.conversationId;
        messages.add(resp.message!);
      } else {
        chatError = resp.error ?? 'Unknown error';
      }
    } catch (e) {
      chatError = e.toString();
    }
    sending = false;
    notifyListeners();
  }

  void clearChat() {
    messages.clear();
    currentConversationId = null;
    chatError = null;
    notifyListeners();
  }

  // ── Test ───────────────────────────────────────────────────
  AiTestResult? testResult;
  bool testing = false;
  String? testError;

  Future<void> testConnection() async {
    testing = true;
    testError = null;
    notifyListeners();
    try {
      testResult = await _svc.testAi();
    } catch (e) {
      testError = e.toString();
    }
    testing = false;
    notifyListeners();
  }

  // ── Platform AI Usage (Super Admin) ───────────────────────
  AiUsageSummary? usageSummary;
  bool usageLoading = false;
  String? usageError;

  Future<void> loadPlatformUsage({String period = '30d'}) async {
    usageLoading = true;
    usageError = null;
    notifyListeners();
    try {
      usageSummary = await _svc.getPlatformAiUsage(period: period);
    } catch (e) {
      usageError = e.toString();
    }
    usageLoading = false;
    notifyListeners();
  }

  // ── Conversations ─────────────────────────────────────────
  List<AiConversationSummary> conversations = [];
  bool convsLoading = false;

  Future<void> loadConversations() async {
    convsLoading = true;
    notifyListeners();
    try {
      conversations = await _svc.listConversations();
    } catch (_) {}
    convsLoading = false;
    notifyListeners();
  }
}
