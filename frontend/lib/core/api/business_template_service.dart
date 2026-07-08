// SmartBiz AI — Business template API service.
//
// Provides list and apply operations against the business template endpoints.

import 'api_client.dart';
import 'business_template_models.dart';

class BusinessTemplateService {
  final ApiClient _client;

  BusinessTemplateService(this._client);

  /// GET /api/business-templates
  ///
  /// Returns all active templates with module counts.
  Future<List<BusinessTemplateSummary>> listTemplates() async {
    final response = await _client.get('/business-templates');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BusinessTemplateSummary.fromJson)
        .toList();
  }

  /// POST /api/business-templates/{templateKey}/apply
  ///
  /// Applies the template to the workspace identified by [workspaceId]
  /// (sent via X-Workspace-Id header by the ApiClient).
  Future<TemplateApplicationResult> applyTemplate(String templateKey) async {
    final response = await _client.post('/business-templates/$templateKey/apply');
    final data = response.data as Map<String, dynamic>;
    final appJson = data['application'] as Map<String, dynamic>? ?? {};
    return TemplateApplicationResult.fromJson(appJson);
  }
}
