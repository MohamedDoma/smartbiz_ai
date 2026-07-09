// SmartBiz AI — Platform Admin state management (Step 58).
import 'package:flutter/foundation.dart';
import '../../core/api/platform_models.dart';
import '../../core/api/platform_service.dart';

class PlatformState extends ChangeNotifier {
  final PlatformService _svc;
  PlatformState(this._svc);

  // ── Dashboard ─────────────────────────────────────────────
  PlatformDashboard? dashboard;
  bool dashboardLoading = false;
  String? dashboardError;

  Future<void> loadDashboard() async {
    dashboardLoading = true;
    dashboardError = null;
    notifyListeners();
    try {
      dashboard = await _svc.getDashboard();
    } catch (e) {
      dashboardError = e.toString();
    }
    dashboardLoading = false;
    notifyListeners();
  }

  // ── Workspaces ────────────────────────────────────────────
  List<PlatformWorkspaceSummary> workspaces = [];
  bool wsLoading = false;

  Future<void> loadWorkspaces() async {
    wsLoading = true;
    notifyListeners();
    try {
      workspaces = await _svc.listWorkspaces();
    } catch (_) {}
    wsLoading = false;
    notifyListeners();
  }

  Future<void> updateWorkspaceStatus(String id, String status) async {
    await _svc.updateWorkspaceStatus(id, status);
    await loadWorkspaces();
  }

  Future<void> updateWorkspaceSubscription(String id, Map<String, dynamic> payload) async {
    await _svc.updateWorkspaceSubscription(id, payload);
    await loadWorkspaces();
  }

  // ── Users ─────────────────────────────────────────────────
  List<PlatformUserSummary> users = [];
  bool usersLoading = false;

  Future<void> loadUsers() async {
    usersLoading = true;
    notifyListeners();
    try {
      users = await _svc.listUsers();
    } catch (_) {}
    usersLoading = false;
    notifyListeners();
  }

  Future<void> togglePlatformAdmin(String id, bool value) async {
    await _svc.updatePlatformAdmin(id, value);
    await loadUsers();
  }

  // ── Campaigns ─────────────────────────────────────────────
  List<PlatformActivationCampaign> campaigns = [];
  bool campaignsLoading = false;

  Future<void> loadCampaigns() async {
    campaignsLoading = true;
    notifyListeners();
    try {
      campaigns = await _svc.listCampaigns();
    } catch (_) {}
    campaignsLoading = false;
    notifyListeners();
  }

  Future<PlatformActivationCampaign> createCampaign(PlatformActivationCampaignPayload p) async {
    final c = await _svc.createCampaign(p);
    await loadCampaigns();
    return c;
  }

  Future<void> deleteCampaign(String id) async {
    await _svc.deleteCampaign(id);
    await loadCampaigns();
  }

  // ── Codes ─────────────────────────────────────────────────
  List<PlatformActivationCode> codes = [];
  bool codesLoading = false;

  Future<void> loadCodes({String? campaignId, String? status}) async {
    codesLoading = true;
    notifyListeners();
    try {
      codes = await _svc.listCodes(campaignId: campaignId, status: status);
    } catch (_) {}
    codesLoading = false;
    notifyListeners();
  }

  Future<List<PlatformActivationCode>> generateCodes(
      String campaignId, ActivationCodeGenerationPayload p) async {
    final generated = await _svc.generateCodes(campaignId, p);
    await loadCodes();
    return generated;
  }

  Future<void> updateCodeStatus(String id, String status) async {
    await _svc.updateCodeStatus(id, status);
    await loadCodes();
  }

  // ── Public validation ─────────────────────────────────────
  Future<ActivationCodeValidationResult> validateCode(String code) async {
    return await _svc.validateActivationCode(code);
  }

  // ── System Health ─────────────────────────────────────────
  Map<String, dynamic>? healthData;
  bool healthLoading = false;

  Future<void> loadHealth() async {
    healthLoading = true;
    notifyListeners();
    try {
      healthData = await _svc.getSystemHealth();
    } catch (_) {}
    healthLoading = false;
    notifyListeners();
  }
}
