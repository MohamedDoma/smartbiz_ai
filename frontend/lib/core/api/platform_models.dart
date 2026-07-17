// Step 58 — Platform Admin / Activation Code models.

class PlatformDashboard {
  final PlatformWorkspaceStats workspaces;
  final PlatformUserStats users;
  final PlatformCampaignStats campaigns;
  final PlatformCodeStats codes;
  final List<PlatformWorkspaceSummary> recentWorkspaces;
  final List<PlatformActivationCode> recentCodeUsage;
  final List<PlatformActivationCampaign> topCampaigns;

  PlatformDashboard({
    required this.workspaces,
    required this.users,
    required this.campaigns,
    required this.codes,
    required this.recentWorkspaces,
    required this.recentCodeUsage,
    required this.topCampaigns,
  });

  factory PlatformDashboard.fromJson(Map<String, dynamic> j) {
    return PlatformDashboard(
      workspaces: PlatformWorkspaceStats.fromJson(j['workspaces'] ?? {}),
      users: PlatformUserStats.fromJson(j['users'] ?? {}),
      campaigns: PlatformCampaignStats.fromJson(j['campaigns'] ?? {}),
      codes: PlatformCodeStats.fromJson(j['codes'] ?? {}),
      recentWorkspaces: (j['recent_workspaces'] as List? ?? [])
          .map((e) => PlatformWorkspaceSummary.fromJson(e))
          .toList(),
      recentCodeUsage: (j['recent_code_usage'] as List? ?? [])
          .map((e) => PlatformActivationCode.fromJson(e))
          .toList(),
      topCampaigns: (j['top_campaigns'] as List? ?? [])
          .map((e) => PlatformActivationCampaign.fromJson(e))
          .toList(),
    );
  }
}

class PlatformWorkspaceStats {
  final int total;
  final int active;
  final int trial;
  final int suspended;

  PlatformWorkspaceStats({this.total = 0, this.active = 0, this.trial = 0, this.suspended = 0});

  factory PlatformWorkspaceStats.fromJson(Map<String, dynamic> j) => PlatformWorkspaceStats(
        total: j['total'] ?? 0,
        active: j['active'] ?? 0,
        trial: j['trial'] ?? 0,
        suspended: j['suspended'] ?? 0,
      );
}

class PlatformUserStats {
  final int total;
  final int platformAdmins;

  PlatformUserStats({this.total = 0, this.platformAdmins = 0});

  factory PlatformUserStats.fromJson(Map<String, dynamic> j) => PlatformUserStats(
        total: j['total'] ?? 0,
        platformAdmins: j['platform_admins'] ?? 0,
      );
}

class PlatformCampaignStats {
  final int total;
  final int active;

  PlatformCampaignStats({this.total = 0, this.active = 0});

  factory PlatformCampaignStats.fromJson(Map<String, dynamic> j) => PlatformCampaignStats(
        total: j['total'] ?? 0,
        active: j['active'] ?? 0,
      );
}

class PlatformCodeStats {
  final int total;
  final int unused;
  final int used;
  final int expired;
  final int disabled;

  PlatformCodeStats({this.total = 0, this.unused = 0, this.used = 0, this.expired = 0, this.disabled = 0});

  factory PlatformCodeStats.fromJson(Map<String, dynamic> j) => PlatformCodeStats(
        total: j['total'] ?? 0,
        unused: j['unused'] ?? 0,
        used: j['used'] ?? 0,
        expired: j['expired'] ?? 0,
        disabled: j['disabled'] ?? 0,
      );
}

class PlatformWorkspaceSummary {
  final String id;
  final String name;
  final String? industryType;
  final String? businessSize;
  final String? status;
  final String? subscriptionStatus;
  final bool isActive;
  final int? membersCount;
  final String? defaultLocale;
  final String? createdAt;

  PlatformWorkspaceSummary({
    required this.id,
    required this.name,
    this.industryType,
    this.businessSize,
    this.status,
    this.subscriptionStatus,
    this.isActive = true,
    this.membersCount,
    this.defaultLocale,
    this.createdAt,
  });

  factory PlatformWorkspaceSummary.fromJson(Map<String, dynamic> j) => PlatformWorkspaceSummary(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        industryType: j['industry_type'],
        businessSize: j['business_size'],
        status: j['status'],
        subscriptionStatus: j['subscription_status'],
        isActive: j['is_active'] ?? true,
        membersCount: j['members_count'],
        defaultLocale: j['default_locale'],
        createdAt: j['created_at'],
      );
}

class PlatformUserSummary {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final bool isActive;
  final bool isSuperAdmin;
  final String? preferredLocale;
  final String? createdAt;

  PlatformUserSummary({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.isActive = true,
    this.isSuperAdmin = false,
    this.preferredLocale,
    this.createdAt,
  });

  factory PlatformUserSummary.fromJson(Map<String, dynamic> j) => PlatformUserSummary(
        id: j['id'] ?? '',
        fullName: j['full_name'] ?? '',
        email: j['email'] ?? '',
        phoneNumber: j['phone_number'],
        isActive: j['is_active'] ?? true,
        isSuperAdmin: j['is_super_admin'] ?? false,
        preferredLocale: j['preferred_locale'],
        createdAt: j['created_at'],
      );
}

