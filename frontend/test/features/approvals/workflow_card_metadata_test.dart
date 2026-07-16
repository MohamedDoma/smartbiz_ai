// SmartBiz AI — Workflow Card Metadata Loading Tests.
//
// Focused tests for the coordinated metadata preload strategy that ensures
// workflow cards show loading states (not "Unavailable") while entity type
// descriptors and field schemas are being loaded.
//
// Tests:
//  1.  EntityFieldCatalogState starts with loading=true, not unavailable
//  2.  After entity types load, descriptor resolves to "Commission entry"
//  3.  Schema loading state is tracked correctly
//  4.  After schema loads, field resolves to "Commission Amount"
//  5.  English locale resolves "Commission entry" and "Commission Amount ≥ 500"
//  6.  Arabic locale resolves "سجل عمولة" and "قيمة العمولة ≥ 500"
//  7.  Only one schema request for multiple workflows with same entity type
//  8.  Two different entity types trigger one request each
//  9.  Metadata loading works when workflows arrive after init
// 10.  Metadata loading works when entity types arrive first
// 11.  F5-like empty-cache state resolves correctly
// 12.  Workspace switch clears metadata cache
// 13.  API error is not displayed as unavailable
// 14.  Confirmed missing entity shows unavailable only after loading
// 15.  Confirmed missing field shows unavailable only after schema loads
// 16.  Raw entity/field/operator keys never render

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/api_exceptions.dart';
import 'package:smartbiz_ai/core/api/approval_models.dart';
import 'package:smartbiz_ai/core/api/approval_service.dart';
import 'package:smartbiz_ai/core/api/entity_field_catalog_models.dart';
import 'package:smartbiz_ai/features/approvals/entity_field_catalog_state.dart';

// ═══════════════════════════════════════════════════════
//  Fixtures
// ═══════════════════════════════════════════════════════

