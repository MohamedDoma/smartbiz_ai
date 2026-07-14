// SmartBiz AI — AI Chat state management (Step 59.1.2).
// Replaced mock engine with real backend calls via AiService.
// Step 59.3: Added resetForLogout(), loadConversationHistory(),
// user/workspace change detection, and race-condition protection.
import 'package:flutter/material.dart';
import '../../core/api/ai_service.dart';
import 'models/chat_models.dart';

class AiChatState extends ChangeNotifier {
  final AiService _svc;
  AiChatState(this._svc);

  final List<ChatMessage> _messages = [];
  bool _isThinking = false;
  String? _conversationId;
  String? _error;
  int _msgCounter = 0;

  // ── User/Workspace tracking for isolation ───────────────
  String? _boundUserId;
  String? _boundWorkspaceId;

  // ── Race-condition protection ───────────────────────────
  /// Incremented on every reset/user-change. Pending async calls
  /// compare their captured epoch to the current one; stale
  /// responses are discarded.
  int _epoch = 0;

  // ── Getters ─────────────────────────────────────────────
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _isThinking;
  bool get isEmpty => _messages.isEmpty;
  String? get conversationId => _conversationId;
  String? get error => _error;

  // Credits: show token usage from the last response, or 0
  int _totalTokensUsed = 0;
  int get credits => _totalTokensUsed;

  // ── Ensure state is bound to correct user/workspace ─────
  /// Called before any operation. If the user or workspace changed,
  /// clears stale data automatically.
  void ensureUserContext(String userId, String workspaceId) {
    if (_boundUserId == userId && _boundWorkspaceId == workspaceId) return;
    // User or workspace changed — clear old data
    _resetInternal();
    _boundUserId = userId;
    _boundWorkspaceId = workspaceId;
  }

  // ── Load conversation history from backend ──────────────
  /// Loads the most recent conversation for the current user/workspace.
  /// If a conversation exists, loads its messages.
  Future<void> loadConversationHistory() async {
    if (_boundUserId == null || _boundWorkspaceId == null) return;
    if (_messages.isNotEmpty) return; // Already loaded

    final myEpoch = _epoch;
    try {
      final conversations = await _svc.listConversations();
      if (_epoch != myEpoch) return; // User changed during request

      if (conversations.isEmpty) return;

      // Load the most recent conversation
      final latest = conversations.first;
      final detail = await _svc.getConversation(latest.id);
      if (_epoch != myEpoch) return; // User changed during request

      final msgs = detail['messages'] as List?;
      if (msgs == null || msgs.isEmpty) return;

      _conversationId = latest.id;
      _msgCounter = 0;

      for (final m in msgs) {
        final msg = m as Map<String, dynamic>;
        final role = msg['role']?.toString() ?? 'assistant';
        final content = msg['content']?.toString() ?? '';
        if (content.isEmpty) continue;

        _messages.add(ChatMessage(
          id: msg['id']?.toString() ?? '$role-$_msgCounter',
          type: ChatMsgType.text,
          sender: role == 'user' ? ChatSender.user : ChatSender.ai,
          text: content,
          timestamp: DateTime.tryParse(msg['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
        _msgCounter++;
      }
      notifyListeners();
    } catch (_) {
      // Network error — silently fail, user can still send new messages
    }
  }

  // ── Send message ────────────────────────────────────────
  Future<void> sendMessage(String text, BuildContext context) async {
    if (text.trim().isEmpty || _isThinking) return;
    _error = null;

    final myEpoch = _epoch;

    // Add user message immediately
    _messages.add(ChatMessage(
      id: 'user-${_msgCounter++}',
      type: ChatMsgType.text,
      sender: ChatSender.user,
      text: text.trim(),
      timestamp: DateTime.now(),
    ));
    _isThinking = true;
    notifyListeners();

    try {
      final resp = await _svc.sendChatMessage(
        text.trim(),
        conversationId: _conversationId,
      );

      // Stale response — user logged out or switched during request
      if (_epoch != myEpoch) return;

      _isThinking = false;

      if (resp.success && resp.message != null) {
        _conversationId = resp.conversationId;
        _totalTokensUsed += resp.message!.tokens;

        _messages.add(ChatMessage(
          id: resp.message!.id.isNotEmpty ? resp.message!.id : 'ai-${_msgCounter++}',
          type: ChatMsgType.text,
          sender: ChatSender.ai,
          text: resp.message!.content.isNotEmpty
              ? resp.message!.content
              : 'No response received.',
          timestamp: resp.message!.createdAt != null
              ? DateTime.tryParse(resp.message!.createdAt!) ?? DateTime.now()
              : DateTime.now(),
        ));
      } else {
        // Backend returned success=false or error
        final errMsg = resp.error ?? resp.code ?? 'Unknown error from AI';
        _error = errMsg;
        _messages.add(ChatMessage(
          id: 'err-${_msgCounter++}',
          type: ChatMsgType.text,
          sender: ChatSender.ai,
          text: '⚠️ $errMsg',
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // Stale response — discard
      if (_epoch != myEpoch) return;

      _isThinking = false;
      final errStr = _friendlyError(e.toString());
      _error = errStr;
      _messages.add(ChatMessage(
        id: 'err-${_msgCounter++}',
        type: ChatMsgType.text,
        sender: ChatSender.ai,
        text: '⚠️ $errStr',
        timestamp: DateTime.now(),
      ));
    }

    notifyListeners();
  }

  void sendQuickReply(String text, BuildContext context) => sendMessage(text, context);

  // ── Confirm / Cancel action (kept for future tools) ─────
  void confirmAction(String messageId, BuildContext context) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(actionStatus: ActionStatus.confirmed);
    notifyListeners();
  }

  void cancelAction(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(actionStatus: ActionStatus.cancelled);
    notifyListeners();
  }

  // ── Clear chat (user action — new conversation) ─────────
  void clearChat() {
    _messages.clear();
    _conversationId = null;
    _error = null;
    _totalTokensUsed = 0;
    notifyListeners();
  }

  // ── Full reset for logout / account switch ──────────────
  /// Centralized reset — clears ALL chat state including user binding.
  /// Called from logout flow. Invalidates pending async requests.
  void resetForLogout() {
    _resetInternal();
    _boundUserId = null;
    _boundWorkspaceId = null;
    notifyListeners();
  }

  /// Internal reset — clears messages, conversation, counters, epoch.
  void _resetInternal() {
    _messages.clear();
    _conversationId = null;
    _error = null;
    _isThinking = false;
    _totalTokensUsed = 0;
    _msgCounter = 0;
    _epoch++; // Invalidate all pending async requests
  }

  // ── Error helpers ───────────────────────────────────────
  String _friendlyError(String raw) {
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      return 'Cannot reach server. Check your connection.';
    }
    if (raw.contains('401') || raw.contains('Unauthenticated')) {
      return 'Session expired. Please log in again.';
    }
    if (raw.contains('503') || raw.contains('ai_disabled')) {
      return 'AI is currently disabled on this server.';
    }
    if (raw.contains('429')) {
      return 'Too many requests. Please wait a moment.';
    }
    if (raw.contains('500')) {
      return 'Server error. Please try again.';
    }
    // Strip long Dio/exception wrappers, show just the message
    final shortMsg = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    return shortMsg;
  }
}
