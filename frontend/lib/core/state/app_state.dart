// SmartBiz AI — App-wide state.
//
// Manages: UI language, workspace doc language, current user/role/workspace.
// Separate from ShellState (which is navigation-only).
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../api/auth_models.dart';
import '../api/auth_service.dart';
import '../api/business_template_service.dart';
import '../api/token_storage.dart';
import '../api/workspace_invite_service.dart';

/// Platform-level role (separate from workspace role).
/// Controls access to Super Admin portal.
enum PlatformRole { none, superAdmin }

/// Roles that affect navigation and dashboard behavior.
enum AppRole {
  owner(id: 'owner', labelKey: 'role_owner', navFilter: null),
  cashier(id: 'cashier', labelKey: 'role_cashier', navFilter: ['dashboard', 'ai_chat', 'invoices', 'payments', 'pos', 'customers', 'settings']),
  warehouse(id: 'warehouse', labelKey: 'role_warehouse', navFilter: ['dashboard', 'ai_chat', 'products', 'inventory', 'settings']),
  accountant(id: 'accountant', labelKey: 'role_accountant', navFilter: ['dashboard', 'ai_chat', 'accounting', 'reports', 'invoices', 'payments', 'customers', 'settings']),
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
  bool _authenticated = false;
  PlatformRole _platformRole = PlatformRole.none;

  /// API client — created once, shared across services.
  late final ApiClient apiClient;

  /// Auth service for login/logout/me.
  late final AuthService authService;

  /// Business template service for listing/applying templates.
  late final BusinessTemplateService templateService;

  /// Workspace invitation service for invite CRUD and acceptance.
  late final WorkspaceInviteService inviteService;

  /// Last loaded auth session (available after real login or session restore).
  AuthSession? _lastSession;

  AppState({
    UserInfo? user,
    AppRole? role,
    WorkspaceInfo? workspace,
  })  : _currentUser = user ?? _defaultUser,
        _currentRole = role ?? AppRole.owner,
        _currentWorkspace = workspace ?? _defaultWorkspace {
    apiClient = ApiClient(
      workspaceIdProvider: () => _authenticated ? _currentWorkspace.id : null,
      onAuthError: _handleAuthError,
    );
    authService = AuthService(apiClient);
    templateService = BusinessTemplateService(apiClient);
    inviteService = WorkspaceInviteService(apiClient);
  }

  /// Called by ApiClient interceptor on 401 responses.
  /// Clears local session so router redirects to /login.
  void _handleAuthError() {
    if (!_authenticated) return; // already signed out
    TokenStorage.clearToken();
    _clearSession();
  }

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

  /// Whether current platform role is super admin.
  bool get isSuperAdmin => _platformRole == PlatformRole.superAdmin;

  /// Whether the user has an active session.
  bool get isAuthenticated => _authenticated;

  /// Platform-level role (super admin vs regular user).
  PlatformRole get platformRole => _platformRole;

  /// Whether workspace onboarding is completed.
  bool get isOnboardingCompleted => _onboardingCompleted;

  /// Last loaded auth session from backend.
  AuthSession? get lastSession => _lastSession;

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

  // ═══════════════════════════════════════════════════════════
  //  Real Auth Methods (backend-integrated)
  // ═══════════════════════════════════════════════════════════

  /// Login with email + password via backend API.
  ///
  /// Throws [AuthException], [ValidationException], or [NetworkException].
  Future<void> signInWithEmailPassword(String email, String password) async {
    final session = await authService.login(email: email, password: password);
    _applySession(session);
  }

  /// Restore session from stored token (called from splash screen).
  ///
  /// Returns true if session was restored, false if no token or expired.
  /// On any error (network, server, 401), clears state and returns false.
  Future<bool> loadCurrentSession() async {
    try {
      final session = await authService.me();
      if (session == null) {
        _clearSession();
        return false;
      }
      _applySession(session);
      return true;
    } catch (_) {
      // Network error, server down, unexpected error — clear and fail safe.
      await TokenStorage.clearToken();
      _clearSession();
      return false;
    }
  }

