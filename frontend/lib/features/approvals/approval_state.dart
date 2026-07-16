// SmartBiz AI — Approval state management.
import 'package:flutter/foundation.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/approval_models.dart';
import '../../core/api/approval_service.dart';

class ApprovalState extends ChangeNotifier {
  final ApprovalService _svc;
  ApprovalState(this._svc);

  List<ApprovalRequest> _inbox = [];
  List<ApprovalRequest> _requests = [];
  List<ApprovalWorkflow> _workflows = [];
  ApprovalRequest? _selectedRequest;
  bool _loading = false;
  String? _error;
  bool _isForbidden = false;

  List<ApprovalRequest> get inbox => _inbox;
  List<ApprovalRequest> get requests => _requests;
  List<ApprovalWorkflow> get workflows => _workflows;
  ApprovalRequest? get selectedRequest => _selectedRequest;
  bool get loading => _loading;
  String? get error => _error;
  bool get isForbidden => _isForbidden;
  int get pendingCount => _inbox.length;

  void _handleError(Object e) {
    if (e is ApiException && e.statusCode == 403) {
      _isForbidden = true;
      _error = 'approval_no_permission';
    } else if (e is ValidationException) {
      _isForbidden = false;
      _error = e.firstMessage ?? e.message;
    } else if (e is ApiException) {
      _isForbidden = false;
      _error = e.message;
    } else {
      _isForbidden = false;
      _error = e.toString();
    }
  }

  void clearError() {
    _error = null;
    _isForbidden = false;
    notifyListeners();
  }

  // ── Inbox ──────────────────────────────────────────────

  Future<void> loadInbox() async {
    _loading = true;
    _error = null;
    _isForbidden = false;
    notifyListeners();
    try {
      _inbox = await _svc.inbox();
    } catch (e) {
      _handleError(e);
    }
    _loading = false;
    notifyListeners();
  }

  // ── Requests ───────────────────────────────────────────

  Future<void> loadRequests({
    String? scope,
    String? status,
    String? entityType,
  }) async {
    _loading = true;
    _error = null;
    _isForbidden = false;
    notifyListeners();
    try {
      _requests = await _svc.listRequests(
        scope: scope,
        status: status,
        entityType: entityType,
      );
    } catch (e) {
      _handleError(e);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadRequestDetail(String id) async {
    _loading = true;
    _error = null;
    _isForbidden = false;
    notifyListeners();
    try {
      _selectedRequest = await _svc.showRequest(id);
    } catch (e) {
      _handleError(e);
    }
    _loading = false;
    notifyListeners();
  }

  Future<ApprovalRequest?> submitRequest(ApprovalRequestPayload p) async {
    try {
      final req = await _svc.submitRequest(p);
      _requests = [req, ..._requests];
      notifyListeners();
      return req;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> approve(String id, {String? notes}) async {
    try {
      final updated = await _svc.decide(
        id,
        ApprovalDecisionPayload(decision: 'approved', notes: notes),
      );
      _updateInLists(updated);
      _selectedRequest = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> reject(String id, {String? notes}) async {
    try {
      final updated = await _svc.decide(
        id,
        ApprovalDecisionPayload(decision: 'rejected', notes: notes),
      );
      _updateInLists(updated);
      _selectedRequest = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelRequest(String id, {String? reason}) async {
    try {
      final updated = await _svc.cancel(id, reason: reason);
      _updateInLists(updated);
      _selectedRequest = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Workflows (admin) ──────────────────────────────────

  Future<void> loadWorkflows({String? entityType}) async {
    _loading = true;
    _error = null;
    _isForbidden = false;
    notifyListeners();
    try {
      _workflows = await _svc.listWorkflows(entityType: entityType);
    } catch (e) {
      _handleError(e);
    }
    _loading = false;
    notifyListeners();
  }

  Future<ApprovalWorkflow?> createWorkflow(ApprovalWorkflowPayload p) async {
    try {
      final wf = await _svc.createWorkflow(p);
      _workflows = [..._workflows, wf];
      notifyListeners();
      return wf;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return null;
    }
  }

  Future<ApprovalWorkflow?> updateWorkflow(
    String id,
    ApprovalWorkflowUpdatePayload p,
  ) async {
    try {
      final wf = await _svc.updateWorkflow(id, p);
      _workflows = _workflows.map((w) => w.id == id ? wf : w).toList();
      notifyListeners();
      return wf;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteWorkflow(String id) async {
    try {
      await _svc.deleteWorkflow(id);
      await loadWorkflows();
      return true;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Workflow Steps (admin) ───────────────────────────

  Future<ApprovalWorkflowStep?> addStep(
    String workflowId,
    ApprovalWorkflowStepPayload p,
  ) async {
    try {
      final step = await _svc.addStep(workflowId, p);
      await loadWorkflows(); // refresh to get updated steps list
      return step;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return null;
    }
  }

  Future<ApprovalWorkflowStep?> updateStep(
    String stepId,
    Map<String, dynamic> data,
  ) async {
    try {
      final step = await _svc.updateStep(stepId, data);
      await loadWorkflows();
      return step;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteStep(String stepId) async {
    try {
      await _svc.deleteStep(stepId);
      await loadWorkflows();
      return true;
    } catch (e) {
      _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────

  void _updateInLists(ApprovalRequest updated) {
    _inbox = _inbox.where((r) => r.id != updated.id).toList();
    _requests = _requests.map((r) => r.id == updated.id ? updated : r).toList();
  }

  /// Clear all cached data (call on logout / workspace switch).
  /// Prevents stale tenant data from leaking across sessions.
  void clearData() {
    _inbox = [];
    _requests = [];
    _workflows = [];
    _selectedRequest = null;
    _loading = false;
    _error = null;
    _isForbidden = false;
    notifyListeners();
  }
}
