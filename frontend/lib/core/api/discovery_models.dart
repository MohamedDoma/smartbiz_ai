// SmartBiz AI — Discovery API response models.
//
// Maps to the backend DiscoverySessionResource, DiscoveryMessageResource,
// and DiscoveryBlueprintResource JSON shapes.

/// A discovery session returned by the backend.
class DiscoverySession {
  final String id;
  final String workspaceId;
  final String status;
  final String? businessDescription;
  final String? businessType;
  final int? classificationConfidence;
  final double? completeness;
  final bool readyForBlueprint;
  final List<String> criticalMissing;
  final bool hasBlockingContradictions;
  final List<DiscoveryMessageDto> messages;
  final DiscoveryBlueprintDto? blueprint;
  final String? createdAt;

  const DiscoverySession({
    required this.id,
    required this.workspaceId,
    required this.status,
    this.businessDescription,
    this.businessType,
    this.classificationConfidence,
    this.completeness,
    this.readyForBlueprint = false,
    this.criticalMissing = const [],
    this.hasBlockingContradictions = false,
    this.messages = const [],
    this.blueprint,
    this.createdAt,
  });

  factory DiscoverySession.fromJson(Map<String, dynamic> json) {
    return DiscoverySession(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String? ?? '',
      status: json['status'] as String? ?? 'intake',
      businessDescription: json['business_description'] as String?,
      businessType: json['business_type'] as String?,
      classificationConfidence: json['classification_confidence'] as int?,
      completeness: (json['completeness'] as num?)?.toDouble(),
      readyForBlueprint: json['ready_for_blueprint'] as bool? ?? false,
      criticalMissing: (json['critical_missing'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      hasBlockingContradictions:
          json['has_blocking_contradictions'] as bool? ?? false,
      messages: (json['messages'] as List<dynamic>?)
              ?.map(
                  (m) => DiscoveryMessageDto.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      blueprint: json['blueprint'] != null &&
              json['blueprint'] is Map<String, dynamic> &&
              (json['blueprint'] as Map<String, dynamic>)['id'] != null
          ? DiscoveryBlueprintDto.fromJson(
              json['blueprint'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as String?,
    );
  }

  /// Returns the last AI message that is a follow_up_question (for answer submission).
  DiscoveryMessageDto? get lastFollowUpQuestion {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'ai' &&
          messages[i].messageType == 'follow_up_question') {
        return messages[i];
      }
    }
    return null;
  }
}

/// A single message in the discovery conversation.
class DiscoveryMessageDto {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String messageType;
  final Map<String, dynamic>? metadata;
  final String? createdAt;

  const DiscoveryMessageDto({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.messageType,
    this.metadata,
    this.createdAt,
  });

  factory DiscoveryMessageDto.fromJson(Map<String, dynamic> json) {
    return DiscoveryMessageDto(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      role: json['role'] as String,
      content: json['content'] as String,
      messageType: json['message_type'] as String? ?? 'unknown',
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: json['created_at'] as String?,
    );
  }

  /// Suggestion chips extracted from metadata (if any).
  List<String>? get suggestionChips {
    final questions = metadata?['questions'] as List<dynamic>?;
    if (questions == null || questions.isEmpty) return null;
    // Check if the question metadata has options
    final first = questions.first as Map<String, dynamic>?;
    final options = first?['options'] as List<dynamic>?;
    return options?.map((o) => o.toString()).toList();
  }
}

/// A generated ERP blueprint from the backend.
class DiscoveryBlueprintDto {
  final String id;
  final String sessionId;
  final String? businessType;
  final Map<String, dynamic> blueprint;
  final int version;
  final String? generatorMethod;
  final String? generatorVersion;
  final String? createdAt;

  const DiscoveryBlueprintDto({
    required this.id,
    required this.sessionId,
    this.businessType,
    required this.blueprint,
    this.version = 1,
    this.generatorMethod,
    this.generatorVersion,
    this.createdAt,
  });

  factory DiscoveryBlueprintDto.fromJson(Map<String, dynamic> json) {
    return DiscoveryBlueprintDto(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      businessType: json['business_type'] as String?,
      blueprint: json['blueprint'] is Map
          ? Map<String, dynamic>.from(json['blueprint'] as Map)
          : {},
      version: json['version'] as int? ?? 1,
      generatorMethod: json['generator_method'] as String?,
      generatorVersion: json['generator_version'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
