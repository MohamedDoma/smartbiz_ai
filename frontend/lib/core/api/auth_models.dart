// SmartBiz AI — Auth session models.
//
// Dart models that map to the backend /auth/login and /auth/me responses.
// All fromJson constructors handle missing/null values safely.

/// A user's role within a workspace membership.
class AuthRole {
  final String roleId;
  final String? roleName;
  final String? roleKey;
  final bool isPrimary;

  const AuthRole({
    required this.roleId,
    this.roleName,
    this.roleKey,
    this.isPrimary = false,
  });

  factory AuthRole.fromJson(Map<String, dynamic> json) => AuthRole(
        roleId: json['role_id'] as String? ?? '',
        roleName: json['role_name'] as String?,
        roleKey: json['role_key'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

/// A workspace membership entry from the session payload.
class AuthMembership {
  final String id;
  final String workspaceId;
  final String? workspaceName;
  final String status;
  final String? departmentId;
  final String? branchId;
  final String? joinedAt;
  final AuthRole? primaryRole;
  final List<AuthRole> roles;
  final bool onboardingCompleted;
  final List<String> enabledModules;
  final List<String> permissions;

  const AuthMembership({
    required this.id,
    required this.workspaceId,
    this.workspaceName,
    this.status = 'active',
    this.departmentId,
    this.branchId,
    this.joinedAt,
    this.primaryRole,
    this.roles = const [],
    this.onboardingCompleted = false,
    this.enabledModules = const [],
    this.permissions = const [],
  });

  factory AuthMembership.fromJson(Map<String, dynamic> json) {
    final ws = json['workspace'] as Map<String, dynamic>?;
    final primaryRoleJson = json['primary_role'] as Map<String, dynamic>?;
    final rolesJson = json['roles'] as List<dynamic>? ?? [];

    return AuthMembership(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      workspaceName: ws?['name'] as String?,
      status: json['status'] as String? ?? 'active',
      departmentId: json['department_id'] as String?,
      branchId: json['branch_id'] as String?,
      joinedAt: json['joined_at'] as String?,
      primaryRole:
          primaryRoleJson != null ? AuthRole.fromJson(primaryRoleJson) : null,
      roles: rolesJson
          .whereType<Map<String, dynamic>>()
          .map(AuthRole.fromJson)
          .toList(),
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      enabledModules: (json['enabled_modules'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// The active workspace summary from the session payload.
class AuthWorkspace {
  final String id;
  final String name;
  final String? roleKey;
  final List<String> roleKeys;
  final bool onboardingCompleted;
  final List<String> enabledModules;
  final List<String> permissions;

  const AuthWorkspace({
    required this.id,
    required this.name,
    this.roleKey,
    this.roleKeys = const [],
    this.onboardingCompleted = false,
    this.enabledModules = const [],
    this.permissions = const [],
  });

  factory AuthWorkspace.fromJson(Map<String, dynamic> json) {
    final roleKey = json['role_key'] as String?;
    final rawRoleKeys = json['role_keys'] as List<dynamic>?;
    // Fallback: if backend doesn't return role_keys, derive from roleKey
    final roleKeys = rawRoleKeys?.map((e) => e.toString()).toList()
        ?? (roleKey != null ? [roleKey] : <String>[]);

    return AuthWorkspace(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      roleKey: roleKey,
      roleKeys: roleKeys,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      enabledModules: (json['enabled_modules'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// The authenticated user from the session payload.
class AuthUser {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final bool isActive;
  final String? preferredLocale;
  final String platformRole; // "super_admin" | "none"
  final String? createdAt;

  const AuthUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.isActive = true,
    this.preferredLocale,
    this.platformRole = 'none',
    this.createdAt,
  });

  bool get isSuperAdmin => platformRole == 'super_admin';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phoneNumber: json['phone_number'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        preferredLocale: json['preferred_locale'] as String?,
        platformRole: json['platform_role'] as String? ?? 'none',
        createdAt: json['created_at'] as String?,
      );
}

/// Full session payload from /auth/login or /auth/me.
class AuthSession {
  final String? token;
  final AuthUser user;
  final AuthWorkspace? activeWorkspace;
  final List<AuthMembership> memberships;

  const AuthSession({
    this.token,
    required this.user,
    this.activeWorkspace,
    this.memberships = const [],
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] as Map<String, dynamic>? ?? {};
    final awJson = json['active_workspace'] as Map<String, dynamic>?;
    final membershipsJson = json['memberships'] as List<dynamic>? ?? [];

    return AuthSession(
      token: json['token'] as String?,
      user: AuthUser.fromJson(userJson),
      activeWorkspace:
          awJson != null ? AuthWorkspace.fromJson(awJson) : null,
      memberships: membershipsJson
          .whereType<Map<String, dynamic>>()
          .map(AuthMembership.fromJson)
          .toList(),
    );
  }
}