  /// Logout via backend API + clear local state.
  Future<void> signOutReal() async {
    await authService.logout();
    _clearSession();
  }

  /// Register a new business owner via backend API.
  ///
  /// Creates user + workspace + membership on the server,
  /// then applies the session locally. User will be authenticated
  /// but onboarding_completed will be false, so router routes to /onboarding.
  ///
  /// Throws [ValidationException], [NetworkException], or [ApiException].
  Future<void> registerBusinessOwnerReal({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required String passwordConfirmation,
    required String workspaceName,
    String? businessType,
    String? businessSize,
  }) async {
    final locale = _currentUser.uiLanguage == AppLanguage.ar ? 'ar' : 'en';
    final session = await authService.registerBusinessOwner(
      fullName: fullName,
      email: email,
      phoneNumber: phoneNumber,
      password: password,
      passwordConfirmation: passwordConfirmation,
      workspaceName: workspaceName,
      businessType: businessType,
      businessSize: businessSize,
      preferredLocale: locale,
    );
    _applySession(session);
  }

  /// Apply a business template to the current workspace.
  ///
  /// Calls the apply endpoint, then refreshes the session via /auth/me
  /// so onboarding_completed becomes true and enabled_modules are populated.
  ///
  /// Throws [ApiException] on failure.
  Future<void> applyBusinessTemplate(String templateKey) async {
    await templateService.applyTemplate(templateKey);
    await loadCurrentSession();
  }

  /// Accept an employee invite via backend API.
  ///
  /// Creates user + membership + role on the server,
  /// then applies the session locally. Invited employees typically
  /// see onboarding_completed = true (inheriting the owner's setup).
  ///
  /// Throws [ValidationException], [ApiException], etc.
  Future<void> acceptEmployeeInviteReal({
    required String token,
    required String fullName,
    required String phoneNumber,
    required String password,
    required String passwordConfirmation,
  }) async {
    final locale = _currentUser.uiLanguage == AppLanguage.ar ? 'ar' : 'en';
    final session = await inviteService.acceptInvite(
      token: token,
      fullName: fullName,
      phoneNumber: phoneNumber,
      password: password,
      passwordConfirmation: passwordConfirmation,
      preferredLocale: locale,
    );
    _applySession(session);
  }

  /// Apply an AuthSession to AppState.
  void _applySession(AuthSession session) {
    _lastSession = session;
    _authenticated = true;

    // Platform role
    _platformRole = session.user.isSuperAdmin
        ? PlatformRole.superAdmin
        : PlatformRole.none;

    // User info
    final preferredLocale = session.user.preferredLocale;
    final uiLang = preferredLocale == 'en' ? AppLanguage.en : AppLanguage.ar;
    _currentUser = UserInfo(
      id: session.user.id,
      fullName: session.user.fullName,
      email: session.user.email,
      uiLanguage: uiLang,
    );

    // Workspace role mapping
    final aw = session.activeWorkspace;
    if (aw != null) {
      _currentWorkspace = WorkspaceInfo(
        id: aw.id,
        name: aw.name,
        defaultLanguage: AppLanguage.ar,
        documentLanguage: AppLanguage.ar,
      );
      _onboardingCompleted = aw.onboardingCompleted;
      _currentRole = _mapRoleKey(aw.roleKey);

      // Set workspace ID on ApiClient for workspace-scoped requests.
      apiClient.setWorkspaceId(aw.id);
    } else {
      // Super admin with no workspace — leave defaults.
      _onboardingCompleted = true;
    }

    // Super admin role override.
    if (_platformRole == PlatformRole.superAdmin) {
      _currentRole = AppRole.superAdmin;
    }

    notifyListeners();
  }

  /// Clear all session state (logout).
  void _clearSession() {
    _authenticated = false;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.owner;
    _currentUser = _defaultUser;
    _currentWorkspace = _defaultWorkspace;
    _onboardingCompleted = false;
    _lastSession = null;
    apiClient.setWorkspaceId(null);
    notifyListeners();
  }

