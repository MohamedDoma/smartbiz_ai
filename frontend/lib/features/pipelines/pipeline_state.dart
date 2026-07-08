// SmartBiz AI — Pipeline state management.
import 'package:flutter/foundation.dart';
import '../../core/api/pipeline_models.dart';
import '../../core/api/pipeline_service.dart';

class PipelineState extends ChangeNotifier {
  final PipelineService _svc;
  PipelineState(this._svc);

  List<Pipeline> _pipelines = [];
  Pipeline? _active;
  List<PipelineStage> _stages = [];
  List<CustomField> _customFields = [];
  List<PipelineRecord> _records = [];
  bool _loading = false;
  String? _error;

  List<Pipeline> get pipelines => _pipelines;
  Pipeline? get activePipeline => _active;
  List<PipelineStage> get stages => _stages;
  List<CustomField> get customFields => _customFields;
  List<PipelineRecord> get records => _records;
  bool get loading => _loading;
  String? get error => _error;

  // ── Load pipelines ──────────────────────────────────────

  Future<void> loadPipelines() async {
    _loading = true; _error = null; notifyListeners();
    try {
      _pipelines = await _svc.listPipelines();
      if (_active == null && _pipelines.isNotEmpty) {
        await selectPipeline(_pipelines.first);
      }
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<void> selectPipeline(Pipeline p) async {
    _active = p;
    notifyListeners();
    await Future.wait([_loadStages(p.id), _loadCustomFields(p.id), _loadRecords(p.id)]);
    notifyListeners();
  }

  Future<void> _loadStages(String pid) async {
    try { _stages = await _svc.listStages(pid); } catch (_) {}
  }

  Future<void> _loadCustomFields(String pid) async {
    try { _customFields = await _svc.listCustomFields(pipelineId: pid); } catch (_) {}
  }

  Future<void> _loadRecords(String pid) async {
    try { _records = await _svc.listRecords(pipelineId: pid); } catch (_) {}
  }

  // ── CRUD wrappers ───────────────────────────────────────

  Future<Pipeline?> createPipeline(PipelinePayload p) async {
    try {
      final pipeline = await _svc.createPipeline(p);
      _pipelines = [..._pipelines, pipeline];
      notifyListeners();
      return pipeline;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<PipelineStage?> createStage(PipelineStagePayload p) async {
    if (_active == null) return null;
    try {
      final stage = await _svc.createStage(_active!.id, p);
      _stages = [..._stages, stage];
      notifyListeners();
      return stage;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<CustomField?> createCustomField(CustomFieldPayload p) async {
    try {
      final field = await _svc.createCustomField(p);
      _customFields = [..._customFields, field];
      notifyListeners();
      return field;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<PipelineRecord?> createRecord(PipelineRecordPayload p) async {
    try {
      final record = await _svc.createRecord(p);
      _records = [record, ..._records];
      notifyListeners();
      return record;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<PipelineRecord?> moveRecord(String recordId, String stageId) async {
    try {
      final updated = await _svc.moveRecord(recordId, stageId);
      _records = _records.map((r) => r.id == recordId ? updated : r).toList();
      notifyListeners();
      return updated;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> refresh() async {
    if (_active != null) {
      await selectPipeline(_active!);
    }
  }

  List<PipelineRecord> recordsForStage(String stageId) =>
      _records.where((r) => r.stageId == stageId).toList();
}
