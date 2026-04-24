// SmartBiz AI — AI Advisor recommendation models.

/// Impact level of a recommendation.
enum RecImpact { high, medium, low }

/// Category of a recommendation.
enum RecCategory { finance, inventory, sales, operations, system }

/// Status of a recommendation.
enum RecStatus { active, dismissed, applied, later }

/// A single AI recommendation.
class Recommendation {
  final String id;
  final String titleKey;
  final String descriptionKey;
  final String detailKey;
  final RecCategory category;
  final RecImpact impact;
  final double confidence; // 0.0 - 1.0
  final DateTime createdAt;
  RecStatus status;

  Recommendation({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.detailKey,
    required this.category,
    required this.impact,
    required this.confidence,
    required this.createdAt,
    this.status = RecStatus.active,
  });
}
