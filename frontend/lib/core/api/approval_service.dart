// SmartBiz AI — Approval Engine API service.
import '../api/api_client.dart';
import '../api/approval_models.dart';

class ApprovalService {
  final ApiClient _c;
  ApprovalService(this._c);

  // ── Approval Requests ──────────────────────────────────

  Future<List<ApprovalRequest>> listRequests({
    String? scope,
    String? status,
    String? entityType,
  }) async {
    final params = <String, dynamic>{};
    if (scope != null) params['scope'] = scope;
    if (status != null) params['status'] = status;
    if (entityType != null) params['entity_type'] = entityType;
    final r = await _c.get('/approvals', queryParameters: params);
    return (r.data['data'] as List)
        .map((e) => ApprovalRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ApprovalRequest>> inbox() async {
    final r = await _c.get('/approvals/inbox');
    return (r.data['data'] as List)
        .map((e) => ApprovalRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ApprovalRequest> showRequest(String id) async {
    final r = await _c.get('/approvals/$id');
    return ApprovalRequest.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ApprovalRequest> submitRequest(ApprovalRequestPayload p) async {
    final r = await _c.post('/approvals', data: p.toJson());
    return ApprovalRequest.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ApprovalRequest> decide(String id, ApprovalDecisionPayload p) async {
    final r = await _c.post('/approvals/$id/decide', data: p.toJson());
    return ApprovalRequest.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ApprovalRequest> cancel(String id, {String? reason}) async {
    final data = <String, dynamic>{};
    if (reason != null) data['reason'] = reason;
    final r = await _c.post('/approvals/$id/cancel', data: data);
    return ApprovalRequest.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Approval Workflows (admin) ─────────────────────────

  Future<List<ApprovalWorkflow>> listWorkflows({
    String? entityType,
    bool? isActive,
  }) async {
    final params = <String, dynamic>{};
    if (entityType != null) params['entity_type'] = entityType;
    if (isActive != null) params['is_active'] = isActive.toString();
    final r = await _c.get('/approval-workflows', queryParameters: params);

    // Extract the list from the response, handling both
    // { "data": [...] } and bare [...] shapes.
    final dynamic body = r.data;
    final List<dynamic> items;
    if (body is Map && body.containsKey('data')) {
      final d = body['data'];
      if (d is List) {
        items = d;
      } else {
        throw FormatException(
          'GET /approval-workflows: expected data to be List, '
          'got ${d.runtimeType}',
        );
      }
    } else if (body is List) {
      items = body;
    } else {
      throw FormatException(
        'GET /approval-workflows: unexpected response shape '
        '${body.runtimeType}, expected Map with "data" key or List',
      );
    }

    return items
        .whereType<Map>()
        .map((e) => ApprovalWorkflow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ApprovalWorkflow> showWorkflow(String id) async {
    final r = await _c.get('/approval-workflows/$id');
    return ApprovalWorkflow.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ApprovalWorkflow> createWorkflow(ApprovalWorkflowPayload p) async {
    final r = await _c.post('/approval-workflows', data: p.toJson());
    return ApprovalWorkflow.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ApprovalWorkflow> updateWorkflow(
    String id,
    ApprovalWorkflowUpdatePayload p,
  ) async {
    final r = await _c.put('/approval-workflows/$id', data: p.toJson());
    return ApprovalWorkflow.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteWorkflow(String id) async =>
      await _c.delete('/approval-workflows/$id');

  Future<ApprovalWorkflowStep> addStep(
    String workflowId,
    ApprovalWorkflowStepPayload p,
  ) async {
    final r = await _c.post(
      '/approval-workflows/$workflowId/steps',
      data: p.toJson(),
    );
    return ApprovalWorkflowStep.fromJson(
      r.data['data'] as Map<String, dynamic>,
    );
  }

  Future<ApprovalWorkflowStep> updateStep(
    String stepId,
    Map<String, dynamic> data,
  ) async {
    final r = await _c.put('/approval-workflow-steps/$stepId', data: data);
    return ApprovalWorkflowStep.fromJson(
      r.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteStep(String stepId) async =>
      await _c.delete('/approval-workflow-steps/$stepId');
}
