// Step 59.1 — AI Models for frontend.

int _toInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _toDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

class AiChatResponse {
  final bool success;
  final String? conversationId;
  final AiMessageData? message;
  final String? error;
  final String? code;

  AiChatResponse({
    required this.success,
    this.conversationId,
    this.message,
    this.error,
    this.code,
  });

  factory AiChatResponse.fromJson(Map<String, dynamic> j) => AiChatResponse(
    success: j['success'] ?? false,
    conversationId: j['conversation_id'],
    message: j['message'] != null ? AiMessageData.fromJson(j['message']) : null,
    error: j['error'],
    code: j['code'],
  );
}

class AiMessageData {
  final String id;
  final String role;
  final String content;
  final String? model;
  final int tokens;
  final String? createdAt;

  AiMessageData({
    required this.id,
    required this.role,
    required this.content,
    this.model,
    this.tokens = 0,
    this.createdAt,
  });

  factory AiMessageData.fromJson(Map<String, dynamic> j) => AiMessageData(
    id: (j['id'] ?? '').toString(),
    role: (j['role'] ?? 'assistant').toString(),
    content: (j['content'] ?? '').toString(),
    model: j['model']?.toString(),
    tokens: _toInt(j['total_tokens'] ?? j['tokens']),
    createdAt: j['created_at']?.toString(),
  );
}

class AiConversationSummary {
  final String id;
  final String? title;
  final String type;
  final String status;
  final int messageCount;
  final String? lastMessageAt;
  final String? createdAt;

  AiConversationSummary({
    required this.id,
    this.title,
    this.type = 'chat',
    this.status = 'active',
    this.messageCount = 0,
    this.lastMessageAt,
    this.createdAt,
  });

  factory AiConversationSummary.fromJson(Map<String, dynamic> j) => AiConversationSummary(
    id: j['id'] ?? '',
    title: j['title'],
    type: j['type'] ?? 'chat',
    status: j['status'] ?? 'active',
    messageCount: _toInt(j['message_count']),
    lastMessageAt: j['last_message_at']?.toString(),
    createdAt: j['created_at']?.toString(),
  );
}

class AiTestResult {
  final bool success;
  final String? text;
  final String? model;
  final int durationMs;
  final String? error;

  AiTestResult({
    required this.success,
    this.text,
    this.model,
    this.durationMs = 0,
    this.error,
  });

  factory AiTestResult.fromJson(Map<String, dynamic> j) => AiTestResult(
    success: j['success'] ?? false,
    text: j['text'],
    model: j['model'],
    durationMs: _toInt(j['duration_ms']),
    error: j['error'],
  );
}

// ── Platform AI Usage Models ─────────────────────────────────

class AiUsageSummary {
  final String period;
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalTokens;
  final double estimatedTotalCost;
  final List<AiUsageByDay> byDay;
  final List<AiUsageByModel> byModel;
  final List<AiUsageByOperation> byOperation;
  final List<AiRecentError> recentErrors;
  final AiUsageBudget budget;

  AiUsageSummary({
    required this.period,
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalTokens,
    required this.estimatedTotalCost,
    required this.byDay,
    required this.byModel,
    required this.byOperation,
    required this.recentErrors,
    required this.budget,
  });

  factory AiUsageSummary.fromJson(Map<String, dynamic> j) => AiUsageSummary(
    period: j['period'] ?? '30d',
    totalRequests: _toInt(j['total_requests']),
    successfulRequests: _toInt(j['successful_requests']),
    failedRequests: _toInt(j['failed_requests']),
    totalInputTokens: _toInt(j['total_input_tokens']),
    totalOutputTokens: _toInt(j['total_output_tokens']),
    totalTokens: _toInt(j['total_tokens']),
    estimatedTotalCost: _toDouble(j['estimated_total_cost']),
    byDay: (j['by_day'] as List? ?? []).map((e) => AiUsageByDay.fromJson(e)).toList(),
    byModel: (j['by_model'] as List? ?? []).map((e) => AiUsageByModel.fromJson(e)).toList(),
    byOperation: (j['by_operation'] as List? ?? []).map((e) => AiUsageByOperation.fromJson(e)).toList(),
    recentErrors: (j['recent_errors'] as List? ?? []).map((e) => AiRecentError.fromJson(e)).toList(),
    budget: AiUsageBudget.fromJson(j['budget'] ?? {}),
  );
}

