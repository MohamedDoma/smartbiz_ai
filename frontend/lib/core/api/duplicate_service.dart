// SmartBiz AI — Duplicate detection API service.
import '../api/api_client.dart';
import '../api/duplicate_models.dart';

class DuplicateService {
  final ApiClient _c;
  DuplicateService(this._c);

  Future<List<DuplicateRule>> listRules({String? entityType}) async {
    final params = <String, dynamic>{};
    if (entityType != null) params['entity_type'] = entityType;
    final r = await _c.get('/duplicate-rules', queryParameters: params);
    return (r.data['data'] as List).map((e) => DuplicateRule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DuplicateRule> createRule(DuplicateRulePayload p) async {
    final r = await _c.post('/duplicate-rules', data: p.toJson());
    return DuplicateRule.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<DuplicateRule> updateRule(String id, DuplicateRulePayload p) async {
    final r = await _c.put('/duplicate-rules/$id', data: p.toJson());
    return DuplicateRule.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteRule(String id) async => await _c.delete('/duplicate-rules/$id');

  Future<DuplicateCheckResult> checkDuplicate(DuplicateCheckPayload p) async {
    final r = await _c.post('/duplicates/check', data: p.toJson());
    return DuplicateCheckResult.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<DuplicateMatch>> listMatches({String? status}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    final r = await _c.get('/duplicate-matches', queryParameters: params);
    return (r.data['data'] as List).map((e) => DuplicateMatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DuplicateMatch> resolveMatch(String id, {required String resolution}) async {
    final r = await _c.post('/duplicate-matches/$id/resolve', data: {'resolution': resolution});
    return DuplicateMatch.fromJson(r.data['data'] as Map<String, dynamic>);
  }
}
