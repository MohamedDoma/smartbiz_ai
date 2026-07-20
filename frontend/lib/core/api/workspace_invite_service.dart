// SmartBiz AI — Workspace invitation API service.
//
// Authenticated operations: workspace-scoped (list/create/revoke).
// Public operations: preview + accept invite.

import 'api_client.dart';
import 'auth_models.dart';
import 'token_storage.dart';
import 'workspace_invite_models.dart';

class WorkspaceInviteService {
  final ApiClient _client;

  WorkspaceInviteService(this._client);

  // ── Workspace-scoped (authenticated) ────────────────────

  /// GET /api/workspace-roles
  Future<List<WorkspaceRoleSummary>> listWorkspaceRoles() async {
    final response = await _client.get('/workspace-roles');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceRoleSummary.fromJson)
        .toList();
  }

  /// GET /api/workspace-invitations
  Future<List<WorkspaceInvitation>> listInvites() async {
    final response = await _client.get('/workspace-invitations');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceInvitation.fromJson)
        .toList();
  }

  /// POST /api/workspace-invitations
  Future<WorkspaceInvitation> createInvite(
      CreateWorkspaceInvitationPayload payload) async {
    final response =
        await _client.post('/workspace-invitations', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return WorkspaceInvitation.fromJson(
        data['data'] as Map<String, dynamic>);
  }

  /// POST /api/workspace-invitations/{id}/resend
  Future<WorkspaceInvitation> resendInvite(String id, {int? expiresInDays}) async {
    final response = await _client.post(
      '/workspace-invitations/$id/resend',
      data: {if (expiresInDays != null) 'expires_in_days': expiresInDays},
    );
    final data = response.data as Map<String, dynamic>;
    return WorkspaceInvitation.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /api/workspace-invitations/{id}/revoke
  Future<WorkspaceInvitation> revokeInvite(String id) async {
    final response = await _client.post('/workspace-invitations/$id/revoke');
    final data = response.data as Map<String, dynamic>;
    return WorkspaceInvitation.fromJson(data['data'] as Map<String, dynamic>);
  }

  // ── Public endpoints (no auth required) ─────────────────

  /// GET /api/invites/{token}
  Future<InvitePreview> previewInvite(String token) async {
    final response = await _client.get('/invites/$token');
    final data = response.data as Map<String, dynamic>;
    return InvitePreview.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /api/invites/{token}/accept
  ///
  /// Returns full AuthSession (same shape as login/register).
  /// Stores token securely.
  Future<AuthSession> acceptInvite({
    required String token,
    required String fullName,
    required String phoneNumber,
    required String password,
    required String passwordConfirmation,
    String? preferredLocale,
  }) async {
    final payload = AcceptInvitePayload(
      fullName: fullName,
      phoneNumber: phoneNumber,
      password: password,
      passwordConfirmation: passwordConfirmation,
      preferredLocale: preferredLocale,
    );

    final response = await _client.post(
      '/invites/$token/accept',
      data: payload.toJson(),
    );

    final data = response.data as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);

    // Store the token securely.
    final authToken = session.token;
    if (authToken != null && authToken.isNotEmpty) {
      await TokenStorage.writeToken(authToken);
    }

    return session;
  }
}
