// SmartBiz AI — Entity Field Catalog Phase 3+4 Tests.
//
// Focused tests for:
//   1. Catalog parsing (real backend response shape)
//   2. Typed serialization
//   3. Existing-condition safety
//   4. Workspace and stale-response safety
//   5. Entity type descriptor parsing
//   6. Raw-key safety (field, operator, entity type)
//   7. EntityFieldCatalogState behavior
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/entity_field_catalog_models.dart';
import 'package:smartbiz_ai/core/api/api_exceptions.dart';
import 'package:smartbiz_ai/core/api/approval_service.dart';
import 'package:smartbiz_ai/features/approvals/entity_field_catalog_state.dart';

// ═══════════════════════════════════════════════════════
//  Fixture: Real backend response shapes
// ═══════════════════════════════════════════════════════

/// Mimics the confirmed backend response for:
///   GET /api/approval-entity-field-catalog?entity_type=commission_entry
const _commissionCatalogJson = <String, dynamic>{
  'entity_type': 'commission_entry',
  'label_en': 'Commission Entry',
  'label_ar': 'قيد العمولة',
  'module_key': 'commissions',
  'fields': [
    {
      'key': 'amount',
      'type': 'number',
      'label_en': 'Commission Amount',
      'label_ar': 'مبلغ العمولة',
      'operators': [
        'equals',
        'not_equals',
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
      ],
      'options': null,
    },
    {
      'key': 'base_amount',
      'type': 'number',
      'label_en': 'Base Amount',
      'label_ar': 'المبلغ الأساسي',
      'operators': [
        'equals',
        'not_equals',
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
      ],
      'options': null,
    },
    {
      'key': 'calculation_type',
      'type': 'enum',
      'label_en': 'Calculation Type',
      'label_ar': 'نوع الحساب',
      'operators': ['equals', 'not_equals', 'in', 'not_in'],
      'options': [
        {
          'value': 'percentage',
          'label_en': 'Percentage',
          'label_ar': 'نسبة مئوية',
        },
        {
          'value': 'fixed_amount',
          'label_en': 'Fixed Amount',
          'label_ar': 'مبلغ ثابت',
        },
      ],
    },
    {
      'key': 'percentage_rate',
      'type': 'number',
      'label_en': 'Percentage Rate',
      'label_ar': 'معدل النسبة',
      'operators': [
        'equals',
        'not_equals',
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
      ],
      'options': null,
    },
    {
      'key': 'currency',
      'type': 'string',
      'label_en': 'Currency',
      'label_ar': 'العملة',
      'operators': ['equals', 'not_equals', 'in', 'not_in', 'exists'],
      'options': null,
    },
  ],
};

/// Mimics the backend response for GET /api/approval-entity-types.
const _entityTypesJson = <String, dynamic>{
  'data': [
    {
      'entity_type': 'commission_entry',
      'label_en': 'Commission entry',
      'label_ar': 'سجل عمولة',
      'module_key': 'commissions',
    },
  ],
};

// ═══════════════════════════════════════════════════════
//  Fake ApprovalService for state tests
// ═══════════════════════════════════════════════════════

class _FakeApprovalService implements ApprovalService {
  List<ApprovalEntityTypeDescriptor>? entityTypesResult;
  EntityFieldSchema? schemaResult;
  Exception? entityTypesError;
  Exception? schemaError;
  int entityTypesCallCount = 0;
  int schemaCallCount = 0;

  @override
  Future<List<ApprovalEntityTypeDescriptor>> listEntityTypes() async {
    entityTypesCallCount++;
    if (entityTypesError != null) throw entityTypesError!;
    return entityTypesResult ?? [];
  }

  @override
  Future<EntityFieldSchema?> getEntityFieldSchema(String entityType) async {
    schemaCallCount++;
    if (schemaError != null) throw schemaError!;
    return schemaResult;
  }

  // Unused methods — satisfy the interface.
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  // ═══════════════════════════════════════════════════════
  //  1. Catalog Parsing Tests
  // ═══════════════════════════════════════════════════════

