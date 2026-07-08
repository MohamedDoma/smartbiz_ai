// SmartBiz AI — Document Checklist API models.

// ═══════════════════════════════════════════════════════
//  Document Checklist
// ═══════════════════════════════════════════════════════

class DocumentChecklist {
  final String id;
  final String workspaceId;
  final String? pipelineId;
  final Map<String, String>? pipeline;
  final String? stageId;
  final Map<String, String>? stage;
  final String? checklistKey;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final int? itemsCount;
  final List<DocumentChecklistItem>? items;

  const DocumentChecklist({
    required this.id,
    this.workspaceId = '',
    this.pipelineId,
    this.pipeline,
    this.stageId,
    this.stage,
    this.checklistKey,
    required this.name,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
    this.itemsCount,
    this.items,
  });

  factory DocumentChecklist.fromJson(Map<String, dynamic> j) => DocumentChecklist(
        id: j['id'] as String,
        workspaceId: j['workspace_id'] as String? ?? '',
        pipelineId: j['pipeline_id'] as String?,
        pipeline: j['pipeline'] != null ? Map<String, String>.from(j['pipeline'] as Map) : null,
        stageId: j['stage_id'] as String?,
        stage: j['stage'] != null ? Map<String, String>.from(j['stage'] as Map) : null,
        checklistKey: j['checklist_key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
        itemsCount: j['items_count'] as int?,
        items: (j['items'] as List?)?.map((e) => DocumentChecklistItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class DocumentChecklistPayload {
  final String name;
  final String? description;
  final String? pipelineId;
  final String? stageId;
  final int? sortOrder;

  const DocumentChecklistPayload({required this.name, this.description, this.pipelineId, this.stageId, this.sortOrder});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (pipelineId != null) 'pipeline_id': pipelineId,
        if (stageId != null) 'stage_id': stageId,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Document Checklist Item
// ═══════════════════════════════════════════════════════

class DocumentChecklistItem {
  final String id;
  final String documentChecklistId;
  final String? itemKey;
  final String title;
  final String? description;
  final bool isRequired;
  final List<String>? acceptedFileTypes;
  final int? maxFileSizeMb;
  final int sortOrder;
  final bool isActive;

  const DocumentChecklistItem({
    required this.id,
    this.documentChecklistId = '',
    this.itemKey,
    required this.title,
    this.description,
    this.isRequired = true,
    this.acceptedFileTypes,
    this.maxFileSizeMb,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory DocumentChecklistItem.fromJson(Map<String, dynamic> j) => DocumentChecklistItem(
        id: j['id'] as String,
        documentChecklistId: j['document_checklist_id'] as String? ?? '',
        itemKey: j['item_key'] as String?,
        title: j['title'] as String,
        description: j['description'] as String?,
        isRequired: j['is_required'] as bool? ?? true,
        acceptedFileTypes: (j['accepted_file_types'] as List?)?.map((e) => e.toString()).toList(),
        maxFileSizeMb: j['max_file_size_mb'] as int?,
        sortOrder: j['sort_order'] as int? ?? 0,
        isActive: j['is_active'] as bool? ?? true,
      );
}

class DocumentChecklistItemPayload {
  final String title;
  final String? description;
  final bool? isRequired;
  final List<String>? acceptedFileTypes;
  final int? maxFileSizeMb;
  final int? sortOrder;

  const DocumentChecklistItemPayload({
    required this.title,
    this.description,
    this.isRequired,
    this.acceptedFileTypes,
    this.maxFileSizeMb,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        if (isRequired != null) 'is_required': isRequired,
        if (acceptedFileTypes != null) 'accepted_file_types': acceptedFileTypes,
        if (maxFileSizeMb != null) 'max_file_size_mb': maxFileSizeMb,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Record Document
// ═══════════════════════════════════════════════════════

class RecordDocument {
  final String id;
  final String pipelineRecordId;
  final String? documentChecklistItemId;
  final Map<String, dynamic>? checklistItem;
  final String title;
  final String status;
  final String? originalFilename;
  final String? mimeType;
  final int? fileSize;
  final String? externalReference;
  final String? notes;
  final Map<String, dynamic>? uploadedBy;
  final String? uploadedAt;

  const RecordDocument({
    required this.id,
    required this.pipelineRecordId,
    this.documentChecklistItemId,
    this.checklistItem,
    required this.title,
    this.status = 'uploaded',
    this.originalFilename,
    this.mimeType,
    this.fileSize,
    this.externalReference,
    this.notes,
    this.uploadedBy,
    this.uploadedAt,
  });

  factory RecordDocument.fromJson(Map<String, dynamic> j) => RecordDocument(
        id: j['id'] as String,
        pipelineRecordId: j['pipeline_record_id'] as String,
        documentChecklistItemId: j['document_checklist_item_id'] as String?,
        checklistItem: j['checklist_item'] as Map<String, dynamic>?,
        title: j['title'] as String,
        status: j['status'] as String? ?? 'uploaded',
        originalFilename: j['original_filename'] as String?,
        mimeType: j['mime_type'] as String?,
        fileSize: j['file_size'] as int?,
        externalReference: j['external_reference'] as String?,
        notes: j['notes'] as String?,
        uploadedBy: j['uploaded_by'] as Map<String, dynamic>?,
        uploadedAt: j['uploaded_at'] as String?,
      );
}

class RecordDocumentPayload {
  final String? documentChecklistItemId;
  final String? title;
  final String? status;
  final String? externalReference;
  final String? notes;

  const RecordDocumentPayload({this.documentChecklistItemId, this.title, this.status, this.externalReference, this.notes});

  Map<String, dynamic> toJson() => {
        if (documentChecklistItemId != null) 'document_checklist_item_id': documentChecklistItemId,
        if (title != null) 'title': title,
        if (status != null) 'status': status,
        if (externalReference != null) 'external_reference': externalReference,
        if (notes != null) 'notes': notes,
      };
}

// ═══════════════════════════════════════════════════════
//  Document Status
// ═══════════════════════════════════════════════════════

class DocumentStatus {
  final String recordId;
  final String? recordTitle;
  final int requiredCount;
  final int completedCount;
  final int missingCount;
  final int optionalCount;
  final List<DocumentStatusItem> items;

  const DocumentStatus({
    required this.recordId,
    this.recordTitle,
    this.requiredCount = 0,
    this.completedCount = 0,
    this.missingCount = 0,
    this.optionalCount = 0,
    this.items = const [],
  });

  factory DocumentStatus.fromJson(Map<String, dynamic> j) => DocumentStatus(
        recordId: j['record_id'] as String,
        recordTitle: j['record_title'] as String?,
        requiredCount: j['required_count'] as int? ?? 0,
        completedCount: j['completed_count'] as int? ?? 0,
        missingCount: j['missing_count'] as int? ?? 0,
        optionalCount: j['optional_count'] as int? ?? 0,
        items: (j['items'] as List?)?.map((e) => DocumentStatusItem.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      );
}

class DocumentStatusItem {
  final String itemId;
  final String title;
  final String? description;
  final bool isRequired;
  final String? checklist;
  final String status;
  final RecordDocument? document;

  const DocumentStatusItem({
    required this.itemId,
    required this.title,
    this.description,
    this.isRequired = true,
    this.checklist,
    this.status = 'missing',
    this.document,
  });

  factory DocumentStatusItem.fromJson(Map<String, dynamic> j) => DocumentStatusItem(
        itemId: j['item_id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        isRequired: j['is_required'] as bool? ?? true,
        checklist: j['checklist'] as String?,
        status: j['status'] as String? ?? 'missing',
        document: j['document'] != null ? RecordDocument.fromJson(j['document'] as Map<String, dynamic>) : null,
      );
}
