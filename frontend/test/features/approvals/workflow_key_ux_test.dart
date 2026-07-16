// Tests for workflow_key UX removal and payload correctness.
//
// Verifies:
//  1. Create payload omits workflow_key.
//  2. Edit payload (ApprovalWorkflowUpdatePayload) omits workflow_key.
//  3. Existing API response still parses workflow_key internally.
//  4. Arabic workflow name is submitted correctly.
//  5. Payload with explicit key conditionally includes it.
//  6. Empty workflowKey is excluded from payload.
//  7. ApprovalWorkflow model stores workflowKey for internal use.
//  8. ApprovalWorkflowUpdatePayload never contains workflow_key.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/approval_models.dart';

void main() {
  group('WorkflowKey UX Removal', () {
    // ═══════════════════════════════════════════════════════
    //  1. Create payload omits workflow_key
    // ═══════════════════════════════════════════════════════

    test('create payload omits workflow_key when not provided', () {
      const payload = ApprovalWorkflowPayload(
        name: 'Test Workflow',
        entityType: 'commission_entry',
      );

      final json = payload.toJson();

      expect(
        json.containsKey('workflow_key'),
        isFalse,
        reason: 'Normal create payload must not contain workflow_key',
      );
      expect(json['name'], equals('Test Workflow'));
      expect(json['entity_type'], equals('commission_entry'));
    });

    // ═══════════════════════════════════════════════════════
    //  2. Edit payload omits workflow_key
    // ═══════════════════════════════════════════════════════

    test('edit payload never contains workflow_key', () {
      const payload = ApprovalWorkflowUpdatePayload(
        name: 'Updated Name',
        description: 'New description',
      );

      final json = payload.toJson();

      expect(
        json.containsKey('workflow_key'),
        isFalse,
        reason: 'Update payload must never contain workflow_key',
      );
      expect(json['name'], equals('Updated Name'));
    });

    // ═══════════════════════════════════════════════════════
    //  3. API response parses workflow_key internally
    // ═══════════════════════════════════════════════════════

    test('existing API response parses workflow_key internally', () {
      final workflow = ApprovalWorkflow.fromJson({
        'id': 'test-id-123',
        'workflow_key': 'high_commission_manual_test',
        'name': 'High Commission Approval',
        'entity_type': 'commission_entry',
        'is_active': true,
        'sort_order': 0,
        'steps': [],
      });

      expect(
        workflow.workflowKey,
        equals('high_commission_manual_test'),
        reason: 'Model must store workflowKey for internal use',
      );
      expect(workflow.name, equals('High Commission Approval'));
      expect(workflow.id, equals('test-id-123'));
    });

    // ═══════════════════════════════════════════════════════
    //  4. Arabic workflow name is submitted correctly
    // ═══════════════════════════════════════════════════════

    test('Arabic workflow name is submitted correctly', () {
      const payload = ApprovalWorkflowPayload(
        name: 'اعتماد العمولات المرتفعة',
        description: 'يتطلب اعتماد العمولات التي تساوي أو تتجاوز ٥٠٠',
        entityType: 'commission_entry',
      );

      final json = payload.toJson();

      expect(json['name'], equals('اعتماد العمولات المرتفعة'));
      expect(
        json['description'],
        equals('يتطلب اعتماد العمولات التي تساوي أو تتجاوز ٥٠٠'),
      );
      expect(json.containsKey('workflow_key'), isFalse);
    });

    // ═══════════════════════════════════════════════════════
    //  5. Explicit key conditionally included
    // ═══════════════════════════════════════════════════════

    test('payload with explicit key includes it', () {
      const payload = ApprovalWorkflowPayload(
        workflowKey: 'custom_explicit_key',
        name: 'Explicit Test',
        entityType: 'commission_entry',
      );

      final json = payload.toJson();

      expect(json.containsKey('workflow_key'), isTrue);
      expect(json['workflow_key'], equals('custom_explicit_key'));
    });

    // ═══════════════════════════════════════════════════════
    //  6. Empty workflowKey excluded
    // ═══════════════════════════════════════════════════════

    test('empty workflowKey is excluded from payload', () {
      const payload = ApprovalWorkflowPayload(
        workflowKey: '',
        name: 'Empty Key Test',
        entityType: 'commission_entry',
      );

      final json = payload.toJson();

      expect(
        json.containsKey('workflow_key'),
        isFalse,
        reason: 'Empty string workflow_key must not be sent to the server',
      );
    });

    // ═══════════════════════════════════════════════════════
    //  7. Model stores workflowKey for internal use
    // ═══════════════════════════════════════════════════════

    test('model stores workflowKey for internal use', () {
      final workflow = ApprovalWorkflow.fromJson({
        'id': 'wf-abc-123',
        'workflow_key': 'wf_01JTEST12345678901234',
        'name': 'Test',
        'entity_type': 'commission_entry',
        'is_active': true,
        'sort_order': 0,
        'steps': [],
      });

      expect(workflow.workflowKey, equals('wf_01JTEST12345678901234'));
    });

    // ═══════════════════════════════════════════════════════
    //  8. Update payload never contains workflow_key
    // ═══════════════════════════════════════════════════════

    test('update payload with all fields still excludes workflow_key', () {
      const payload = ApprovalWorkflowUpdatePayload(
        name: 'New Name',
        description: 'New Desc',
        isActive: false,
        sortOrder: 5,
      );

      final json = payload.toJson();

      expect(json.containsKey('workflow_key'), isFalse);
      expect(json['name'], equals('New Name'));
      expect(json['is_active'], equals(false));
      expect(json['sort_order'], equals(5));
    });
  });
}