  /// Map backend role_key to frontend AppRole.
  static AppRole _mapRoleKey(String? roleKey) {
    switch (roleKey) {
      case 'owner':
        return AppRole.owner;
      case 'admin':
        return AppRole.owner; // admin = full access like owner
      case 'cashier':
        return AppRole.cashier;
      case 'warehouse':
      case 'warehouse_manager':
        return AppRole.warehouse;
      case 'accountant':
      case 'finance':
        return AppRole.accountant;
      case 'super_admin':
        return AppRole.superAdmin;
      default:
        return AppRole.employee; // safe fallback for unknown roles
    }
  }

  // ── Mock sign-in / sign-out (kept for dev/demo) ─────────

  /// Mock sign in as business owner.
  void signInAsOwner() {
    _authenticated = true;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.owner;
    _currentUser = _defaultUser;
    _currentWorkspace = _defaultWorkspace;
    notifyListeners();
  }

  /// Mock sign in as employee.
  void signInAsEmployee() {
    _authenticated = true;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.employee;
    _onboardingCompleted = true; // employees skip business onboarding
    _currentUser = const UserInfo(
      id: 'demo-emp-1', fullName: 'Sara Ahmed',
      email: 'sara@smartbiz.ai', uiLanguage: AppLanguage.ar,
    );
    _currentWorkspace = _defaultWorkspace;
    notifyListeners();
  }

  /// Mock sign in as platform super admin.
  void signInAsSuperAdmin() {
    _authenticated = true;
    _platformRole = PlatformRole.superAdmin;
    _currentRole = AppRole.superAdmin;
    _currentUser = const UserInfo(
      id: 'admin-1', fullName: 'Platform Admin',
      email: 'admin@smartbiz.ai', uiLanguage: AppLanguage.ar,
    );
    notifyListeners();
  }

  /// Register a new business owner with workspace details.
  /// Mock-only — real backend will create tenant + user.
  void registerBusinessOwner({
    required String fullName,
    required String email,
    required String workspaceName,
    String businessSize = 'small',
    String businessType = 'general',
  }) {
    _authenticated = true;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.owner;
    _onboardingCompleted = false;
    _currentUser = UserInfo(
      id: 'owner-${DateTime.now().millisecondsSinceEpoch}',
      fullName: fullName,
      email: email,
      uiLanguage: _currentUser.uiLanguage,
    );
    _currentWorkspace = WorkspaceInfo(
      id: 'ws-${DateTime.now().millisecondsSinceEpoch}',
      name: workspaceName,
      defaultLanguage: AppLanguage.ar,
      documentLanguage: AppLanguage.ar,
    );
    notifyListeners();
  }

  /// Accept an employee invite — join existing workspace, skip onboarding.
  /// Mock-only — real backend will verify invite token.
  void acceptEmployeeInvite({
    required String fullName,
    required String email,
    required String workspaceName,
  }) {
    _authenticated = true;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.employee;
    _onboardingCompleted = true; // employees skip business onboarding
    _currentUser = UserInfo(
      id: 'emp-${DateTime.now().millisecondsSinceEpoch}',
      fullName: fullName,
      email: email,
      uiLanguage: _currentUser.uiLanguage,
    );
    _currentWorkspace = WorkspaceInfo(
      id: 'ws-invited-${DateTime.now().millisecondsSinceEpoch}',
      name: workspaceName,
      defaultLanguage: AppLanguage.ar,
      documentLanguage: AppLanguage.ar,
    );
    notifyListeners();
  }

  /// Clear session → unauthenticated.
  void signOut() {
    _clearSession();
  }

  // ── Defaults (demo) ─────────────────────────────────────
  static const _defaultUser = UserInfo(
    id: 'demo-user-1',
    fullName: 'Mohamed Doma',
    email: 'demo@smartbiz.ai',
    uiLanguage: AppLanguage.ar,
  );

  static const _defaultWorkspace = WorkspaceInfo(
    id: 'demo-ws-1',
    name: 'SmartBiz Demo',
    defaultLanguage: AppLanguage.ar,
    documentLanguage: AppLanguage.ar,
  );
}
