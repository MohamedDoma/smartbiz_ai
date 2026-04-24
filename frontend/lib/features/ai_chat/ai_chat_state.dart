// SmartBiz AI — AI Chat state management with mock AI response engine.
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import 'models/chat_models.dart';

class AiChatState extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _isThinking = false;
  int _credits = 820;
  int _msgCounter = 0;

  // ── Getters ─────────────────────────────────────────────
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _isThinking;
  int get credits => _credits;
  bool get isEmpty => _messages.isEmpty;

  // ── Send message ────────────────────────────────────────
  void sendMessage(String text, BuildContext context) {
    if (text.trim().isEmpty || _isThinking) return;

    _messages.add(ChatMessage(
      id: 'user-${_msgCounter++}',
      type: ChatMsgType.text,
      sender: ChatSender.user,
      text: text.trim(),
      timestamp: DateTime.now(),
    ));
    _isThinking = true;
    _credits = (_credits - 1).clamp(0, 9999);
    notifyListeners();

    // Generate AI response based on user input
    final lower = text.toLowerCase();
    Future.delayed(const Duration(milliseconds: 900), () {
      _isThinking = false;
      _generateResponse(lower, context);
      notifyListeners();
    });
  }

  void sendQuickReply(String text, BuildContext context) => sendMessage(text, context);

  // ── Confirm / Cancel action ─────────────────────────────
  void confirmAction(String messageId, BuildContext context) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    _messages[idx] = _messages[idx].copyWith(actionStatus: ActionStatus.confirmed);
    _isThinking = true;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 700), () {
      _isThinking = false;
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.actionResult,
        sender: ChatSender.ai,
        text: tr(context, 'chat_action_success'),
        timestamp: DateTime.now(),
        resultSummary: tr(context, 'chat_action_success_detail'),
      ));
      notifyListeners();
    });
  }

  void cancelAction(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(actionStatus: ActionStatus.cancelled);
    notifyListeners();
  }

  // ── Clear chat ──────────────────────────────────────────
  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  // ── Mock response engine ────────────────────────────────
  void _generateResponse(String input, BuildContext context) {
    // Invoice-related
    if (input.contains('invoice') || input.contains('فاتورة')) {
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.actionDraft,
        sender: ChatSender.ai,
        text: tr(context, 'chat_draft_invoice_text'),
        timestamp: DateTime.now(),
        actionTitleKey: 'chat_draft_invoice_title',
        actionTypeKey: 'invoice',
        actionFields: [
          ActionField(labelKey: 'chat_field_customer', value: 'Ahmed Mohamed'),
          ActionField(labelKey: 'chat_field_amount', value: '\$1,250.00'),
          ActionField(labelKey: 'chat_field_items', value: '3 items'),
          ActionField(labelKey: 'chat_field_due', value: 'Net 30'),
        ],
        actionStatus: ActionStatus.pending,
      ));
      return;
    }

    // Contact-related
    if (input.contains('contact') || input.contains('customer') || input.contains('عميل')) {
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.actionDraft,
        sender: ChatSender.ai,
        text: tr(context, 'chat_draft_contact_text'),
        timestamp: DateTime.now(),
        actionTitleKey: 'chat_draft_contact_title',
        actionTypeKey: 'contact',
        actionFields: [
          ActionField(labelKey: 'chat_field_name', value: 'Sara Ali'),
          ActionField(labelKey: 'chat_field_email', value: 'sara@example.com'),
          ActionField(labelKey: 'chat_field_phone', value: '+966 55 123 4567'),
          ActionField(labelKey: 'chat_field_type', value: 'Customer'),
        ],
        actionStatus: ActionStatus.pending,
      ));
      return;
    }

    // Product-related
    if (input.contains('product') || input.contains('منتج')) {
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.actionDraft,
        sender: ChatSender.ai,
        text: tr(context, 'chat_draft_product_text'),
        timestamp: DateTime.now(),
        actionTitleKey: 'chat_draft_product_title',
        actionTypeKey: 'product',
        actionFields: [
          ActionField(labelKey: 'chat_field_product_name', value: 'Premium Coffee Beans'),
          ActionField(labelKey: 'chat_field_sku', value: 'COF-001'),
          ActionField(labelKey: 'chat_field_price', value: '\$24.99'),
          ActionField(labelKey: 'chat_field_stock', value: '150 units'),
        ],
        actionStatus: ActionStatus.pending,
      ));
      return;
    }

    // Revenue / report
    if (input.contains('revenue') || input.contains('report') || input.contains('إيرادات') || input.contains('تقرير')) {
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.insight,
        sender: ChatSender.ai,
        text: tr(context, 'chat_insight_revenue_body'),
        timestamp: DateTime.now(),
        insightTitleKey: 'chat_insight_revenue_title',
      ));
      return;
    }

    // Stock / inventory
    if (input.contains('stock') || input.contains('inventory') || input.contains('مخزون')) {
      _messages.add(ChatMessage(
        id: 'ai-${_msgCounter++}',
        type: ChatMsgType.recommendation,
        sender: ChatSender.ai,
        text: tr(context, 'chat_rec_stock_body'),
        timestamp: DateTime.now(),
        recTitleKey: 'chat_rec_stock_title',
        recDescKey: 'chat_rec_stock_desc',
        recImpact: 'high',
        quickReplies: [
          tr(context, 'chat_qr_view_inventory'),
          tr(context, 'chat_qr_reorder'),
        ],
      ));
      return;
    }

    // Default conversational response
    _messages.add(ChatMessage(
      id: 'ai-${_msgCounter++}',
      type: ChatMsgType.text,
      sender: ChatSender.ai,
      text: tr(context, 'chat_default_response'),
      timestamp: DateTime.now(),
      quickReplies: [
        tr(context, 'ai_suggest_revenue'),
        tr(context, 'ai_suggest_invoice'),
        tr(context, 'ai_suggest_stock'),
      ],
    ));
  }
}
