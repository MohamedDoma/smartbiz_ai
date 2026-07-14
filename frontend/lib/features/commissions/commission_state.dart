// SmartBiz AI — Commission state management.
import 'package:flutter/foundation.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/commission_models.dart';
import '../../core/api/commission_service.dart';

class CommissionState extends ChangeNotifier {
  final CommissionService _svc;
  CommissionState(this._svc);

  List<CommissionPlan> _plans = [];
  List<CommissionRule> _rules = [];
  List<CommissionEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _isForbidden = false;

  List<CommissionPlan> get plans => _plans;
  List<CommissionRule> get rules => _rules;
  List<CommissionEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;

  /// True when the last error was a 403 Forbidden response.
  /// The UI can use this to show an "Access restricted" message
  /// rather than a generic error.
  bool get isForbidden => _isForbidden;

  /// Centralized error handler that detects 403 responses and sets
  /// a user-friendly l10n key instead of the raw exception message.
  void _handleError(Object e) {
    if (e is ApiException && e.statusCode == 403) {
      _isForbidden = true;
      _error = 'comm_no_permission'; // l10n key — UI calls tr(context, _error)
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

  /// Clears the last error.
  void clearError() {
    _error = null;
    _isForbidden = false;
    notifyListeners();
  }

  // ── Plans ───────────────────────────────────────────────

  Future<void> loadPlans() async {
    _loading = true; _error = null; _isForbidden = false; notifyListeners();
    try {
      _plans = await _svc.listPlans();
    } catch (e) { _handleError(e); }
    _loading = false; notifyListeners();
  }

  Future<CommissionPlan?> createPlan(CommissionPlanPayload p) async {
    try {
      final plan = await _svc.createPlan(p);
      _plans = [..._plans, plan];
      notifyListeners();
      return plan;
    } catch (e) { _handleError(e); notifyListeners(); return null; }
  }

  Future<CommissionPlan?> updatePlan(String id, CommissionPlanUpdatePayload p) async {
    try {
      final plan = await _svc.updatePlan(id, p);
      _plans = _plans.map((x) => x.id == id ? plan : x).toList();
      notifyListeners();
      return plan;
    } catch (e) { _handleError(e); notifyListeners(); return null; }
  }

  Future<bool> togglePlanActive(String id, {required bool isActive}) async {
    try {
      final plan = await _svc.updatePlan(id, CommissionPlanUpdatePayload(isActive: isActive));
      _plans = _plans.map((x) => x.id == id ? plan : x).toList();
      notifyListeners();
      return true;
    } catch (e) { _handleError(e); notifyListeners(); return false; }
  }

  Future<bool> deletePlan(String id) async {
    try {
      await _svc.deletePlan(id);
      // The backend deactivates on delete — reload to get fresh state.
      await loadPlans();
      return true;
    } catch (e) { _handleError(e); notifyListeners(); return false; }
  }

  // ── Rules ───────────────────────────────────────────────

  Future<void> loadRules({String? planId}) async {
    _loading = true; _error = null; _isForbidden = false; notifyListeners();
    try {
      _rules = await _svc.listRules(planId: planId);
    } catch (e) { _handleError(e); }
    _loading = false; notifyListeners();
  }

  Future<CommissionRule?> createRule(CommissionRulePayload p) async {
    try {
      final rule = await _svc.createRule(p);
      _rules = [..._rules, rule];
      notifyListeners();
      return rule;
    } catch (e) { _handleError(e); notifyListeners(); return null; }
  }

  Future<CommissionRule?> updateRule(String id, CommissionRuleUpdatePayload p) async {
    try {
      final rule = await _svc.updateRule(id, p);
      _rules = _rules.map((x) => x.id == id ? rule : x).toList();
      notifyListeners();
      return rule;
    } catch (e) { _handleError(e); notifyListeners(); return null; }
  }

  Future<bool> toggleRuleActive(String id, {required bool isActive}) async {
    try {
      final rule = await _svc.updateRule(id, CommissionRuleUpdatePayload(isActive: isActive));
      _rules = _rules.map((x) => x.id == id ? rule : x).toList();
      notifyListeners();
      return true;
    } catch (e) { _handleError(e); notifyListeners(); return false; }
  }

  Future<bool> deleteRule(String id) async {
    try {
      await _svc.deleteRule(id);
      // The backend deactivates on delete — reload rules for the current plan.
      final planId = _rules.firstWhere((r) => r.id == id, orElse: () => _rules.first).commissionPlanId;
      await loadRules(planId: planId);
      return true;
    } catch (e) { _handleError(e); notifyListeners(); return false; }
  }

  // ── Entries ─────────────────────────────────────────────

  Future<void> loadEntries({String? status}) async {
    _loading = true; _error = null; _isForbidden = false; notifyListeners();
    try {
      _entries = await _svc.listEntries(status: status);
    } catch (e) { _handleError(e); }
    _loading = false; notifyListeners();
  }

  Future<CommissionCalculationResult?> calculateForRecord(String recordId) async {
    try {
      final result = await _svc.calculateForRecord(recordId);
      // Refresh entries
      await loadEntries();
      return result;
    } catch (e) { _handleError(e); notifyListeners(); return null; }
  }

  Future<void> markApproved(String entryId) async {
    try {
      final updated = await _svc.markApproved(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _handleError(e); notifyListeners(); }
  }

  Future<void> markPaid(String entryId) async {
    try {
      final updated = await _svc.markPaid(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _handleError(e); notifyListeners(); }
  }

  Future<void> cancelEntry(String entryId) async {
    try {
      final updated = await _svc.cancelEntry(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _handleError(e); notifyListeners(); }
  }
}
