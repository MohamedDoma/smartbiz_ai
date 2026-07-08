// SmartBiz AI — Workspace invitation API models.
//
// Maps backend invitation responses and payloads.
// Updated for multi-role support (Step 50.5).

/// Workspace role summary (from GET /api/workspace-roles).
class WorkspaceRoleSummary {
  final String id;
  final String roleKey;
  final String name;
  final String? description;
  final int hierarchyLevel;

  const WorkspaceRoleSummary({
    required this.id,
    required this.roleKey,
    required this.name,
    this.description,
    this.hierarchyLevel = 99,
  });

  factory WorkspaceRoleSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceRoleSummary(
        id: json['id'] as String? ?? '',
        roleKey: json['role_key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        hierarchyLevel: json['hierarchy_level'] as int? ?? 99,
      );
}

/// A role reference within an invitation.
class InviteRoleSummary {
  final String roleId;
  final String? roleKey;
  final String? name;
  final bool isPrimary;

  const InviteRoleSummary({required this.roleId, this.roleKey, this.name, this.isPrimary = false});

  factory InviteRoleSummary.fromJson(Map<String, dynamic> json) => InviteRoleSummary(
        roleId: json['role_id'] as String? ?? '',
        roleKey: json['role_key'] as String?,
        name: json['name'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

/// A workspace invitation (from list endpoint).
class WorkspaceInvitation {
  final String id;
  final String email;
  final String? fullName;
  final WorkspaceRoleSummary? role; // Legacy single role (backward compat)
  final List<InviteRoleSummary> roles; // Multi-role
  final InviteRoleSummary? primaryRole;
  final String status;
  final String? invitedByName;
  final String? expiresAt;
  final String? acceptedAt;
  final String? createdAt;

  /// Raw token — only populated when freshly created.
  final String? token;
  final String? invitePath;

  const WorkspaceInvitation({
    required this.id,
    required this.email,
    this.fullName,
    this.role,
    this.roles = const [],
    this.primaryRole,
    this.status = 'pending',
    this.invitedByName,
    this.expiresAt,
    this.acceptedAt,
    this.createdAt,
    this.token,
    this.invitePath,
  });

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) {
    final roleData = json['role'] as Map<String, dynamic>?;
    final invitedBy = json['invited_by'] as Map<String, dynamic>?;
    final rolesRaw = json['roles'] as List<dynamic>? ?? [];
    final primaryRaw = json['primary_role'] as Map<String, dynamic>?;

    return WorkspaceInvitation(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      role: roleData != null ? WorkspaceRoleSummary.fromJson(roleData) : null,
      roles: rolesRaw.whereType<Map<String, dynamic>>().map(InviteRoleSummary.fromJson).toList(),
      primaryRole: primaryRaw != null ? InviteRoleSummary.fromJson(primaryRaw) : null,
      status: json['status'] as String? ?? 'pending',
      invitedByName: invitedBy?['full_name'] as String?,
      expiresAt: json['expires_at'] as String?,
      acceptedAt: json['accepted_at'] as String?,
      createdAt: json['created_at'] as String?,
      token: json['token'] as String?,
      invitePath: json['invite_path'] as String?,
    );
  }

  /// Get role names for display.
  String get roleNamesDisplay {
    if (roles.isNotEmpty) {
      return roles.map((r) => r.name ?? r.roleKey ?? '').join(', ');
    }
    return role?.name ?? '';
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRevoked => status == 'revoked';
  bool get isExpired => status == 'expired';
}

/// Invite preview data (from GET /api/invites/{token}).
class InvitePreview {
  final String email;
  final String? fullName;
  final String? workspaceName;
  final String? roleName; // Legacy
  final String? roleKey;  // Legacy
  final List<InviteRoleSummary> roles;
  final InviteRoleSummary? primaryRole;
  final String? expiresAt;

  const InvitePreview({
    required this.email,
    this.fullName,
    this.workspaceName,
    this.roleName,
    this.roleKey,
    this.roles = const [],
    this.primaryRole,
    this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    final rolesRaw = json['roles'] as List<dynamic>? ?? [];
    final primaryRaw = json['primary_role'] as Map<String, dynamic>?;

    return InvitePreview(
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      workspaceName: json['workspace_name'] as String?,
      roleName: json['role_name'] as String?,
      roleKey: json['role_key'] as String?,
      roles: rolesRaw.whereType<Map<String, dynamic>>().map(InviteRoleSummary.fromJson).toList(),
      primaryRole: primaryRaw != null ? InviteRoleSummary.fromJson(primaryRaw) : null,
      expiresAt: json['expires_at'] as String?,
    );
  }

  /// Get display-friendly roles list.
  String get roleNamesDisplay {
    if (roles.isNotEmpty) {
      return roles.map((r) => r.name ?? r.roleKey ?? '').join(', ');
    }
    return roleName ?? '';
  }
}

/// Payload for creating a workspace invitation.
class CreateWorkspaceInvitationPayload {
  final String email;
  final String? fullName;
  /// Multi-role IDs.
  final List<String> roleIds;
  /// Optional primary role ID (defaults to first).
  final String? primaryRoleId;
  /// Legacy single role ID (fallback if roleIds is empty).
  final String? roleId;
  final int? expiresInDays;

  const CreateWorkspaceInvitationPayload({
    required this.email,
    this.fullName,
    this.roleIds = const [],
    this.primaryRoleId,
    this.roleId,
    this.expiresInDays,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'email': email,
      if (fullName != null && fullName!.isNotEmpty) 'full_name': fullName,
      if (expiresInDays != null) 'expires_in_days': expiresInDays,
    };
    if (roleIds.isNotEmpty) {
      map['role_ids'] = roleIds;
      if (primaryRoleId != null) map['primary_role_id'] = primaryRoleId;
    } else if (roleId != null) {
      // Legacy fallback
      map['role_id'] = roleId;
    }
    return map;
  }
}

/// Payload for accepting an invite.
class AcceptInvitePayload {
  final String fullName;
  final String phoneNumber;
  final String password;
  final String passwordConfirmation;
  final String? preferredLocale;

  const AcceptInvitePayload({
    required this.fullName,
    required this.phoneNumber,
    required this.password,
    required this.passwordConfirmation,
    this.preferredLocale,
  });

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'phone_number': phoneNumber,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (preferredLocale != null) 'preferred_locale': preferredLocale,
      };
}
