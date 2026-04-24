// SmartBiz AI — AI Advisor state management.
import 'package:flutter/material.dart';
import 'models/advisor_models.dart';
import 'data/mock_advisor.dart';

class AdvisorState extends ChangeNotifier {
  final List<Recommendation> _recommendations = MockAdvisor.recommendations();

  // Filters
  RecImpact? _filterImpact;
  RecCategory? _filterCategory;
  RecStatus _filterStatus = RecStatus.active;

  // ── Getters ─────────────────────────────────────────────
  RecImpact? get filterImpact => _filterImpact;
  RecCategory? get filterCategory => _filterCategory;
  RecStatus get filterStatus => _filterStatus;

  List<Recommendation> get filtered {
    return _recommendations.where((r) {
      if (r.status != _filterStatus) return false;
      if (_filterImpact != null && r.impact != _filterImpact) return false;
      if (_filterCategory != null && r.category != _filterCategory) return false;
      return true;
    }).toList();
  }

  int get totalActive => _recommendations.where((r) => r.status == RecStatus.active).length;
  int get highImpactCount => _recommendations.where((r) => r.status == RecStatus.active && r.impact == RecImpact.high).length;

  // ── Filter actions ──────────────────────────────────────
  void setImpactFilter(RecImpact? impact) {
    _filterImpact = _filterImpact == impact ? null : impact;
    notifyListeners();
  }

  void setCategoryFilter(RecCategory? category) {
    _filterCategory = _filterCategory == category ? null : category;
    notifyListeners();
  }

  void setStatusFilter(RecStatus status) {
    _filterStatus = status;
    notifyListeners();
  }

  // ── Recommendation actions ──────────────────────────────
  void apply(String id) {
    final r = _recommendations.firstWhere((r) => r.id == id, orElse: () => _recommendations.first);
    r.status = RecStatus.applied;
    notifyListeners();
  }

  void dismiss(String id) {
    final r = _recommendations.firstWhere((r) => r.id == id, orElse: () => _recommendations.first);
    r.status = RecStatus.dismissed;
    notifyListeners();
  }

  void remindLater(String id) {
    final r = _recommendations.firstWhere((r) => r.id == id, orElse: () => _recommendations.first);
    r.status = RecStatus.later;
    notifyListeners();
  }

  void reactivate(String id) {
    final r = _recommendations.firstWhere((r) => r.id == id, orElse: () => _recommendations.first);
    r.status = RecStatus.active;
    notifyListeners();
  }
}
