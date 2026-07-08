// SmartBiz AI — Report API models.

class ReportDataSourceSummary {
  final String key;
  final String displayName;
  final int columnCount;
  final int filterCount;

  const ReportDataSourceSummary({
    required this.key,
    required this.displayName,
    required this.columnCount,
    required this.filterCount,
  });

  factory ReportDataSourceSummary.fromJson(Map<String, dynamic> j) => ReportDataSourceSummary(
        key: j['key'] as String,
        displayName: j['display_name'] as String,
        columnCount: j['column_count'] as int? ?? 0,
        filterCount: j['filter_count'] as int? ?? 0,
      );
}

class ReportColumn {
  final String key;
  final String label;
  final String type;

  const ReportColumn({required this.key, required this.label, required this.type});

  factory ReportColumn.fromJson(Map<String, dynamic> j) => ReportColumn(
        key: j['key'] as String,
        label: j['label'] as String,
        type: j['type'] as String? ?? 'text',
      );
}

class ReportFilterDef {
  final String key;
  final String label;
  final String type;
  final List<String> operators;

  const ReportFilterDef({required this.key, required this.label, required this.type, this.operators = const []});

  factory ReportFilterDef.fromJson(Map<String, dynamic> j) => ReportFilterDef(
        key: j['key'] as String,
        label: j['label'] as String,
        type: j['type'] as String? ?? 'text',
        operators: (j['operators'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class ReportDataSource {
  final String key;
  final String displayName;
  final String table;
  final List<ReportColumn> columns;
  final List<ReportFilterDef> filters;

  const ReportDataSource({
    required this.key,
    required this.displayName,
    required this.table,
    required this.columns,
    required this.filters,
  });

  factory ReportDataSource.fromJson(Map<String, dynamic> j) => ReportDataSource(
        key: j['key'] as String,
        displayName: j['display_name'] as String,
        table: j['table'] as String? ?? '',
        columns: (j['columns'] as List).map((e) => ReportColumn.fromJson(e as Map<String, dynamic>)).toList(),
        filters: (j['filters'] as List).map((e) => ReportFilterDef.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class ReportTemplate {
  final String id;
  final String? templateKey;
  final String name;
  final String? description;
  final String dataSource;
  final List<String> columns;
  final List<Map<String, dynamic>>? filters;
  final List<Map<String, dynamic>>? groupBy;
  final List<Map<String, dynamic>>? sortBy;
  final String visibility;
  final bool isActive;
  final int sortOrder;
  final String? createdAt;

  const ReportTemplate({
    required this.id,
    this.templateKey,
    required this.name,
    this.description,
    required this.dataSource,
    required this.columns,
    this.filters,
    this.groupBy,
    this.sortBy,
    this.visibility = 'workspace',
    this.isActive = true,
    this.sortOrder = 0,
    this.createdAt,
  });

  factory ReportTemplate.fromJson(Map<String, dynamic> j) => ReportTemplate(
        id: j['id'] as String,
        templateKey: j['template_key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        dataSource: j['data_source'] as String,
        columns: (j['columns'] as List).map((e) => e.toString()).toList(),
        filters: (j['filters'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        groupBy: (j['group_by'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        sortBy: (j['sort_by'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        visibility: j['visibility'] as String? ?? 'workspace',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
        createdAt: j['created_at'] as String?,
      );
}

class ReportTemplatePayload {
  final String name;
  final String? description;
  final String dataSource;
  final List<String> columns;
  final List<Map<String, dynamic>>? filters;
  final List<Map<String, dynamic>>? sortBy;
  final String? visibility;

  const ReportTemplatePayload({
    required this.name,
    this.description,
    required this.dataSource,
    required this.columns,
    this.filters,
    this.sortBy,
    this.visibility,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'data_source': dataSource,
        'columns': columns,
        if (description != null) 'description': description,
        if (filters != null) 'filters': filters,
        if (sortBy != null) 'sort_by': sortBy,
        if (visibility != null) 'visibility': visibility,
      };
}

class ReportResultSummary {
  final int rowCount;
  final String? generatedAt;
  final Map<String, String>? totals;
  final Map<String, Map<String, int>>? statusCounts;

  const ReportResultSummary({this.rowCount = 0, this.generatedAt, this.totals, this.statusCounts});

  factory ReportResultSummary.fromJson(Map<String, dynamic> j) {
    Map<String, String>? totals;
    if (j['totals'] is Map) {
      totals = (j['totals'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    Map<String, Map<String, int>>? statusCounts;
    if (j['status_counts'] is Map) {
      statusCounts = (j['status_counts'] as Map).map((k, v) {
        final inner = (v as Map).map((k2, v2) => MapEntry(k2.toString(), (v2 as num).toInt()));
        return MapEntry(k.toString(), inner);
      });
    }
    return ReportResultSummary(
      rowCount: j['row_count'] as int? ?? 0,
      generatedAt: j['generated_at'] as String?,
      totals: totals,
      statusCounts: statusCounts,
    );
  }
}

class ReportResult {
  final String? runId;
  final String? templateId;
  final String dataSource;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final ReportResultSummary summary;

  const ReportResult({
    this.runId,
    this.templateId,
    required this.dataSource,
    required this.columns,
    required this.rows,
    required this.summary,
  });

  factory ReportResult.fromJson(Map<String, dynamic> j) => ReportResult(
        runId: j['run_id'] as String?,
        templateId: j['template_id'] as String?,
        dataSource: j['data_source'] as String,
        columns: (j['columns'] as List).map((e) => e.toString()).toList(),
        rows: (j['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        summary: ReportResultSummary.fromJson(j['summary'] as Map<String, dynamic>),
      );
}

class ReportRun {
  final String id;
  final String? reportTemplateId;
  final Map<String, dynamic>? template;
  final String dataSource;
  final String status;
  final int rowCount;
  final Map<String, dynamic>? resultSummary;
  final String? errorMessage;
  final String? startedAt;
  final String? finishedAt;

  const ReportRun({
    required this.id,
    this.reportTemplateId,
    this.template,
    required this.dataSource,
    this.status = 'completed',
    this.rowCount = 0,
    this.resultSummary,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
  });

  factory ReportRun.fromJson(Map<String, dynamic> j) => ReportRun(
        id: j['id'] as String,
        reportTemplateId: j['report_template_id'] as String?,
        template: j['template'] as Map<String, dynamic>?,
        dataSource: j['data_source'] as String,
        status: j['status'] as String? ?? 'completed',
        rowCount: j['row_count'] as int? ?? 0,
        resultSummary: j['result_summary'] as Map<String, dynamic>?,
        errorMessage: j['error_message'] as String?,
        startedAt: j['started_at'] as String?,
        finishedAt: j['finished_at'] as String?,
      );
}
