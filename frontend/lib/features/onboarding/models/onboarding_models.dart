// SmartBiz AI — Onboarding / discovery models.

/// A single message in the discovery conversation.
class DiscoveryMessage {
  final String id;
  final String text;
  final MessageSender sender;
  final DateTime timestamp;
  final List<String>? quickReplies;
  final bool isThinking;
  final String? messageType;

  const DiscoveryMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.quickReplies,
    this.isThinking = false,
    this.messageType,
  });
}

enum MessageSender { user, ai }

/// Generated ERP blueprint.
class BlueprintModel {
  final String businessName;
  final String businessType;
  final String businessDescription;
  final List<BlueprintModule> requiredModules;
  final List<BlueprintModule> optionalModules;
  final List<BlueprintRole> suggestedRoles;
  final List<String> suggestedWorkflows;
  final List<String> suggestedDashboards;
  final List<String> suggestedAutomations;
  final List<String> notes;

  const BlueprintModel({
    required this.businessName,
    required this.businessType,
    required this.businessDescription,
    required this.requiredModules,
    required this.optionalModules,
    required this.suggestedRoles,
    required this.suggestedWorkflows,
    required this.suggestedDashboards,
    required this.suggestedAutomations,
    required this.notes,
  });
}

class BlueprintModule {
  final String id;

  /// Human-readable display name (already localized by the bridge).
  final String displayName;

  /// Human-readable description (already localized by the bridge).
  final String displayDescription;

  final String icon;
  final bool included;

  const BlueprintModule({
    required this.id,
    required this.displayName,
    required this.displayDescription,
    required this.icon,
    this.included = true,
  });

  // Legacy alias for backward compatibility with tests
  String get nameKey => displayName;
  String get descriptionKey => displayDescription;
}

class BlueprintRole {
  final String id;

  /// Human-readable display name (already localized by the bridge).
  final String displayName;

  /// Human-readable description (already localized by the bridge).
  final String displayDescription;

  final List<String> accessModules;

  const BlueprintRole({
    required this.id,
    required this.displayName,
    required this.displayDescription,
    required this.accessModules,
  });

  // Legacy alias for backward compatibility with tests
  String get nameKey => displayName;
  String get descriptionKey => displayDescription;
}
