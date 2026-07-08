// SmartBiz AI — Report API service.
import '../api/api_client.dart';
import '../api/report_models.dart';

class ReportService {
  final ApiClient _c;
  ReportService(this._c);

  Future<List<ReportDataSourceSummary>> getCatalog() async {
    final r = await _c.get('/report-catalog');
    return (r.data['data'] as List).map((e) => ReportDataSourceSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ReportDataSource> getDataSource(String dataSource) async {
    final r = await _c.get('/report-catalog/$dataSource');
    return ReportDataSource.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<ReportTemplate>> listTemplates({String? dataSource}) async {
    final params = <String, dynamic>{};
    if (dataSource != null) params['data_source'] = dataSource;
    final r = await _c.get('/report-templates', queryParameters: params);
    return (r.data['data'] as List).map((e) => ReportTemplate.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ReportTemplate> createTemplate(ReportTemplatePayload p) async {
    final r = await _c.post('/report-templates', data: p.toJson());
    return ReportTemplate.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ReportTemplate> updateTemplate(String id, ReportTemplatePayload p) async {
    final r = await _c.put('/report-templates/$id', data: p.toJson());
    return ReportTemplate.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(String id) async => await _c.delete('/report-templates/$id');

  Future<ReportResult> runTemplate(String id, {int limit = 100}) async {
    final r = await _c.post('/report-templates/$id/run', data: {'parameters': {'limit': limit}});
    return ReportResult.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<ReportRun>> listRuns({String? dataSource}) async {
    final params = <String, dynamic>{};
    if (dataSource != null) params['data_source'] = dataSource;
    final r = await _c.get('/report-runs', queryParameters: params);
    return (r.data['data'] as List).map((e) => ReportRun.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ReportRun> getRun(String id) async {
    final r = await _c.get('/report-runs/$id');
    return ReportRun.fromJson(r.data['data'] as Map<String, dynamic>);
  }
}
