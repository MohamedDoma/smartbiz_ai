// SmartBiz AI — Document state management.
import 'package:flutter/foundation.dart';
import '../../core/api/document_models.dart';
import '../../core/api/document_service.dart';

class DocumentState extends ChangeNotifier {
  final DocumentService _svc;
  DocumentState(this._svc);

  List<DocumentChecklist> _checklists = [];
  List<DocumentChecklistItem> _items = [];
  DocumentStatus? _status;
  List<RecordDocument> _documents = [];
  bool _loading = false;
  String? _error;

  List<DocumentChecklist> get checklists => _checklists;
  List<DocumentChecklistItem> get items => _items;
  DocumentStatus? get documentStatus => _status;
  List<RecordDocument> get documents => _documents;
  bool get loading => _loading;
  String? get error => _error;

  // ── Checklists ──────────────────────────────────────────

  Future<void> loadChecklists({String? pipelineId, String? stageId}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _checklists = await _svc.listChecklists(pipelineId: pipelineId, stageId: stageId);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<DocumentChecklist?> createChecklist(DocumentChecklistPayload p) async {
    try {
      final cl = await _svc.createChecklist(p);
      _checklists = [..._checklists, cl];
      notifyListeners();
      return cl;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  // ── Checklist Items ─────────────────────────────────────

  Future<void> loadItems(String checklistId) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _items = await _svc.listChecklistItems(checklistId);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<DocumentChecklistItem?> createItem(String checklistId, DocumentChecklistItemPayload p) async {
    try {
      final item = await _svc.createChecklistItem(checklistId, p);
      _items = [..._items, item];
      notifyListeners();
      return item;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  // ── Record Documents ────────────────────────────────────

  Future<void> loadDocumentStatus(String recordId) async {
    _loading = true; _error = null; notifyListeners();
    try {
      _status = await _svc.getDocumentStatus(recordId);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false; notifyListeners();
  }

  Future<void> loadDocuments(String recordId) async {
    try {
      _documents = await _svc.listRecordDocuments(recordId);
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<RecordDocument?> provideDocument(String recordId, RecordDocumentPayload p) async {
    try {
      final doc = await _svc.provideRecordDocument(recordId, p);
      _documents = [doc, ..._documents];
      // Refresh status
      await loadDocumentStatus(recordId);
      return doc;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> deleteDocument(String id, String recordId) async {
    try {
      await _svc.deleteRecordDocument(id);
      _documents = _documents.where((d) => d.id != id).toList();
      await loadDocumentStatus(recordId);
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }
}