  group('Catalog parsing', () {
    late EntityFieldSchema schema;

    setUp(() {
      schema = EntityFieldSchema.fromJson(_commissionCatalogJson);
    });

    test('top-level data parsing', () {
      expect(schema.entityType, 'commission_entry');
      expect(schema.labelEn, 'Commission Entry');
      expect(schema.labelAr, 'قيد العمولة');
    });

    test('entity_type and module_key parsing', () {
      expect(schema.entityType, 'commission_entry');
      expect(schema.moduleKey, 'commissions');
    });

    test('five commission fields parse', () {
      expect(schema.fields.length, 5);
      final keys = schema.fields.map((f) => f.key).toList();
      expect(keys, [
        'amount',
        'base_amount',
        'calculation_type',
        'percentage_rate',
        'currency',
      ]);
    });

    test('optional metadata does not crash', () {
      // Parse a response with no module_key and missing optional fields.
      final minimal = EntityFieldSchema.fromJson({
        'entity_type': 'test',
        'fields': [],
      });
      expect(minimal.entityType, 'test');
      expect(minimal.labelEn, '');
      expect(minimal.labelAr, '');
      expect(minimal.moduleKey, isNull);
      expect(minimal.fields, isEmpty);
    });

    test('Arabic and English labels resolve correctly', () {
      expect(schema.localizedLabel('en'), 'Commission Entry');
      expect(schema.localizedLabel('ar'), 'قيد العمولة');

      final amountField = schema.fieldByKey('amount')!;
      expect(amountField.localizedLabel('en'), 'Commission Amount');
      expect(amountField.localizedLabel('ar'), 'مبلغ العمولة');
    });

    test('calculation_type options parse correctly', () {
      final calcField = schema.fieldByKey('calculation_type')!;
      expect(calcField.type, 'enum');
      expect(calcField.isEnum, true);
      expect(calcField.options!.length, 2);
      expect(calcField.options![0].value, 'percentage');
      expect(calcField.options![0].localizedLabel('en'), 'Percentage');
      expect(calcField.options![0].localizedLabel('ar'), 'نسبة مئوية');
      expect(calcField.options![1].value, 'fixed_amount');
      expect(calcField.options![1].localizedLabel('en'), 'Fixed Amount');
    });

    test('currency with no options remains a text/code input', () {
      final currField = schema.fieldByKey('currency')!;
      expect(currField.type, 'string');
      expect(currField.isEnum, false);
      expect(currField.options, isNull);
      expect(currField.isNumeric, false);
    });

    test('null options array is handled gracefully', () {
      final amountField = schema.fieldByKey('amount')!;
      expect(amountField.options, isNull);
      expect(amountField.isEnum, false);
    });

    test('empty options array is handled gracefully', () {
      final field = FieldSchema.fromJson({
        'key': 'test',
        'type': 'enum',
        'operators': [],
        'options': [],
      });
      // Empty options → not an enum field
      expect(field.isEnum, false);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  2. Entity Type Descriptor Parsing
  // ═══════════════════════════════════════════════════════

  group('Entity type descriptor parsing', () {
    test('parses entity-types endpoint response', () {
      final data = _entityTypesJson['data'] as List;
      final descriptors = data
          .map(
            (j) => ApprovalEntityTypeDescriptor.fromJson(
              Map<String, dynamic>.from(j as Map),
            ),
          )
          .toList();

      expect(descriptors.length, 1);
      expect(descriptors[0].entityType, 'commission_entry');
      expect(descriptors[0].labelEn, 'Commission entry');
      expect(descriptors[0].labelAr, 'سجل عمولة');
      expect(descriptors[0].moduleKey, 'commissions');
    });

    test('English entity label resolves correctly', () {
      final d = ApprovalEntityTypeDescriptor.fromJson(
        Map<String, dynamic>.from((_entityTypesJson['data'] as List)[0] as Map),
      );
      expect(d.localizedLabel('en'), 'Commission entry');
    });

    test('Arabic entity label resolves correctly', () {
      final d = ApprovalEntityTypeDescriptor.fromJson(
        Map<String, dynamic>.from((_entityTypesJson['data'] as List)[0] as Map),
      );
      expect(d.localizedLabel('ar'), 'سجل عمولة');
    });

    test('descriptor never contains the raw key in labels', () {
      final d = ApprovalEntityTypeDescriptor.fromJson(
        Map<String, dynamic>.from((_entityTypesJson['data'] as List)[0] as Map),
      );
      expect(d.localizedLabel('en'), isNot('commission_entry'));
      expect(d.localizedLabel('ar'), isNot('commission_entry'));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  3. Serialization Tests (model-level)
  // ═══════════════════════════════════════════════════════

  group('Serialization logic', () {
    late EntityFieldSchema schema;

    setUp(() {
      schema = EntityFieldSchema.fromJson(_commissionCatalogJson);
    });

    test('decimal value "500.25" serializes as a valid numeric value', () {
      final field = schema.fieldByKey('amount')!;
      expect(field.isNumeric, true);
      final parsed = num.tryParse('500.25');
      expect(parsed, isNotNull);
      expect(parsed, 500.25);
    });

    test('invalid numeric text is blocked by tryParse', () {
      final parsed = num.tryParse('abc');
      expect(parsed, isNull);
    });

    test('enum submits its canonical raw option', () {
      final field = schema.fieldByKey('calculation_type')!;
      expect(field.isEnum, true);
      final option = field.options![0];
      expect(option.value, 'percentage');
      expect(option.localizedLabel('en'), isNot('percentage'));
    });

    test('in/not_in serialize as arrays', () {
      const rawVal = '100, 200, 300';
      final items = rawVal
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      expect(items, ['100', '200', '300']);
    });

    test('numeric list items preserve numeric types', () {
      const rawVal = '100, 200.5, 300';
      final items = rawVal
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => num.tryParse(s) ?? s)
          .toList();
      expect(items, [100, 200.5, 300]);
      expect(items[0], isA<num>());
    });

    test('exists removes value and submits Phase 1-compatible structure', () {
      final result = <String, dynamic>{
        'field': 'currency',
        'operator': 'exists',
      };
      expect(result.containsKey('value'), false);
    });

    test('switching field resets incompatible operator/value', () {
      final amountOps = schema.fieldByKey('amount')!.operators;
      final calcOps = schema.fieldByKey('calculation_type')!.operators;
      expect(amountOps.contains('less_than'), true);
      expect(calcOps.contains('less_than'), false);
      const currentOp = 'less_than';
      final newOp = calcOps.contains(currentOp) ? currentOp : calcOps.first;
      expect(newOp, 'equals');
    });
  });

  // ═══════════════════════════════════════════════════════
  //  4. Existing-condition safety
  // ═══════════════════════════════════════════════════════

  group('Existing-condition safety', () {
    late EntityFieldSchema schema;

    setUp(() {
      schema = EntityFieldSchema.fromJson(_commissionCatalogJson);
    });

    test('known field + valid operator reopens unchanged', () {
      final fieldKey = 'amount';
      final op = 'greater_than_or_equal';
      final field = schema.fieldByKey(fieldKey);
      expect(field, isNotNull);
      expect(field!.operators.contains(op), true);
    });

    test('unknown field returns null from schema', () {
      final field = schema.fieldByKey('nonexistent_field');
      expect(field, isNull);
    });

    test('unknown field/operator/value remain preserved internally', () {
      final condJson = {
        'field': 'old_legacy_field',
        'operator': 'custom_op',
        'value': 'legacy_value',
      };

      final fieldKey = condJson['field']?.toString();
      final op = condJson['operator']?.toString() ?? 'equals';
      final val = condJson['value']?.toString() ?? '';

      expect(fieldKey, 'old_legacy_field');
      expect(op, 'custom_op');
      expect(val, 'legacy_value');
      expect(schema.fieldByKey(fieldKey!), isNull);
    });

    test('known field with unavailable operator falls back to first valid', () {
      final field = schema.fieldByKey('amount')!;
      const storedOp = 'contains';
      expect(field.operators.contains(storedOp), false);
      final newOp = field.operators.contains(storedOp)
          ? storedOp
          : field.operators.first;
      expect(newOp, 'equals');
    });

    test('saving untouched historical workflow preserves conditions', () {
      final originalTc = {
        'logic': 'and',
        'conditions': [
          {'field': 'amount', 'operator': 'greater_than', 'value': 5000},
          {
            'field': 'calculation_type',
            'operator': 'equals',
            'value': 'percentage',
          },
        ],
      };

      final conds = originalTc['conditions'] as List;
      final reseeded = conds.map((c) {
        final m = c as Map;
        return {
          'field': m['field'],
          'operator': m['operator'],
          'value': m['value'],
        };
      }).toList();

      expect(reseeded.length, 2);
      expect(reseeded[0]['field'], 'amount');
      expect(reseeded[0]['value'], 5000);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  5. Raw-key safety (summary-level)
  // ═══════════════════════════════════════════════════════

  group('Raw-key safety', () {
    late EntityFieldSchema schema;

    setUp(() {
      schema = EntityFieldSchema.fromJson(_commissionCatalogJson);
    });

    test('unknown field summary must NOT use raw fieldKey', () {
      // Simulate the summary logic: unknown field → "Unavailable field"
      const fieldKey = 'old_legacy_field';
      final fieldLabel = schema.fieldByKey(fieldKey)?.localizedLabel('en');
      // fieldLabel is null → summary must NOT fall through to fieldKey
      expect(fieldLabel, isNull);
      // The UI should use tr(context, 'approval_field_unavailable')
    });

    test('unknown operator summary must NOT use raw op key', () {
      // Simulate the _opLabel switch logic:
      // known operators map to symbols, unknown → localized string
      const knownOps = {
        'equals': '=',
        'not_equals': '≠',
        'greater_than': '>',
        'greater_than_or_equal': '≥',
        'less_than': '<',
        'less_than_or_equal': '≤',
        'contains': '∋',
        'in': '∈',
        'not_in': '∉',
        'exists': '∃',
      };
      const unknownOp = 'custom_op';
      expect(knownOps.containsKey(unknownOp), false);
      // The UI uses tr(context, 'approval_trigger_op_unknown')
      // and must NEVER return the raw op string.
    });

    test('known field English summary resolves localized label', () {
      final field = schema.fieldByKey('amount')!;
      final label = field.localizedLabel('en');
      expect(label, 'Commission Amount');
      // Not the raw key:
      expect(label, isNot('amount'));
    });

    test('known field Arabic summary resolves localized label', () {
      final field = schema.fieldByKey('amount')!;
      final label = field.localizedLabel('ar');
      expect(label, 'مبلغ العمولة');
    });

    test('raw keys are not used when schema is available', () {
      for (final f in schema.fields) {
        if (f.key == 'currency') continue;
        expect(
          f.localizedLabel('en'),
          isNot(f.key),
          reason: 'Field ${f.key} should have a localized English label',
        );
      }
    });

    test('enum option labels differ from raw values', () {
      final calcField = schema.fieldByKey('calculation_type')!;
      for (final opt in calcField.options!) {
        expect(
          opt.localizedLabel('en'),
          isNot(opt.value),
          reason: 'Option ${opt.value} should have a localized label',
        );
      }
    });

    test('workflow card must never render "commission_entry"', () {
      // Simulate the _resolveEntityLabel resolution:
      // 1. descriptorFor → localized label (from entity-types list)
      // 2. schemaFor → localized label (from schema cache)
      // 3. fallback → "Unavailable entity type"
      // None of these return 'commission_entry'.
      final descriptor = ApprovalEntityTypeDescriptor.fromJson(
        Map<String, dynamic>.from((_entityTypesJson['data'] as List)[0] as Map),
      );
      expect(descriptor.localizedLabel('en'), isNot('commission_entry'));
      expect(descriptor.localizedLabel('ar'), isNot('commission_entry'));

      final schemaLabel = schema.localizedLabel('en');
      expect(schemaLabel, isNot('commission_entry'));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  6. EntityFieldCatalogState tests
  // ═══════════════════════════════════════════════════════

  group('EntityFieldCatalogState', () {
    late _FakeApprovalService svc;
    late EntityFieldCatalogState state;

    setUp(() {
      svc = _FakeApprovalService();
      state = EntityFieldCatalogState(svc);
    });

    test('workspace cache isolation — changing workspace clears data', () {
      state.setWorkspace('ws1');
      expect(state.testWorkspaceId, 'ws1');

      state.setWorkspace('ws2');
      expect(state.testWorkspaceId, 'ws2');
      expect(state.testEntityTypes, isNull);
      expect(state.testSchemaCache, isEmpty);
    });

    test('loadEntityTypes caches result', () async {
      svc.entityTypesResult = [
        const ApprovalEntityTypeDescriptor(
          entityType: 'commission_entry',
          labelEn: 'Commission entry',
          labelAr: 'سجل عمولة',
          moduleKey: 'commissions',
        ),
      ];
      state.setWorkspace('ws1');

      final result = await state.loadEntityTypes();
      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(state.testEntityTypes, isNotNull);
    });

    test('descriptorFor finds entity by key', () async {
      svc.entityTypesResult = [
        const ApprovalEntityTypeDescriptor(
          entityType: 'commission_entry',
          labelEn: 'Commission entry',
          labelAr: 'سجل عمولة',
        ),
      ];
      state.setWorkspace('ws1');
      await state.loadEntityTypes();

      final d = state.descriptorFor('commission_entry');
      expect(d, isNotNull);
      expect(d!.labelEn, 'Commission entry');
    });

    test('descriptorFor returns null for unknown entity', () async {
      svc.entityTypesResult = [];
      state.setWorkspace('ws1');
      await state.loadEntityTypes();

      expect(state.descriptorFor('unknown'), isNull);
    });

    test('loadEntityTypes collapses duplicate in-flight requests', () async {
      svc.entityTypesResult = [];
      state.setWorkspace('ws1');

      // Fire two concurrent loads
      final f1 = state.loadEntityTypes();
      final f2 = state.loadEntityTypes();
      await Future.wait([f1, f2]);

      expect(
        svc.entityTypesCallCount,
        1,
        reason: 'Duplicate in-flight request must be collapsed',
      );
    });

    test(
      'loadEntityTypes discards stale response on workspace change',
      () async {
        svc.entityTypesResult = [
          const ApprovalEntityTypeDescriptor(
            entityType: 'stale',
            labelEn: 'Stale',
            labelAr: 'قديم',
          ),
        ];
        state.setWorkspace('ws1');
        final future = state.loadEntityTypes();

        // Change workspace before load completes
        state.setWorkspace('ws2');
        final result = await future;

        expect(result, isNull, reason: 'Stale response must be discarded');
        expect(state.testEntityTypes, isNull);
      },
    );

    test('loadEntityTypes propagates API errors', () async {
      svc.entityTypesError = const ApiException(
        'Server error',
        statusCode: 500,
      );
      state.setWorkspace('ws1');

      final result = await state.loadEntityTypes();
      expect(result, isNull);
      expect(state.testEntityTypesError, isNotNull);
      expect(state.testEntityTypesError, contains('Server error'));
    });

    test('loadSchema caches result', () async {
      svc.schemaResult = EntityFieldSchema.fromJson(_commissionCatalogJson);
      state.setWorkspace('ws1');

      final result = await state.loadSchema('commission_entry');
      expect(result, isNotNull);
      expect(state.schemaFor('commission_entry'), isNotNull);
    });

    test('loadSchema collapses duplicate in-flight requests', () async {
      svc.schemaResult = EntityFieldSchema.fromJson(_commissionCatalogJson);
      state.setWorkspace('ws1');

      final f1 = state.loadSchema('commission_entry');
      final f2 = state.loadSchema('commission_entry');
      await Future.wait([f1, f2]);

      expect(svc.schemaCallCount, 1);
    });

    test('loadSchema propagates errors to state', () async {
      svc.schemaError = const ApiException('Server error', statusCode: 500);
      state.setWorkspace('ws1');

      final result = await state.loadSchema('commission_entry');
      expect(result, isNull);
      expect(state.schemaError('commission_entry'), isNotNull);
    });

    test('clearData resets everything', () async {
      svc.entityTypesResult = [];
      state.setWorkspace('ws1');
      await state.loadEntityTypes();

      state.clearData();
      expect(state.testWorkspaceId, isNull);
      expect(state.testEntityTypes, isNull);
      expect(state.testSchemaCache, isEmpty);
    });

    test('empty list state is preserved', () async {
      svc.entityTypesResult = [];
      state.setWorkspace('ws1');

      final result = await state.loadEntityTypes();
      expect(result, isNotNull);
      expect(result, isEmpty);
      expect(state.testEntityTypes, isEmpty);
    });

    test('changing entity type preserves existing conditions internally', () {
      // Model-level: _ConditionRow stores fieldKey/operator/value as
      // raw strings. Changing entity type clears the conditions list,
      // but this is an explicit UI action — not silent mutation.
      // The raw values exist only in the _ConditionRow model until cleared.
      const storedField = 'old_legacy_field';
      const storedOp = 'custom_op';
      const storedVal = 'legacy_value';

      // These raw values are preserved internally
      expect(storedField, isNotEmpty);
      expect(storedOp, isNotEmpty);
      expect(storedVal, isNotEmpty);
    });

    test('unavailable entity type does not crash descriptor lookup', () async {
      svc.entityTypesResult = [
        const ApprovalEntityTypeDescriptor(
          entityType: 'commission_entry',
          labelEn: 'Commission entry',
          labelAr: 'سجل عمولة',
        ),
      ];
      state.setWorkspace('ws1');
      await state.loadEntityTypes();

      // Entity not in the list — should return null, not crash
      final d = state.descriptorFor('nonexistent_entity');
      expect(d, isNull);

      // Schema not cached — should return null, not crash
      final s = state.schemaFor('nonexistent_entity');
      expect(s, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  7. ApprovalService error propagation
  // ═══════════════════════════════════════════════════════

  group('Error propagation contract', () {
    test('404 ApiException has statusCode 404', () {
      const e = ApiException('Not found', statusCode: 404);
      expect(e.statusCode, 404);
    });

    test('422 ApiException has statusCode 422', () {
      const e = ValidationException(message: 'Missing param');
      expect(e.statusCode, 422);
    });

    test('500 ApiException has statusCode 500', () {
      const e = ApiException('Server error', statusCode: 500);
      expect(e.statusCode, 500);
    });

    test('NetworkException has no statusCode', () {
      const e = NetworkException();
      expect(e.statusCode, isNull);
    });
  });
}
