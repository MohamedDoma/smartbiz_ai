// SmartBiz AI — Report state management.
import 'package:flutter/foundation.dart';
import '../../core/api/report_models.dart';
import '../../core/api/report_service.dart';

class ReportState extends ChangeNotifier {
  final ReportService _svc;
  ReportState(this._svc);

  List<ReportDataSourceSummary> _catalog = [];
  ReportDataSource? _activeDataSource;
  List<ReportTemplate> _templates = [];
  List<ReportRun> _runs = [];
  ReportResult? _lastResult;
  bool _loading = false;
  String? _error;

  List<ReportDataSourceSummary> get catalog => _catalog;
  ReportDataSource? get activeDataSource => _activeDataSource;
  List<ReportTemplate> get templates => _templates;
  List<ReportRun> get runs => _runs;
  ReportResult? get lastResult => _lastResult;
  bool get loading => _loading;
  String? get error => _error;

  // ── Catalog ──────────────────────────────────────────

  Future<void> loadCatalog() async {
    _loading = true; _error = null; notifyListeners();
    try {
      _catalog = await _svc.getCatalog();
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<void> loadDataSource(String key) async {
    try {
      _activeDataSource = await _svc.getDataSource(key);
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  // ── Templates ────────────────────────────────────────

  Future<void> loadTemplates({String? dataSource}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _templates = await _svc.listTemplates(dataSource: dataSource);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<ReportTemplate?> createTemplate(ReportTemplatePayload p) async {
    try {
      final t = await _svc.createTemplate(p);
      _templates = [..._templates, t];
      notifyListeners();
      return t;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> deleteTemplate(String id) async {
    try {
      await _svc.deleteTemplate(id);
      _templates = _templates.where((t) => t.id != id).toList();
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  // ── Execution ────────────────────────────────────────

  Future<ReportResult?> runTemplate(String id, {int limit = 100}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _lastResult = await _svc.runTemplate(id, limit: limit);
      _loading = false; notifyListeners();
      return _lastResult;
    } catch (e) {
      _error = e.toString();
      _loading = false; notifyListeners();
      return null;
    }
  }

  // ── Runs ─────────────────────────────────────────────

  Future<void> loadRuns({String? dataSource}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _runs = await _svc.listRuns(dataSource: dataSource);
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }
}
