// SmartBiz AI — Onboarding / discovery models.

/// A single message in the discovery conversation.
class DiscoveryMessage {
  final String id;
  final String text;
  final MessageSender sender;
  final DateTime timestamp;
  final List<String>? quickReplies;
  final bool isThinking;

  const DiscoveryMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.quickReplies,
    this.isThinking = false,
  });
}

enum MessageSender { user, ai }

/// Discovery progress categories.
enum DiscoveryCategory {
  companyBasics,
  businessType,
  operations,
  teamRoles,
  productsServices,
  financeWorkflows,
}

/// Tracks which categories are complete.
class DiscoveryProgress {
  final Map<DiscoveryCategory, bool> categories;

  const DiscoveryProgress({required this.categories});

  factory DiscoveryProgress.initial() {
    return DiscoveryProgress(
      categories: {for (final c in DiscoveryCategory.values) c: false},
    );
  }

  double get completionPercent {
    final done = categories.values.where((v) => v).length;
    return done / categories.length;
  }

  bool get isComplete => categories.values.every((v) => v);

  int get completedCount => categories.values.where((v) => v).length;

  DiscoveryProgress copyWith(DiscoveryCategory category, bool done) {
    final updated = Map<DiscoveryCategory, bool>.from(categories);
    updated[category] = done;
    return DiscoveryProgress(categories: updated);
  }
}

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
  final String nameKey;
  final String descriptionKey;
  final String icon;
  final bool included;

  const BlueprintModule({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.icon,
    this.included = true,
  });
}

class BlueprintRole {
  final String id;
  final String nameKey;
  final String descriptionKey;
  final List<String> accessModules;

  const BlueprintRole({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.accessModules,
  });
}
