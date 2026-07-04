// SmartBiz AI — AI Advisor state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/advisor_models.dart';
import 'data/mock_advisor.dart';

class AdvisorState extends ChangeNotifier {
  List<Recommendation>? _recommendations;

  // Filters
  RecImpact? _filterImpact;
  RecCategory? _filterCategory;
  RecStatus _filterStatus = RecStatus.active;

  List<Recommendation>? _filteredCache;

  List<Recommendation> get _data => _recommendations ??= MockAdvisor.recommendations();

  // ── Getters ─────────────────────────────────────────────
  RecImpact? get filterImpact => _filterImpact;
  RecCategory? get filterCategory => _filterCategory;
  RecStatus get filterStatus => _filterStatus;

  List<Recommendation> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _data.where((r) {
      if (r.status != _filterStatus) return false;
      if (_filterImpact != null && r.impact != _filterImpact) return false;
      if (_filterCategory != null && r.category != _filterCategory) return false;
      return true;
    }).toList();
    return _filteredCache!;
  }

  int get totalActive => _data.where((r) => r.status == RecStatus.active).length;
  int get highImpactCount => _data.where((r) => r.status == RecStatus.active && r.impact == RecImpact.high).length;

  // ── Filter actions ──────────────────────────────────────
  void _invalidate() { _filteredCache = null; notifyListeners(); }

  void setImpactFilter(RecImpact? impact) {
    _filterImpact = _filterImpact == impact ? null : impact;
    _invalidate();
  }

  void setCategoryFilter(RecCategory? category) {
    _filterCategory = _filterCategory == category ? null : category;
    _invalidate();
  }

  void setStatusFilter(RecStatus status) {
    _filterStatus = status;
    _invalidate();
  }

  // ── Recommendation actions ──────────────────────────────
  void apply(String id) {
    final r = _data.firstWhere((r) => r.id == id, orElse: () => _data.first);
    r.status = RecStatus.applied;
    _invalidate();
  }

  void dismiss(String id) {
    final r = _data.firstWhere((r) => r.id == id, orElse: () => _data.first);
    r.status = RecStatus.dismissed;
    _invalidate();
  }

  void remindLater(String id) {
    final r = _data.firstWhere((r) => r.id == id, orElse: () => _data.first);
    r.status = RecStatus.later;
    _invalidate();
  }

  void reactivate(String id) {
    final r = _data.firstWhere((r) => r.id == id, orElse: () => _data.first);
    r.status = RecStatus.active;
    _invalidate();
  }
}