class AiUsageByDay {
  final String date;
  final int requests;
  final int tokens;
  final double cost;

  AiUsageByDay({required this.date, required this.requests, required this.tokens, required this.cost});

  factory AiUsageByDay.fromJson(Map<String, dynamic> j) => AiUsageByDay(
    date: j['date'] ?? '',
    requests: _toInt(j['requests']),
    tokens: _toInt(j['tokens']),
    cost: _toDouble(j['cost']),
  );
}

class AiUsageByModel {
  final String model;
  final int requests;
  final int tokens;
  final double cost;

  AiUsageByModel({required this.model, required this.requests, required this.tokens, required this.cost});

  factory AiUsageByModel.fromJson(Map<String, dynamic> j) => AiUsageByModel(
    model: j['model'] ?? '',
    requests: _toInt(j['requests']),
    tokens: _toInt(j['tokens']),
    cost: _toDouble(j['cost']),
  );
}

class AiUsageByOperation {
  final String operation;
  final int requests;
  final int tokens;
  final double cost;

  AiUsageByOperation({required this.operation, required this.requests, required this.tokens, required this.cost});

  factory AiUsageByOperation.fromJson(Map<String, dynamic> j) => AiUsageByOperation(
    operation: j['operation'] ?? '',
    requests: _toInt(j['requests']),
    tokens: _toInt(j['tokens']),
    cost: _toDouble(j['cost']),
  );
}

class AiRecentError {
  final String id;
  final String? model;
  final String? operation;
  final String? errorCode;
  final String? errorMessage;
  final String? createdAt;

  AiRecentError({
    required this.id,
    this.model,
    this.operation,
    this.errorCode,
    this.errorMessage,
    this.createdAt,
  });

  factory AiRecentError.fromJson(Map<String, dynamic> j) => AiRecentError(
    id: j['id'] ?? '',
    model: j['model'],
    operation: j['operation'],
    errorCode: j['error_code'],
    errorMessage: j['error_message'],
    createdAt: j['created_at'],
  );
}

class AiUsageBudget {
  final double monthlyUsd;
  final int dailyLimit;
  final int monthlyLimit;

  AiUsageBudget({this.monthlyUsd = 30, this.dailyLimit = 200, this.monthlyLimit = 3000});

  factory AiUsageBudget.fromJson(Map<String, dynamic> j) => AiUsageBudget(
    monthlyUsd: _toDouble(j['monthly_usd'], fallback: 30.0),
    dailyLimit: _toInt(j['daily_limit'], 200),
    monthlyLimit: _toInt(j['monthly_limit'], 3000),
  );
}

class AiWorkspaceUsageSummary {
  final String? workspaceId;
  final String? workspaceName;
  final int totalRequests;
  final int totalTokens;
  final double estimatedCost;
  final int failedRequests;

  AiWorkspaceUsageSummary({
    this.workspaceId,
    this.workspaceName,
    this.totalRequests = 0,
    this.totalTokens = 0,
    this.estimatedCost = 0,
    this.failedRequests = 0,
  });

  factory AiWorkspaceUsageSummary.fromJson(Map<String, dynamic> j) => AiWorkspaceUsageSummary(
    workspaceId: j['workspace_id'],
    workspaceName: j['workspace_name'],
    totalRequests: _toInt(j['total_requests']),
    totalTokens: _toInt(j['total_tokens']),
    estimatedCost: _toDouble(j['estimated_cost']),
    failedRequests: _toInt(j['failed_requests']),
  );
}
