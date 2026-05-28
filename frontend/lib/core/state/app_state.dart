// SmartBiz AI — App-wide state.
//
// Manages: UI language, workspace doc language, current user/role/workspace.
// Separate from ShellState (which is navigation-only).
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Roles that affect navigation and dashboard behavior.
enum AppRole {
  owner(id: 'owner', labelKey: 'role_owner', navFilter: null),
  cashier(id: 'cashier', labelKey: 'role_cashier', navFilter: ['dashboard', 'ai_chat', 'invoices', 'customers', 'settings']),
  warehouse(id: 'warehouse', labelKey: 'role_warehouse', navFilter: ['dashboard', 'ai_chat', 'products', 'inventory', 'settings']),
  accountant(id: 'accountant', labelKey: 'role_accountant', navFilter: ['dashboard', 'ai_chat', 'accounting', 'reports', 'customers', 'settings']),
  employee(id: 'employee', labelKey: 'role_employee', navFilter: ['dashboard', 'ai_chat', 'settings']),
  superAdmin(id: 'super_admin', labelKey: 'role_super_admin', navFilter: null);

  final String id;
  final String labelKey;

  /// Nav item IDs this role can see. null = all items visible.
  final List<String>? navFilter;

  const AppRole({required this.id, required this.labelKey, required this.navFilter});

  /// Whether this role can see a given nav item.
  bool canSee(String navId) {
    if (navFilter == null) return true; // owner/superAdmin see all
    return navFilter!.contains(navId);
  }

  String label(AppLanguage lang) => trForLang(lang, labelKey);
}

/// Mock workspace data.
class WorkspaceInfo {
  final String id;
  final String name;
  final AppLanguage defaultLanguage;
  final AppLanguage documentLanguage;

  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.defaultLanguage,
    required this.documentLanguage,
  });

  WorkspaceInfo copyWith({
    AppLanguage? defaultLanguage,
    AppLanguage? documentLanguage,
  }) {
    return WorkspaceInfo(
      id: id,
      name: name,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      documentLanguage: documentLanguage ?? this.documentLanguage,
    );
  }
}

/// Mock user data.
class UserInfo {
  final String id;
  final String fullName;
  final String email;
  final AppLanguage uiLanguage;

  const UserInfo({
    required this.id,
    required this.fullName,
    required this.email,
    required this.uiLanguage,
  });

  UserInfo copyWith({AppLanguage? uiLanguage}) {
    return UserInfo(
      id: id,
      fullName: fullName,
      email: email,
      uiLanguage: uiLanguage ?? this.uiLanguage,
    );
  }
}

/// Central app state — ChangeNotifier for Provider.
class AppState extends ChangeNotifier {
  UserInfo _currentUser;
  AppRole _currentRole;
  WorkspaceInfo _currentWorkspace;
  bool _onboardingCompleted = false;

  AppState({
    UserInfo? user,
    AppRole? role,
    WorkspaceInfo? workspace,
  })  : _currentUser = user ?? _defaultUser,
        _currentRole = role ?? AppRole.owner,
        _currentWorkspace = workspace ?? _defaultWorkspace;

  // ── Getters ─────────────────────────────────────────────
  UserInfo get currentUser => _currentUser;
  AppRole get currentRole => _currentRole;
  WorkspaceInfo get currentWorkspace => _currentWorkspace;

  /// The UI language (per-user).
  AppLanguage get uiLanguage => _currentUser.uiLanguage;

  /// The workspace document language (per-workspace, for invoices etc.).
  AppLanguage get documentLanguage => _currentWorkspace.documentLanguage;

  /// Whether current layout is RTL.
  bool get isRtl => uiLanguage.isRtl;

  /// Text direction for the current UI language.
  TextDirection get textDirection => uiLanguage.textDirection;

  /// Locale for the current UI language.
  Locale get locale => uiLanguage.locale;

  /// Whether current role has super admin access.
  bool get isSuperAdmin => _currentRole == AppRole.superAdmin;

  /// Whether workspace onboarding is completed.
  bool get isOnboardingCompleted => _onboardingCompleted;

  // ── Setters ─────────────────────────────────────────────

  void setUiLanguage(AppLanguage lang) {
    _currentUser = _currentUser.copyWith(uiLanguage: lang);
    notifyListeners();
  }

  void setDocumentLanguage(AppLanguage lang) {
    _currentWorkspace = _currentWorkspace.copyWith(documentLanguage: lang);
    notifyListeners();
  }

  void setRole(AppRole role) {
    _currentRole = role;
    notifyListeners();
  }

  void setWorkspace(WorkspaceInfo workspace) {
    _currentWorkspace = workspace;
    notifyListeners();
  }

  void setUser(UserInfo user) {
    _currentUser = user;
    notifyListeners();
  }

  void completeOnboarding() {
    _onboardingCompleted = true;
    notifyListeners();
  }

  void resetOnboarding() {
    _onboardingCompleted = false;
    notifyListeners();
  }

  // ── Defaults (demo) ─────────────────────────────────────
  static const _defaultUser = UserInfo(
    id: 'demo-user-1',
    fullName: 'Mohamed Doma',
    email: 'demo@smartbiz.ai',
    uiLanguage: AppLanguage.en,
  );

  static const _defaultWorkspace = WorkspaceInfo(
    id: 'demo-ws-1',
    name: 'SmartBiz Demo',
    defaultLanguage: AppLanguage.en,
    documentLanguage: AppLanguage.en,
  );
}
