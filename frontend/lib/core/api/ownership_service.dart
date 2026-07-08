// SmartBiz AI — Ownership API service.
import '../api/api_client.dart';
import '../api/ownership_models.dart';

class OwnershipService {
  final ApiClient _c;
  OwnershipService(this._c);

  Future<List<OwnershipAssignment>> listAssignments({String? entityType, String? ownerMembershipId}) async {
    final params = <String, dynamic>{};
    if (entityType != null) params['entity_type'] = entityType;
    if (ownerMembershipId != null) params['owner_membership_id'] = ownerMembershipId;
    final r = await _c.get('/ownership-assignments', queryParameters: params);
    return (r.data['data'] as List).map((e) => OwnershipAssignment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OwnershipAssignment> createAssignment(OwnershipAssignmentPayload p) async {
    final r = await _c.post('/ownership-assignments', data: p.toJson());
    return OwnershipAssignment.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<OwnershipAssignment> transferAssignment(String id, OwnershipTransferPayload p) async {
    final r = await _c.put('/ownership-assignments/$id/transfer', data: p.toJson());
    return OwnershipAssignment.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<OwnershipResolveResult> resolveOwnership(String entityType, String entityId) async {
    final r = await _c.get('/ownership/resolve', queryParameters: {'entity_type': entityType, 'entity_id': entityId});
    return OwnershipResolveResult.fromJson(r.data['data'] as Map<String, dynamic>);
  }
}
