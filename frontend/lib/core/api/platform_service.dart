// SmartBiz AI — Platform Admin API service (Step 58).
import '../api/api_client.dart';
import '../api/platform_models.dart';

class PlatformService {
  final ApiClient _c;
  PlatformService(this._c);

  // ── Dashboard ─────────────────────────────────────────────
  Future<PlatformDashboard> getDashboard() async {
    final r = await _c.get('/platform/dashboard');
    return PlatformDashboard.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Workspaces ────────────────────────────────────────────
  Future<List<PlatformWorkspaceSummary>> listWorkspaces() async {
    final r = await _c.get('/platform/workspaces');
    return (r.data['data'] as List)
        .map((e) => PlatformWorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlatformWorkspaceSummary> getWorkspace(String id) async {
    final r = await _c.get('/platform/workspaces/$id');
    return PlatformWorkspaceSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PlatformWorkspaceSummary> updateWorkspaceStatus(String id, String status) async {
    final r = await _c.put('/platform/workspaces/$id/status', data: {'status': status});
    return PlatformWorkspaceSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PlatformWorkspaceSummary> updateWorkspaceSubscription(
      String id, Map<String, dynamic> payload) async {
    final r = await _c.put('/platform/workspaces/$id/subscription', data: payload);
    return PlatformWorkspaceSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Users ─────────────────────────────────────────────────
  Future<List<PlatformUserSummary>> listUsers() async {
    final r = await _c.get('/platform/users');
    return (r.data['data'] as List)
        .map((e) => PlatformUserSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlatformUserSummary> getUser(String id) async {
    final r = await _c.get('/platform/users/$id');
    return PlatformUserSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PlatformUserSummary> updatePlatformAdmin(String id, bool isPlatformAdmin) async {
    final r = await _c.put('/platform/users/$id/platform-admin',
        data: {'is_super_admin': isPlatformAdmin});
    return PlatformUserSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Campaigns ─────────────────────────────────────────────
  Future<List<PlatformActivationCampaign>> listCampaigns() async {
    final r = await _c.get('/platform/activation-campaigns');
    return (r.data['data'] as List)
        .map((e) => PlatformActivationCampaign.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlatformActivationCampaign> createCampaign(PlatformActivationCampaignPayload p) async {
    final r = await _c.post('/platform/activation-campaigns', data: p.toJson());
    return PlatformActivationCampaign.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<PlatformActivationCampaign> updateCampaign(
      String id, PlatformActivationCampaignPayload p) async {
    final r = await _c.put('/platform/activation-campaigns/$id', data: p.toJson());
    return PlatformActivationCampaign.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteCampaign(String id) async {
    await _c.delete('/platform/activation-campaigns/$id');
  }

  // ── Codes ─────────────────────────────────────────────────
  Future<List<PlatformActivationCode>> listCodes({String? campaignId, String? status}) async {
    final params = <String, dynamic>{};
    if (campaignId != null) params['campaign_id'] = campaignId;
    if (status != null) params['status'] = status;
    final r = await _c.get('/platform/activation-codes', queryParameters: params);
    return (r.data['data'] as List)
        .map((e) => PlatformActivationCode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PlatformActivationCode>> generateCodes(
      String campaignId, ActivationCodeGenerationPayload p) async {
    final r = await _c.post('/platform/activation-campaigns/$campaignId/codes/generate',
        data: p.toJson());
    return (r.data['data']['codes'] as List)
        .map((e) => PlatformActivationCode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PlatformActivationCode> updateCodeStatus(String id, String status) async {
    final r = await _c.put('/platform/activation-codes/$id/status', data: {'status': status});
    return PlatformActivationCode.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  // ── Public (no auth) ──────────────────────────────────────
  Future<ActivationCodeValidationResult> validateActivationCode(String code) async {
    final r = await _c.get('/activation-codes/$code');
    return ActivationCodeValidationResult.fromJson(r.data as Map<String, dynamic>);
  }
  // ── System Health ──────────────────────────────────────────
  Future<Map<String, dynamic>> getSystemHealth() async {
    final r = await _c.get('/platform/system-health');
    return r.data['data'] as Map<String, dynamic>;
  }
}
