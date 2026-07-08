// SmartBiz AI — Ownership state management.
import 'package:flutter/foundation.dart';
import '../../core/api/ownership_models.dart';
import '../../core/api/ownership_service.dart';

class OwnershipState extends ChangeNotifier {
  final OwnershipService _svc;
  OwnershipState(this._svc);

  List<OwnershipAssignment> _assignments = [];
  OwnershipResolveResult? _resolveResult;
  bool _loading = false;
  String? _error;

  List<OwnershipAssignment> get assignments => _assignments;
  OwnershipResolveResult? get resolveResult => _resolveResult;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadAssignments({String? entityType, String? ownerMembershipId}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _assignments = await _svc.listAssignments(entityType: entityType, ownerMembershipId: ownerMembershipId);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<OwnershipAssignment?> createAssignment(OwnershipAssignmentPayload p) async {
    try {
      final a = await _svc.createAssignment(p);
      _assignments = [..._assignments, a];
      notifyListeners();
      return a;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<OwnershipAssignment?> transferAssignment(String id, OwnershipTransferPayload p) async {
    try {
      final a = await _svc.transferAssignment(id, p);
      _assignments = _assignments.map((e) => e.id == id ? a : e).toList();
      notifyListeners();
      return a;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<OwnershipResolveResult?> resolveOwnership(String entityType, String entityId) async {
    try {
      _resolveResult = await _svc.resolveOwnership(entityType, entityId);
      notifyListeners();
      return _resolveResult;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }
}
