// SmartBiz AI — Workspace invitation API models.

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

class InviteRoleSummary {
  final String roleId;
  final String? roleKey;
  final String? name;
  final bool isPrimary;

  const InviteRoleSummary({
    required this.roleId,
    this.roleKey,
    this.name,
    this.isPrimary = false,
  });

  factory InviteRoleSummary.fromJson(Map<String, dynamic> json) =>
      InviteRoleSummary(
        roleId: json['role_id'] as String? ?? json['id'] as String? ?? '',
        roleKey: json['role_key'] as String?,
        name: json['name'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

class InviteOrgRef {
  final String id;
  final String name;

  const InviteOrgRef({required this.id, required this.name});

  factory InviteOrgRef.fromJson(Map<String, dynamic> json) => InviteOrgRef(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class WorkspaceInvitation {
  final String id;
  final String email;
  final String? fullName;
  final WorkspaceRoleSummary? role;
  final List<InviteRoleSummary> roles;
  final InviteRoleSummary? primaryRole;
  final InviteOrgRef? department;
  final InviteOrgRef? team;
  final String? jobTitle;
  final String? preferredLocale;
  final String status;
  final String? invitedByName;
  final String? inviteUrl;
  final String? invitePath;
  final String? deliveryStatus;
  final String? deliveryError;
  final int sendCount;
  final String? lastSentAt;
  final String? expiresAt;
  final String? acceptedAt;
  final String? revokedAt;
  final String? createdAt;

  const WorkspaceInvitation({
    required this.id,
    required this.email,
    this.fullName,
    this.role,
    this.roles = const [],
    this.primaryRole,
    this.department,
    this.team,
    this.jobTitle,
    this.preferredLocale,
    this.status = 'pending',
    this.invitedByName,
    this.inviteUrl,
    this.invitePath,
    this.deliveryStatus,
    this.deliveryError,
    this.sendCount = 0,
    this.lastSentAt,
    this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
    this.createdAt,
  });

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) {
    final roleData = json['role'] as Map<String, dynamic>?;
    final invitedBy = json['invited_by'] as Map<String, dynamic>?;
    final rolesRaw = json['roles'] as List<dynamic>? ?? const [];
    final primaryRaw = json['primary_role'] as Map<String, dynamic>?;
    final departmentRaw = json['department'] as Map<String, dynamic>?;
    final teamRaw = json['team'] as Map<String, dynamic>?;

    return WorkspaceInvitation(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      role: roleData != null ? WorkspaceRoleSummary.fromJson(roleData) : null,
      roles: rolesRaw
          .whereType<Map<String, dynamic>>()
          .map(InviteRoleSummary.fromJson)
          .toList(),
      primaryRole: primaryRaw != null
          ? InviteRoleSummary.fromJson(primaryRaw)
          : null,
      department:
          departmentRaw != null ? InviteOrgRef.fromJson(departmentRaw) : null,
      team: teamRaw != null ? InviteOrgRef.fromJson(teamRaw) : null,
      jobTitle: json['job_title'] as String?,
      preferredLocale: json['preferred_locale'] as String?,
      status: json['status'] as String? ?? 'pending',
      invitedByName: invitedBy?['full_name'] as String?,
      inviteUrl: json['invite_url'] as String?,
      invitePath: json['invite_path'] as String?,
      deliveryStatus: json['delivery_status'] as String?,
      deliveryError: json['delivery_error'] as String?,
      sendCount: (json['send_count'] as num?)?.toInt() ?? 0,
      lastSentAt: json['last_sent_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      acceptedAt: json['accepted_at'] as String?,
      revokedAt: json['revoked_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  String get roleNamesDisplay {
    if (roles.isNotEmpty) {
      return roles.map((r) => r.name ?? r.roleKey ?? '').where((e) => e.isNotEmpty).join(', ');
    }
    return role?.name ?? '';
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRevoked => status == 'revoked';
  bool get isExpired => status == 'expired';
  bool get canResend => !isAccepted;
  bool get hasCopyableLink => inviteUrl != null && inviteUrl!.isNotEmpty;
}

class InvitePreview {
  final String email;
  final String? fullName;
  final String? workspaceName;
  final String? roleName;
  final String? roleKey;
  final List<InviteRoleSummary> roles;
  final InviteRoleSummary? primaryRole;
  final InviteOrgRef? department;
  final InviteOrgRef? team;
  final String? jobTitle;
  final String? expiresAt;

  const InvitePreview({
    required this.email,
    this.fullName,
    this.workspaceName,
    this.roleName,
    this.roleKey,
    this.roles = const [],
    this.primaryRole,
    this.department,
    this.team,
    this.jobTitle,
    this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) {
    final rolesRaw = json['roles'] as List<dynamic>? ?? const [];
    final primaryRaw = json['primary_role'] as Map<String, dynamic>?;
    final departmentRaw = json['department'] as Map<String, dynamic>?;
    final teamRaw = json['team'] as Map<String, dynamic>?;

    return InvitePreview(
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      workspaceName: json['workspace_name'] as String?,
      roleName: json['role_name'] as String?,
      roleKey: json['role_key'] as String?,
      roles: rolesRaw
          .whereType<Map<String, dynamic>>()
          .map(InviteRoleSummary.fromJson)
          .toList(),
      primaryRole: primaryRaw != null
          ? InviteRoleSummary.fromJson(primaryRaw)
          : null,
      department:
          departmentRaw != null ? InviteOrgRef.fromJson(departmentRaw) : null,
      team: teamRaw != null ? InviteOrgRef.fromJson(teamRaw) : null,
      jobTitle: json['job_title'] as String?,
      expiresAt: json['expires_at'] as String?,
    );
  }

  String get roleNamesDisplay => roles.isNotEmpty
      ? roles.map((r) => r.name ?? r.roleKey ?? '').join(', ')
      : roleName ?? '';

  String? get departmentName => department?.name;
  String? get teamName => team?.name;
}

class CreateWorkspaceInvitationPayload {
  final String email;
  final String? fullName;
  final List<String> roleIds;
  final String? primaryRoleId;
  final String? roleId;
  final String? departmentId;
  final String? teamId;
  final String? jobTitle;
  final String? preferredLocale;
  final int? expiresInDays;

  const CreateWorkspaceInvitationPayload({
    required this.email,
    this.fullName,
    this.roleIds = const [],
    this.primaryRoleId,
    this.roleId,
    this.departmentId,
    this.teamId,
    this.jobTitle,
    this.preferredLocale,
    this.expiresInDays,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'email': email,
      if (fullName != null && fullName!.trim().isNotEmpty)
        'full_name': fullName!.trim(),
      if (departmentId != null) 'department_id': departmentId,
      if (teamId != null) 'team_id': teamId,
      if (jobTitle != null && jobTitle!.trim().isNotEmpty)
        'job_title': jobTitle!.trim(),
      if (preferredLocale != null) 'preferred_locale': preferredLocale,
      if (expiresInDays != null) 'expires_in_days': expiresInDays,
    };
    if (roleIds.isNotEmpty) {
      map['role_ids'] = roleIds;
      if (primaryRoleId != null) map['primary_role_id'] = primaryRoleId;
    } else if (roleId != null) {
      map['role_id'] = roleId;
    }
    return map;
  }
}

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