const _commissionCatalogJson = <String, dynamic>{
  'entity_type': 'commission_entry',
  'label_en': 'Commission Entry',
  'label_ar': 'سجل عمولة',
  'module_key': 'commissions',
  'fields': [
    {
      'key': 'amount',
      'type': 'number',
      'label_en': 'Commission Amount',
      'label_ar': 'قيمة العمولة',
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
  ],
};

const _invoiceCatalogJson = <String, dynamic>{
  'entity_type': 'invoice',
  'label_en': 'Invoice',
  'label_ar': 'فاتورة',
  'module_key': 'invoicing',
  'fields': [
    {
      'key': 'total',
      'type': 'number',
      'label_en': 'Total',
      'label_ar': 'المجموع',
      'operators': ['equals', 'greater_than'],
      'options': null,
    },
  ],
};

const _commissionDescriptor = ApprovalEntityTypeDescriptor(
  entityType: 'commission_entry',
  labelEn: 'Commission entry',
  labelAr: 'سجل عمولة',
  moduleKey: 'commissions',
);

const _invoiceDescriptor = ApprovalEntityTypeDescriptor(
  entityType: 'invoice',
  labelEn: 'Invoice',
  labelAr: 'فاتورة',
  moduleKey: 'invoicing',
);

// ═══════════════════════════════════════════════════════
//  Fake ApprovalService
// ═══════════════════════════════════════════════════════

class _FakeApprovalService implements ApprovalService {
  List<ApprovalEntityTypeDescriptor>? entityTypesResult;
  Map<String, EntityFieldSchema?> schemaResults = {};
  Exception? entityTypesError;
  Exception? schemaError;
  int entityTypesCallCount = 0;
  Map<String, int> schemaCallCounts = {};

  @override
  Future<List<ApprovalEntityTypeDescriptor>> listEntityTypes() async {
    entityTypesCallCount++;
    if (entityTypesError != null) throw entityTypesError!;
    return entityTypesResult ?? [];
  }

  @override
  Future<EntityFieldSchema?> getEntityFieldSchema(String entityType) async {
    schemaCallCounts[entityType] = (schemaCallCounts[entityType] ?? 0) + 1;
    if (schemaError != null) throw schemaError!;
    return schemaResults[entityType];
  }

  int get totalSchemaCallCount =>
      schemaCallCounts.values.fold(0, (a, b) => a + b);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

// ═══════════════════════════════════════════════════════
//  Minimal workflow stub for loadMetadataForWorkflows
// ═══════════════════════════════════════════════════════

class _WorkflowStub {
  final String entityType;
  const _WorkflowStub(this.entityType);
}

void main() {
  late _FakeApprovalService svc;
  late EntityFieldCatalogState state;

  setUp(() {
    svc = _FakeApprovalService();
    state = EntityFieldCatalogState(svc);
    state.setWorkspace('ws1');
  });

  // ═══════════════════════════════════════════════════════
  //  1. Entity type starts as loading, not unavailable
  // ═══════════════════════════════════════════════════════

  test('1. entity type initially shows loading state', () {
    // Before loadEntityTypes has been called, entityTypesLoading is false
    // and entityTypes is null. The UI should show loading when we trigger.
    expect(state.entityTypes, isNull);
    expect(state.entityTypesLoading, isFalse);

    // After triggering load (but before it completes)
    svc.entityTypesResult = [_commissionDescriptor];
    final future = state.loadEntityTypes();

    // During load: loading flag is true
    // Note: since we are in async, the loading state is set synchronously
    // before the await. Check that it transitions.
    expect(state.entityTypesLoading, isTrue);

    // Complete the load
    return future.then((_) {
      expect(state.entityTypesLoading, isFalse);
      expect(state.entityTypes, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  2. After entity types load, descriptor resolves
  // ═══════════════════════════════════════════════════════

  test('2. after entity types load, descriptor resolves to label', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    await state.loadEntityTypes();

    final d = state.descriptorFor('commission_entry');
    expect(d, isNotNull);
    expect(d!.localizedLabel('en'), 'Commission entry');
    expect(d.localizedLabel('ar'), 'سجل عمولة');
  });

  // ═══════════════════════════════════════════════════════
  //  3. Schema loading state tracked correctly
  // ═══════════════════════════════════════════════════════

  test('3. schema loading state is tracked correctly', () async {
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    expect(state.isSchemaLoading('commission_entry'), isFalse);
    expect(state.schemaFor('commission_entry'), isNull);

    final future = state.loadSchema('commission_entry');

    // During load:
    expect(state.isSchemaLoading('commission_entry'), isTrue);

    await future;

    expect(state.isSchemaLoading('commission_entry'), isFalse);
    expect(state.schemaFor('commission_entry'), isNotNull);
  });

  // ═══════════════════════════════════════════════════════
  //  4. After schema loads, field resolves
  // ═══════════════════════════════════════════════════════

  test('4. after schema loads, field resolves to localized label', () async {
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );
    await state.loadSchema('commission_entry');

    final schema = state.schemaFor('commission_entry')!;
    final field = schema.fieldByKey('amount')!;
    expect(field.localizedLabel('en'), 'Commission Amount');
    expect(field.localizedLabel('ar'), 'قيمة العمولة');
  });

  // ═══════════════════════════════════════════════════════
  //  5. English card content resolves correctly
  // ═══════════════════════════════════════════════════════

  test(
    '5. English card shows "Commission entry" and "Commission Amount ≥ 500"',
    () async {
      svc.entityTypesResult = [_commissionDescriptor];
      svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
        _commissionCatalogJson,
      );

      await state.loadEntityTypes();
      await state.loadSchema('commission_entry');

      final entityLabel = state
          .descriptorFor('commission_entry')!
          .localizedLabel('en');
      expect(entityLabel, 'Commission entry');

      final schema = state.schemaFor('commission_entry')!;
      final fieldLabel = schema.fieldByKey('amount')!.localizedLabel('en');
      expect(fieldLabel, 'Commission Amount');

      // Simulate summary: "Commission Amount ≥ 500"
      final summary = '$fieldLabel ≥ 500';
      expect(summary, 'Commission Amount ≥ 500');
    },
  );

  // ═══════════════════════════════════════════════════════
  //  6. Arabic card content resolves correctly
  // ═══════════════════════════════════════════════════════

  test('6. Arabic card shows "سجل عمولة" and "قيمة العمولة ≥ 500"', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    await state.loadEntityTypes();
    await state.loadSchema('commission_entry');

    final entityLabel = state
        .descriptorFor('commission_entry')!
        .localizedLabel('ar');
    expect(entityLabel, 'سجل عمولة');

    final schema = state.schemaFor('commission_entry')!;
    final fieldLabel = schema.fieldByKey('amount')!.localizedLabel('ar');
    expect(fieldLabel, 'قيمة العمولة');

    final summary = '$fieldLabel ≥ 500';
    expect(summary, 'قيمة العمولة ≥ 500');
  });

  // ═══════════════════════════════════════════════════════
  //  7. Only one schema request for same entity type
  // ═══════════════════════════════════════════════════════

  test(
    '7. only one schema request for multiple workflows with same type',
    () async {
      svc.entityTypesResult = [_commissionDescriptor];
      svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
        _commissionCatalogJson,
      );

      final workflows = [
        const _WorkflowStub('commission_entry'),
        const _WorkflowStub('commission_entry'),
        const _WorkflowStub('commission_entry'),
      ];

      await state.loadMetadataForWorkflows(workflows);

      expect(
        svc.schemaCallCounts['commission_entry'],
        1,
        reason: 'Duplicate entity types must be deduplicated',
      );
    },
  );

  // ═══════════════════════════════════════════════════════
  //  8. Two different entity types trigger one request each
  // ═══════════════════════════════════════════════════════

  test('8. two different entity types trigger one request each', () async {
    svc.entityTypesResult = [_commissionDescriptor, _invoiceDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );
    svc.schemaResults['invoice'] = EntityFieldSchema.fromJson(
      _invoiceCatalogJson,
    );

    final workflows = [
      const _WorkflowStub('commission_entry'),
      const _WorkflowStub('invoice'),
      const _WorkflowStub('commission_entry'),
    ];

    await state.loadMetadataForWorkflows(workflows);

    expect(svc.schemaCallCounts['commission_entry'], 1);
    expect(svc.schemaCallCounts['invoice'], 1);
    expect(svc.totalSchemaCallCount, 2);
  });

  // ═══════════════════════════════════════════════════════
  //  9. Metadata loading works after workflows arrive
  // ═══════════════════════════════════════════════════════

  test('9. metadata loading works when workflows arrive after init', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    // Simulate: entity types not loaded yet, workflows arrive
    expect(state.entityTypes, isNull);

    final workflows = [const _WorkflowStub('commission_entry')];
    await state.loadMetadataForWorkflows(workflows);

    // Entity types should be loaded by loadMetadataForWorkflows
    expect(state.entityTypes, isNotNull);
    expect(state.schemaFor('commission_entry'), isNotNull);
  });

  // ═══════════════════════════════════════════════════════
  // 10. Entity types arrive first
  // ═══════════════════════════════════════════════════════

  test('10. metadata loading works when entity types arrive first', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    // Entity types loaded first
    await state.loadEntityTypes();
    expect(state.entityTypes, isNotNull);

    // Then workflows arrive
    final workflows = [const _WorkflowStub('commission_entry')];
    await state.loadMetadataForWorkflows(workflows);

    // Should use cached entity types (not re-fetch)
    expect(
      svc.entityTypesCallCount,
      1,
      reason: 'Cached entity types must be reused',
    );
    expect(state.schemaFor('commission_entry'), isNotNull);
  });

  // ═══════════════════════════════════════════════════════
  // 11. F5-like empty-cache state resolves correctly
  // ═══════════════════════════════════════════════════════

  test('11. F5-like empty-cache state resolves correctly', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    // Simulate F5: clear all cached data
    state.clearData();
    state.setWorkspace('ws1');

    expect(state.entityTypes, isNull);
    expect(state.schemaFor('commission_entry'), isNull);

    // Trigger metadata preload
    final workflows = [const _WorkflowStub('commission_entry')];
    await state.loadMetadataForWorkflows(workflows);

    expect(state.descriptorFor('commission_entry'), isNotNull);
    expect(state.schemaFor('commission_entry'), isNotNull);
    expect(
      state.descriptorFor('commission_entry')!.localizedLabel('ar'),
      'سجل عمولة',
    );
  });

  // ═══════════════════════════════════════════════════════
  // 12. Workspace switch clears metadata cache
  // ═══════════════════════════════════════════════════════

  test('12. workspace switch clears metadata cache', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    await state.loadEntityTypes();
    await state.loadSchema('commission_entry');

    expect(state.schemaFor('commission_entry'), isNotNull);

    // Switch workspace
    state.setWorkspace('ws2');

    expect(state.entityTypes, isNull);
    expect(state.schemaFor('commission_entry'), isNull);
    expect(state.testSchemaCache, isEmpty);
  });

  // ═══════════════════════════════════════════════════════
  // 13. API error is not displayed as unavailable
  // ═══════════════════════════════════════════════════════

  test('13. API error is not treated as unavailable', () async {
    svc.entityTypesError = const ApiException('Server error', statusCode: 500);

    await state.loadEntityTypes();

    // State has error, not empty/unavailable
    expect(state.entityTypesError, isNotNull);
    expect(state.entityTypesError, contains('Server error'));
    // Entity types should be null (not loaded), not empty list
    expect(state.entityTypes, isNull);
  });

  // ═══════════════════════════════════════════════════════
  // 14. Confirmed missing entity shows unavailable after loading
  // ═══════════════════════════════════════════════════════

  test(
    '14. confirmed missing entity shows unavailable only after loading',
    () async {
      svc.entityTypesResult = [_commissionDescriptor];

      // Before loading: descriptor is null but loading hasn't finished
      expect(state.descriptorFor('unknown_type'), isNull);
      expect(state.isEntityTypeResolved('unknown_type'), isFalse);

      await state.loadEntityTypes();

      // After loading: still null — genuinely unavailable
      expect(state.descriptorFor('unknown_type'), isNull);
      // But commission_entry is resolved
      expect(state.isEntityTypeResolved('commission_entry'), isTrue);
    },
  );

  // ═══════════════════════════════════════════════════════
  // 15. Confirmed missing field shows unavailable after schema loads
  // ═══════════════════════════════════════════════════════

  test(
    '15. confirmed missing field shows unavailable only after schema loads',
    () async {
      svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
        _commissionCatalogJson,
      );

      // Before loading: schema not available
      expect(state.schemaFor('commission_entry'), isNull);
      expect(state.isSchemaResolved('commission_entry'), isFalse);

      await state.loadSchema('commission_entry');

      // After loading: schema available
      final schema = state.schemaFor('commission_entry')!;
      expect(schema.fieldByKey('amount'), isNotNull);
      expect(schema.fieldByKey('nonexistent_field'), isNull);
      expect(state.isSchemaResolved('commission_entry'), isTrue);
    },
  );

  // ═══════════════════════════════════════════════════════
  // 16. Raw entity/field/operator keys never render
  // ═══════════════════════════════════════════════════════

  test('16. raw keys never appear in localized labels', () async {
    svc.entityTypesResult = [_commissionDescriptor];
    svc.schemaResults['commission_entry'] = EntityFieldSchema.fromJson(
      _commissionCatalogJson,
    );

    await state.loadEntityTypes();
    await state.loadSchema('commission_entry');

    // Entity type label is not the raw key
    final entityLabel = state
        .descriptorFor('commission_entry')!
        .localizedLabel('en');
    expect(entityLabel, isNot('commission_entry'));

    final entityLabelAr = state
        .descriptorFor('commission_entry')!
        .localizedLabel('ar');
    expect(entityLabelAr, isNot('commission_entry'));

    // Field label is not the raw key
    final schema = state.schemaFor('commission_entry')!;
    final field = schema.fieldByKey('amount')!;
    expect(field.localizedLabel('en'), isNot('amount'));
    expect(field.localizedLabel('ar'), isNot('amount'));

    // Schema-level label is not the raw key
    expect(schema.localizedLabel('en'), isNot('commission_entry'));
    expect(schema.localizedLabel('ar'), isNot('commission_entry'));
  });
}
