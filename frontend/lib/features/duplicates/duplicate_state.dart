// SmartBiz AI — Duplicate detection state management.
import 'package:flutter/foundation.dart';
import '../../core/api/duplicate_models.dart';
import '../../core/api/duplicate_service.dart';

class DuplicateState extends ChangeNotifier {
  final DuplicateService _svc;
  DuplicateState(this._svc);

  List<DuplicateRule> _rules = [];
  List<DuplicateMatch> _matches = [];
  DuplicateCheckResult? _checkResult;
  bool _loading = false;
  String? _error;

  List<DuplicateRule> get rules => _rules;
  List<DuplicateMatch> get matches => _matches;
  DuplicateCheckResult? get checkResult => _checkResult;
  bool get loading => _loading;
  String? get error => _error;

  // ── Rules ─────────────────────────────────────────────

  Future<void> loadRules({String? entityType}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _rules = await _svc.listRules(entityType: entityType);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<DuplicateRule?> createRule(DuplicateRulePayload p) async {
    try {
      final r = await _svc.createRule(p);
      _rules = [..._rules, r];
      notifyListeners();
      return r;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> deleteRule(String id) async {
    try {
      await _svc.deleteRule(id);
      _rules = _rules.where((r) => r.id != id).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  // ── Duplicate Check ──────────────────────────────────

  Future<DuplicateCheckResult?> checkDuplicate(DuplicateCheckPayload p) async {
    try {
      _checkResult = await _svc.checkDuplicate(p);
      notifyListeners();
      return _checkResult;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  // ── Matches ──────────────────────────────────────────

  Future<void> loadMatches({String? status}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _matches = await _svc.listMatches(status: status);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<void> resolveMatch(String id, {required String resolution}) async {
    try {
      final m = await _svc.resolveMatch(id, resolution: resolution);
      _matches = _matches.map((e) => e.id == id ? m : e).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }
}
