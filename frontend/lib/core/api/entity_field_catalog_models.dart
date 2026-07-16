// SmartBiz AI — Entity Field Catalog models.
//
// Models for the backend entity field catalog API.
// Used by the schema-driven approval condition builder to provide
// type-safe field selectors, operator filtering, and value inputs.
//
// Backend contracts:
//   GET /api/approval-entity-types
//   → Returns { "data": [{ "entity_type", "label_en", "label_ar", "module_key" }] }
//   GET /api/approval-entity-field-catalog?entity_type=<type>
//   → Returns { "data": { "entity_type", "label_en", "label_ar",
//       "module_key", "fields": [...] } }

// ═══════════════════════════════════════════════════════
//  Entity Type Descriptor (from GET /api/approval-entity-types)
// ═══════════════════════════════════════════════════════

/// Describes a registered entity type available for approval workflows.
///
/// Sourced from `GET /api/approval-entity-types`. Each descriptor
/// provides the entity key, localized labels, and module key.
/// Used by the workflow form dropdown to display entity types
/// without exposing raw technical keys.
class ApprovalEntityTypeDescriptor {
  /// The internal entity key (e.g. 'commission_entry').
  /// Used for caching, matching, and API submission only — never displayed.
  final String entityType;

  /// English display label (e.g. 'Commission entry').
  final String labelEn;

  /// Arabic display label (e.g. 'سجل عمولة').
  final String labelAr;

  /// Backend module key (e.g. 'commissions').
  final String? moduleKey;

  const ApprovalEntityTypeDescriptor({
    required this.entityType,
    required this.labelEn,
    required this.labelAr,
    this.moduleKey,
  });

  factory ApprovalEntityTypeDescriptor.fromJson(Map<String, dynamic> j) =>
      ApprovalEntityTypeDescriptor(
        entityType: j['entity_type'] as String,
        labelEn: j['label_en'] as String? ?? '',
        labelAr: j['label_ar'] as String? ?? '',
        moduleKey: j['module_key'] as String?,
      );

  /// Return the localized label based on the given language code.
  String localizedLabel(String langCode) =>
      langCode == 'ar' ? labelAr : labelEn;
}

// ═══════════════════════════════════════════════════════
//  Field Option (for enum fields)
// ═══════════════════════════════════════════════════════

/// An allowed value for an enum-type field.
///
/// Backend fields of type `enum` provide an `options` array with
/// each option containing a value and localized labels.
class FieldOption {
  final String value;
  final String labelEn;
  final String labelAr;

  const FieldOption({
    required this.value,
    required this.labelEn,
    required this.labelAr,
  });

  factory FieldOption.fromJson(Map<String, dynamic> j) => FieldOption(
    value: j['value'] as String,
    labelEn: j['label_en'] as String? ?? j['value'] as String,
    labelAr: j['label_ar'] as String? ?? j['value'] as String,
  );

  /// Return the localized label based on the given language code.
  String localizedLabel(String langCode) =>
      langCode == 'ar' ? labelAr : labelEn;
}

// ═══════════════════════════════════════════════════════
//  Field Schema
// ═══════════════════════════════════════════════════════

/// Full metadata for a single condition field within an entity type.
///
/// Each field specifies its key, data type, localized labels,
/// allowed operators, and optional enum options.
///
/// Backend field JSON shape:
/// ```json
/// {
///   "key": "amount",
///   "type": "number",
///   "label_en": "Commission Amount",
///   "label_ar": "مبلغ العمولة",
///   "operators": ["equals", "not_equals", "greater_than", ...],
///   "options": null
/// }
/// ```
class FieldSchema {
  /// The condition field key (e.g. 'amount', 'currency').
  final String key;

  /// The data type: 'number', 'string', 'enum'.
  final String type;

  /// English label for the field.
  final String labelEn;

  /// Arabic label for the field.
  final String labelAr;

  /// Operators valid for this field (subset of global operator list).
  final List<String> operators;

  /// Enum options, only populated when [type] == 'enum'.
  final List<FieldOption>? options;

  const FieldSchema({
    required this.key,
    required this.type,
    required this.labelEn,
    required this.labelAr,
    required this.operators,
    this.options,
  });

  factory FieldSchema.fromJson(Map<String, dynamic> j) {
    final rawOptions = j['options'];
    List<FieldOption>? opts;
    if (rawOptions is List && rawOptions.isNotEmpty) {
      opts = rawOptions
          .whereType<Map>()
          .map((e) => FieldOption.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return FieldSchema(
      key: j['key'] as String,
      type: j['type'] as String? ?? 'string',
      labelEn: j['label_en'] as String? ?? j['key'] as String,
      labelAr: j['label_ar'] as String? ?? j['key'] as String,
      operators:
          (j['operators'] as List?)?.map((e) => e.toString()).toList() ?? [],
      options: opts,
    );
  }

  /// Return the localized label based on the given language code.
  String localizedLabel(String langCode) =>
      langCode == 'ar' ? labelAr : labelEn;

  /// Whether this field is a numeric type.
  bool get isNumeric => type == 'number';

  /// Whether this field is an enum type with predefined options.
  bool get isEnum => type == 'enum' && options != null && options!.isNotEmpty;
}

// ═══════════════════════════════════════════════════════
//  Entity Field Schema (single entity detail mode)
// ═══════════════════════════════════════════════════════

/// Complete field schema for a single entity type.
///
/// Returned when `GET /api/approval-entity-field-catalog?entity_type=...`
/// is called with a specific entity type.
class EntityFieldSchema {
  final String entityType;
  final String labelEn;
  final String labelAr;

  /// Backend module key (e.g. 'commissions'). Optional metadata.
  final String? moduleKey;

  final List<FieldSchema> fields;

  const EntityFieldSchema({
    required this.entityType,
    required this.labelEn,
    required this.labelAr,
    this.moduleKey,
    required this.fields,
  });

  factory EntityFieldSchema.fromJson(Map<String, dynamic> j) =>
      EntityFieldSchema(
        entityType: j['entity_type'] as String,
        labelEn: j['label_en'] as String? ?? '',
        labelAr: j['label_ar'] as String? ?? '',
        moduleKey: j['module_key'] as String?,
        fields:
            (j['fields'] as List?)
                ?.whereType<Map>()
                .map((e) => FieldSchema.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
      );

  /// Return the localized entity label based on the given language code.
  String localizedLabel(String langCode) =>
      langCode == 'ar' ? labelAr : labelEn;

  /// Look up a field by key. Returns null if not found.
  FieldSchema? fieldByKey(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}
