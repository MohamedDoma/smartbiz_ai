// SmartBiz AI — Commission API service.
import '../api/api_client.dart';
import '../api/commission_models.dart';

class CommissionService {
  final ApiClient _c;
  CommissionService(this._c);

  // ── Settings Options (permission-safe) ──────────────────
  Future<CommissionSettingsOptions> getSettingsOptions() async {
    final r = await _c.get('/commission-settings/options');
    return CommissionSettingsOptions.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Plans ───────────────────────────────────────────────
  Future<List<CommissionPlan>> listPlans() async {
    final r = await _c.get('/commission-plans');
    return (r.data['data'] as List).map((e) => CommissionPlan.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CommissionPlan> createPlan(CommissionPlanPayload p) async {
    final r = await _c.post('/commission-plans', data: p.toJson());
    return CommissionPlan.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CommissionPlan> updatePlan(String id, CommissionPlanUpdatePayload p) async {
    final r = await _c.put('/commission-plans/$id', data: p.toJson());
    return CommissionPlan.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deletePlan(String id) async => await _c.delete('/commission-plans/$id');

  // ── Rules ───────────────────────────────────────────────
  Future<List<CommissionRule>> listRules({String? planId}) async {
    final params = <String, dynamic>{};
    if (planId != null) params['commission_plan_id'] = planId;
    final r = await _c.get('/commission-rules', queryParameters: params);
    return (r.data['data'] as List).map((e) => CommissionRule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CommissionRule> createRule(CommissionRulePayload p) async {
    final r = await _c.post('/commission-rules', data: p.toJson());
    return CommissionRule.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CommissionRule> updateRule(String id, CommissionRuleUpdatePayload p) async {
    final r = await _c.put('/commission-rules/$id', data: p.toJson());
    return CommissionRule.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteRule(String id) async => await _c.delete('/commission-rules/$id');

  // ── Entries ─────────────────────────────────────────────
  Future<List<CommissionEntry>> listEntries({String? status, String? recipientMembershipId}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (recipientMembershipId != null) params['recipient_membership_id'] = recipientMembershipId;
    final r = await _c.get('/commission-entries', queryParameters: params);
    return (r.data['data'] as List).map((e) => CommissionEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CommissionCalculationResult> calculateForRecord(String recordId) async {
    final r = await _c.post('/pipeline-records/$recordId/calculate-commissions');
    return CommissionCalculationResult.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CommissionEntry> markApproved(String entryId) async {
    final r = await _c.post('/commission-entries/$entryId/mark-approved');
    return CommissionEntry.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CommissionEntry> markPaid(String entryId) async {
    final r = await _c.post('/commission-entries/$entryId/mark-paid');
    return CommissionEntry.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CommissionEntry> cancelEntry(String entryId) async {
    final r = await _c.post('/commission-entries/$entryId/cancel');
    return CommissionEntry.fromJson(r.data['data'] as Map<String, dynamic>);
  }
}
