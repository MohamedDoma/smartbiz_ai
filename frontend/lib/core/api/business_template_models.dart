// SmartBiz AI — Business template models for frontend API.

/// Summary of a business template returned by GET /api/business-templates.
class BusinessTemplateSummary {
  final String id;
  final String templateKey;
  final String name;
  final String? description;
  final String industryType;
  final String? businessSize;
  final int version;
  final bool isDefault;
  final int moduleCount;

  const BusinessTemplateSummary({
    required this.id,
    required this.templateKey,
    required this.name,
    this.description,
    required this.industryType,
    this.businessSize,
    this.version = 1,
    this.isDefault = false,
    this.moduleCount = 0,
  });

  factory BusinessTemplateSummary.fromJson(Map<String, dynamic> json) =>
      BusinessTemplateSummary(
        id: json['id'] as String? ?? '',
        templateKey: json['template_key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        industryType: json['industry_type'] as String? ?? '',
        businessSize: json['business_size'] as String?,
        version: json['version'] as int? ?? 1,
        isDefault: json['is_default'] as bool? ?? false,
        moduleCount: json['module_count'] as int? ?? 0,
      );
}

/// Result of POST /api/business-templates/{key}/apply.
class TemplateApplicationResult {
  final String id;
  final String templateKey;
  final int templateVersion;
  final String status;
  final String? appliedAt;

  const TemplateApplicationResult({
    required this.id,
    required this.templateKey,
    this.templateVersion = 1,
    this.status = 'applied',
    this.appliedAt,
  });

  factory TemplateApplicationResult.fromJson(Map<String, dynamic> json) =>
      TemplateApplicationResult(
        id: json['id'] as String? ?? '',
        templateKey: json['template_key'] as String? ?? '',
        templateVersion: json['template_version'] as int? ?? 1,
        status: json['status'] as String? ?? 'applied',
        appliedAt: json['applied_at'] as String?,
      );
}
