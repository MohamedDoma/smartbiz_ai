// SmartBiz AI — Document Checklist API service.
import '../api/api_client.dart';
import '../api/document_models.dart';

class DocumentService {
  final ApiClient _c;
  DocumentService(this._c);

  // ── Checklists ──────────────────────────────────────────
  Future<List<DocumentChecklist>> listChecklists({String? pipelineId, String? stageId}) async {
    final params = <String, dynamic>{};
    if (pipelineId != null) params['pipeline_id'] = pipelineId;
    if (stageId != null) params['stage_id'] = stageId;
    final r = await _c.get('/document-checklists', queryParameters: params);
    return (r.data['data'] as List).map((e) => DocumentChecklist.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DocumentChecklist> createChecklist(DocumentChecklistPayload p) async {
    final r = await _c.post('/document-checklists', data: p.toJson());
    return DocumentChecklist.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<DocumentChecklist> updateChecklist(String id, DocumentChecklistPayload p) async {
    final r = await _c.put('/document-checklists/$id', data: p.toJson());
    return DocumentChecklist.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<DocumentChecklist> showChecklist(String id) async {
    final r = await _c.get('/document-checklists/$id');
    return DocumentChecklist.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteChecklist(String id) async => await _c.delete('/document-checklists/$id');

  // ── Checklist Items ─────────────────────────────────────
  Future<List<DocumentChecklistItem>> listChecklistItems(String checklistId) async {
    final r = await _c.get('/document-checklists/$checklistId/items');
    return (r.data['data'] as List).map((e) => DocumentChecklistItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DocumentChecklistItem> createChecklistItem(String checklistId, DocumentChecklistItemPayload p) async {
    final r = await _c.post('/document-checklists/$checklistId/items', data: p.toJson());
    return DocumentChecklistItem.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<DocumentChecklistItem> updateChecklistItem(String id, DocumentChecklistItemPayload p) async {
    final r = await _c.put('/document-checklist-items/$id', data: p.toJson());
    return DocumentChecklistItem.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteChecklistItem(String id) async => await _c.delete('/document-checklist-items/$id');

  // ── Record Documents ────────────────────────────────────
  Future<List<RecordDocument>> listRecordDocuments(String recordId) async {
    final r = await _c.get('/pipeline-records/$recordId/documents');
    return (r.data['data'] as List).map((e) => RecordDocument.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RecordDocument> provideRecordDocument(String recordId, RecordDocumentPayload p) async {
    final r = await _c.post('/pipeline-records/$recordId/documents', data: p.toJson());
    return RecordDocument.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<DocumentStatus> getDocumentStatus(String recordId) async {
    final r = await _c.get('/pipeline-records/$recordId/document-status');
    return DocumentStatus.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteRecordDocument(String id) async => await _c.delete('/record-documents/$id');
}
