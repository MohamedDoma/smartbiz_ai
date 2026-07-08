// SmartBiz AI — Pipeline & Custom Field API service.
import '../api/api_client.dart';
import '../api/pipeline_models.dart';

class PipelineService {
  final ApiClient _c;
  PipelineService(this._c);

  // ── Pipelines ──────────────────────────────────────────
  Future<List<Pipeline>> listPipelines() async {
    final r = await _c.get('/pipelines');
    return (r.data['data'] as List).map((e) => Pipeline.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Pipeline> createPipeline(PipelinePayload p) async {
    final r = await _c.post('/pipelines', data: p.toJson());
    return Pipeline.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<Pipeline> updatePipeline(String id, PipelinePayload p) async {
    final r = await _c.put('/pipelines/$id', data: p.toJson());
    return Pipeline.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deletePipeline(String id) async => await _c.delete('/pipelines/$id');

  Future<Pipeline> showPipeline(String id) async {
    final r = await _c.get('/pipelines/$id');
    return Pipeline.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Stages ──────────────────────────────────────────────
  Future<List<PipelineStage>> listStages(String pipelineId) async {
    final r = await _c.get('/pipelines/$pipelineId/stages');
    return (r.data['data'] as List).map((e) => PipelineStage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PipelineStage> createStage(String pipelineId, PipelineStagePayload p) async {
    final r = await _c.post('/pipelines/$pipelineId/stages', data: p.toJson());
    return PipelineStage.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PipelineStage> updateStage(String id, PipelineStagePayload p) async {
    final r = await _c.put('/pipeline-stages/$id', data: p.toJson());
    return PipelineStage.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteStage(String id) async => await _c.delete('/pipeline-stages/$id');

  // ── Custom Fields ───────────────────────────────────────
  Future<List<CustomField>> listCustomFields({String? pipelineId}) async {
    final params = <String, dynamic>{};
    if (pipelineId != null) params['pipeline_id'] = pipelineId;
    final r = await _c.get('/custom-fields', queryParameters: params);
    return (r.data['data'] as List).map((e) => CustomField.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CustomField> createCustomField(CustomFieldPayload p) async {
    final r = await _c.post('/custom-fields', data: p.toJson());
    return CustomField.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<CustomField> updateCustomField(String id, CustomFieldPayload p) async {
    final r = await _c.put('/custom-fields/$id', data: p.toJson());
    return CustomField.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteCustomField(String id) async => await _c.delete('/custom-fields/$id');

  // ── Records ─────────────────────────────────────────────
  Future<List<PipelineRecord>> listRecords({String? pipelineId, String? stageId}) async {
    final params = <String, dynamic>{};
    if (pipelineId != null) params['pipeline_id'] = pipelineId;
    if (stageId != null) params['stage_id'] = stageId;
    final r = await _c.get('/pipeline-records', queryParameters: params);
    return (r.data['data'] as List).map((e) => PipelineRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PipelineRecord> createRecord(PipelineRecordPayload p) async {
    final r = await _c.post('/pipeline-records', data: p.toJson());
    return PipelineRecord.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PipelineRecord> updateRecord(String id, Map<String, dynamic> data) async {
    final r = await _c.put('/pipeline-records/$id', data: data);
    return PipelineRecord.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PipelineRecord> moveRecord(String id, String stageId) async {
    final r = await _c.post('/pipeline-records/$id/move', data: {'stage_id': stageId});
    return PipelineRecord.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PipelineRecord> getRecord(String id) async {
    final r = await _c.get('/pipeline-records/$id');
    return PipelineRecord.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteRecord(String id) async => await _c.delete('/pipeline-records/$id');
}
