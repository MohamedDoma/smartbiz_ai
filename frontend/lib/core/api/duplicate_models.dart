// SmartBiz AI — Duplicate detection API models.

class DuplicateRule {
  final String id;
  final String? ruleKey;
  final String name;
  final String entityType;
  final List<String> matchFields;
  final String matchStrategy;
  final String action;
  final bool isActive;
  final int sortOrder;

  const DuplicateRule({
    required this.id,
    this.ruleKey,
    required this.name,
    required this.entityType,
    required this.matchFields,
    this.matchStrategy = 'normalized_exact',
    this.action = 'warn',
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory DuplicateRule.fromJson(Map<String, dynamic> j) => DuplicateRule(
        id: j['id'] as String,
        ruleKey: j['rule_key'] as String?,
        name: j['name'] as String,
        entityType: j['entity_type'] as String,
        matchFields: (j['match_fields'] as List).map((e) => e.toString()).toList(),
        matchStrategy: j['match_strategy'] as String? ?? 'normalized_exact',
        action: j['action'] as String? ?? 'warn',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

class DuplicateRulePayload {
  final String name;
  final String entityType;
  final List<String> matchFields;
  final String? matchStrategy;
  final String? action;

  const DuplicateRulePayload({
    required this.name,
    required this.entityType,
    required this.matchFields,
    this.matchStrategy,
    this.action,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'entity_type': entityType,
        'match_fields': matchFields,
        if (matchStrategy != null) 'match_strategy': matchStrategy,
        if (action != null) 'action': action,
      };
}

class DuplicateMatch {
  final String id;
  final String? duplicateRuleId;
  final Map<String, dynamic>? rule;
  final String entityType;
  final String sourceEntityId;
  final String matchedEntityId;
  final List<String>? matchFields;
  final double? matchScore;
  final String status;
  final String? resolution;
  final String? resolvedAt;

  const DuplicateMatch({
    required this.id,
    this.duplicateRuleId,
    this.rule,
    required this.entityType,
    required this.sourceEntityId,
    required this.matchedEntityId,
    this.matchFields,
    this.matchScore,
    this.status = 'open',
    this.resolution,
    this.resolvedAt,
  });

  factory DuplicateMatch.fromJson(Map<String, dynamic> j) => DuplicateMatch(
        id: j['id'] as String,
        duplicateRuleId: j['duplicate_rule_id'] as String?,
        rule: j['rule'] as Map<String, dynamic>?,
        entityType: j['entity_type'] as String,
        sourceEntityId: j['source_entity_id'] as String,
        matchedEntityId: j['matched_entity_id'] as String,
        matchFields: (j['match_fields'] as List?)?.map((e) => e.toString()).toList(),
        matchScore: (j['match_score'] as num?)?.toDouble(),
        status: j['status'] as String? ?? 'open',
        resolution: j['resolution'] as String?,
        resolvedAt: j['resolved_at'] as String?,
      );
}

class DuplicateCheckPayload {
  final String entityType;
  final Map<String, dynamic> payload;
  final String? excludeEntityId;

  const DuplicateCheckPayload({required this.entityType, required this.payload, this.excludeEntityId});

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'payload': payload,
        if (excludeEntityId != null) 'exclude_entity_id': excludeEntityId,
      };
}

class DuplicateCheckResult {
  final bool blocked;
  final List<Map<String, dynamic>> matches;

  const DuplicateCheckResult({this.blocked = false, this.matches = const []});

  factory DuplicateCheckResult.fromJson(Map<String, dynamic> j) => DuplicateCheckResult(
        blocked: j['blocked'] as bool? ?? false,
        matches: (j['matches'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      );
}

const kMatchStrategies = ['exact', 'normalized_exact'];
const kDupActions = ['warn', 'block'];
const kMatchStatuses = ['open', 'ignored', 'resolved'];
const kResolutions = ['keep_separate', 'duplicate_confirmed', 'merged_later'];
