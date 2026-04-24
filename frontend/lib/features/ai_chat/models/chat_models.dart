// SmartBiz AI — AI Chat message models.

/// Type of chat message content.
enum ChatMsgType { text, insight, recommendation, actionDraft, actionResult }

/// Sender of the message.
enum ChatSender { user, ai }

/// Status for action drafts.
enum ActionStatus { pending, confirmed, cancelled }

/// A field in an action draft preview.
class ActionField {
  final String labelKey;
  final String value;
  const ActionField({required this.labelKey, required this.value});
}

/// A single chat message.
class ChatMessage {
  final String id;
  final ChatMsgType type;
  final ChatSender sender;
  final String text;
  final DateTime timestamp;
  final List<String>? quickReplies;

  // For insight messages
  final String? insightTitleKey;

  // For recommendation messages
  final String? recTitleKey;
  final String? recDescKey;
  final String? recImpact; // high, medium, low

  // For action draft / result messages
  final String? actionTitleKey;
  final String? actionTypeKey; // 'invoice', 'contact', 'product'
  final List<ActionField>? actionFields;
  final ActionStatus? actionStatus;
  final String? resultSummary;

  const ChatMessage({
    required this.id,
    required this.type,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.quickReplies,
    this.insightTitleKey,
    this.recTitleKey,
    this.recDescKey,
    this.recImpact,
    this.actionTitleKey,
    this.actionTypeKey,
    this.actionFields,
    this.actionStatus,
    this.resultSummary,
  });

  ChatMessage copyWith({ActionStatus? actionStatus, String? resultSummary, String? text}) {
    return ChatMessage(
      id: id,
      type: type,
      sender: sender,
      text: text ?? this.text,
      timestamp: timestamp,
      quickReplies: quickReplies,
      insightTitleKey: insightTitleKey,
      recTitleKey: recTitleKey,
      recDescKey: recDescKey,
      recImpact: recImpact,
      actionTitleKey: actionTitleKey,
      actionTypeKey: actionTypeKey,
      actionFields: actionFields,
      actionStatus: actionStatus ?? this.actionStatus,
      resultSummary: resultSummary ?? this.resultSummary,
    );
  }
}