class PlatformActivationCampaign {
  final String id;
  final String? campaignKey;
  final String name;
  final String? description;
  final String? targetMarket;
  final String? defaultPlanKey;
  final int? trialDays;
  final String? startsAt;
  final String? expiresAt;
  final String status;
  final int totalCodes;
  final int usedCodes;
  final String? createdAt;

  PlatformActivationCampaign({
    required this.id,
    this.campaignKey,
    required this.name,
    this.description,
    this.targetMarket,
    this.defaultPlanKey,
    this.trialDays,
    this.startsAt,
    this.expiresAt,
    this.status = 'active',
    this.totalCodes = 0,
    this.usedCodes = 0,
    this.createdAt,
  });

  factory PlatformActivationCampaign.fromJson(Map<String, dynamic> j) => PlatformActivationCampaign(
        id: j['id'] ?? '',
        campaignKey: j['campaign_key'],
        name: j['name'] ?? '',
        description: j['description'],
        targetMarket: j['target_market'],
        defaultPlanKey: j['default_plan_key'],
        trialDays: j['trial_days'],
        startsAt: j['starts_at'],
        expiresAt: j['expires_at'],
        status: j['status'] ?? 'active',
        totalCodes: j['total_codes'] ?? 0,
        usedCodes: j['used_codes'] ?? 0,
        createdAt: j['created_at'],
      );
}

class PlatformActivationCampaignPayload {
  final String name;
  final String? description;
  final String? targetMarket;
  final String? defaultPlanKey;
  final int? trialDays;
  final String? expiresAt;
  final String? status;

  PlatformActivationCampaignPayload({
    required this.name,
    this.description,
    this.targetMarket,
    this.defaultPlanKey,
    this.trialDays,
    this.expiresAt,
    this.status,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name};
    if (description != null) m['description'] = description;
    if (targetMarket != null) m['target_market'] = targetMarket;
    if (defaultPlanKey != null) m['default_plan_key'] = defaultPlanKey;
    if (trialDays != null) m['trial_days'] = trialDays;
    if (expiresAt != null) m['expires_at'] = expiresAt;
    if (status != null) m['status'] = status;
    return m;
  }
}

class PlatformActivationCode {
  final String id;
  final String? campaignId;
  final String? campaignName;
  final String code;
  final String? registrationUrl;
  final String? defaultPlanKey;
  final int? trialDays;
  final int maxUses;
  final int usedCount;
  final String status;
  final String? assignedToName;
  final String? assignedToPhone;
  final String? usedByUserId;
  final String? usedWorkspaceId;
  final String? usedAt;
  final String? expiresAt;
  final String? createdAt;

  PlatformActivationCode({
    required this.id,
    this.campaignId,
    this.campaignName,
    required this.code,
    this.registrationUrl,
    this.defaultPlanKey,
    this.trialDays,
    this.maxUses = 1,
    this.usedCount = 0,
    this.status = 'unused',
    this.assignedToName,
    this.assignedToPhone,
    this.usedByUserId,
    this.usedWorkspaceId,
    this.usedAt,
    this.expiresAt,
    this.createdAt,
  });

  factory PlatformActivationCode.fromJson(Map<String, dynamic> j) => PlatformActivationCode(
        id: j['id'] ?? '',
        campaignId: j['campaign_id'],
        campaignName: j['campaign_name'] ?? (j['campaign'] is Map ? j['campaign']['name'] : null),
        code: j['code'] ?? '',
        registrationUrl: j['registration_url'],
        defaultPlanKey: j['default_plan_key'],
        trialDays: j['trial_days'],
        maxUses: j['max_uses'] ?? 1,
        usedCount: j['used_count'] ?? 0,
        status: j['status'] ?? 'unused',
        assignedToName: j['assigned_to_name'],
        assignedToPhone: j['assigned_to_phone'],
        usedByUserId: j['used_by_user_id'],
        usedWorkspaceId: j['used_workspace_id'],
        usedAt: j['used_at'],
        expiresAt: j['expires_at'],
        createdAt: j['created_at'],
      );
}

class ActivationCodeGenerationPayload {
  final int count;
  final String? assignedToName;
  final String? assignedToPhone;
  final String? expiresAt;

  ActivationCodeGenerationPayload({
    required this.count,
    this.assignedToName,
    this.assignedToPhone,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'count': count};
    if (assignedToName != null) m['assigned_to_name'] = assignedToName;
    if (assignedToPhone != null) m['assigned_to_phone'] = assignedToPhone;
    if (expiresAt != null) m['expires_at'] = expiresAt;
    return m;
  }
}

class ActivationCodeValidationResult {
  final bool valid;
  final String? reason;
  final String? planKey;
  final int? trialDays;
  final String? campaign;
  final String? expiresAt;

  ActivationCodeValidationResult({
    required this.valid,
    this.reason,
    this.planKey,
    this.trialDays,
    this.campaign,
    this.expiresAt,
  });

  factory ActivationCodeValidationResult.fromJson(Map<String, dynamic> j) =>
      ActivationCodeValidationResult(
        valid: j['valid'] ?? false,
        reason: j['reason'],
        planKey: j['plan_key'],
        trialDays: j['trial_days'],
        campaign: j['campaign'],
        expiresAt: j['expires_at'],
      );
}
