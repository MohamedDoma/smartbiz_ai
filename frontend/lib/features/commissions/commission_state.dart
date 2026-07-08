// SmartBiz AI — Commission state management.
import 'package:flutter/foundation.dart';
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

  List<CommissionPlan> get plans => _plans;
  List<CommissionRule> get rules => _rules;
  List<CommissionEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;

  // ── Plans ───────────────────────────────────────────────

  Future<void> loadPlans() async {
    _loading = true; _error = null; notifyListeners();
    try {
      _plans = await _svc.listPlans();
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<CommissionPlan?> createPlan(CommissionPlanPayload p) async {
    try {
      final plan = await _svc.createPlan(p);
      _plans = [..._plans, plan];
      notifyListeners();
      return plan;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> deletePlan(String id) async {
    try {
      await _svc.deletePlan(id);
      _plans = _plans.where((p) => p.id != id).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  // ── Rules ───────────────────────────────────────────────

  Future<void> loadRules({String? planId}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _rules = await _svc.listRules(planId: planId);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<CommissionRule?> createRule(CommissionRulePayload p) async {
    try {
      final rule = await _svc.createRule(p);
      _rules = [..._rules, rule];
      notifyListeners();
      return rule;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> deleteRule(String id) async {
    try {
      await _svc.deleteRule(id);
      _rules = _rules.where((r) => r.id != id).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  // ── Entries ─────────────────────────────────────────────

  Future<void> loadEntries({String? status}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _entries = await _svc.listEntries(status: status);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<CommissionCalculationResult?> calculateForRecord(String recordId) async {
    try {
      final result = await _svc.calculateForRecord(recordId);
      // Refresh entries
      await loadEntries();
      return result;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> markApproved(String entryId) async {
    try {
      final updated = await _svc.markApproved(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> markPaid(String entryId) async {
    try {
      final updated = await _svc.markPaid(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> cancelEntry(String entryId) async {
    try {
      final updated = await _svc.cancelEntry(entryId);
      _entries = _entries.map((e) => e.id == entryId ? updated : e).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }
}
