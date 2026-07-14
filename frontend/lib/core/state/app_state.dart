// SmartBiz AI — App-wide state.
//
// Manages: UI language, workspace doc language, current user/role/workspace.
// Separate from ShellState (which is navigation-only).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _sessionInitialized = false;
  PlatformRole _platformRole = PlatformRole.none;

  /// Real backend role name from the membership's primary_role.
  /// Used for display instead of the generic AppRole label.
  String? _backendRoleName;

  /// Real backend role key from the session (e.g. 'sales_manager').
  /// Used to look up localized role display names.
  String? _backendRoleKey;

  /// Current workspace membership ID for the authenticated user.
  String? _currentMembershipId;

  /// Locally persisted language preference.
  /// Non-null when the user has made an explicit manual choice.
  /// Takes absolute precedence over backend preferred_locale.
  AppLanguage? _savedLocaleChoice;

  /// SharedPreferences key for the persisted UI language.
  static const _localeStorageKey = 'smartbiz.ui_language';

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
    _loadSavedLocale();
  }

  /// Load saved UI language from local storage on startup.
  /// This runs asynchronously but applies before session restore completes.
  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_localeStorageKey);
      if (saved != null) {
        final lang = saved == 'en' ? AppLanguage.en : AppLanguage.ar;
        _savedLocaleChoice = lang;
        _currentUser = _currentUser.copyWith(uiLanguage: lang);
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — use default.
    }
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

  /// Whether the initial session restoration attempt has completed.
  /// Used by the router to avoid premature redirects on page reload.
  bool get isSessionInitialized => _sessionInitialized;

  /// Last loaded auth session from backend.
  AuthSession? get lastSession => _lastSession;

  /// The real backend role name for display.
  /// Null when using mock sessions without backend data.
  String? get backendRoleName => _backendRoleName;

  /// The real backend role key.
  /// Null when using mock sessions without backend data.
  String? get backendRoleKey => _backendRoleKey;

  /// Current workspace membership ID.
  String? get currentMembershipId => _currentMembershipId;

  /// Returns the best available localized role display name.
  ///
  /// Priority:
  /// 1. Localized label for the backend role_key (e.g. bk_role_sales_manager)
  /// 2. Backend role_name for custom/unknown roles
  /// 3. AppRole localized label (mock sessions only)
  /// 4. Generic employee label (final fallback)
  String displayRoleName(AppLanguage lang) {
    // 1. Try localized key for known backend role keys.
    if (_backendRoleKey != null && _backendRoleKey!.isNotEmpty) {
      final l10nKey = 'bk_role_${_backendRoleKey!}';
      final localized = trForLang(lang, l10nKey);
      // trForLang returns '[$key]' when the key is missing.
      if (!localized.startsWith('[')) {
        return localized;
      }
    }
    // 2. Fall back to backend role_name (custom roles).
    if (_backendRoleName != null && _backendRoleName!.isNotEmpty) {
      return _backendRoleName!;
    }
    // 3. AppRole label for mock/legacy sessions.
    return _currentRole.label(lang);
  }

  // ── Setters ─────────────────────────────────────────────

  void setUiLanguage(AppLanguage lang) {
    _savedLocaleChoice = lang;
    _currentUser = _currentUser.copyWith(uiLanguage: lang);
    notifyListeners();
    _persistLocale(lang);
  }

  /// Persist the manual language choice to local storage.
  Future<void> _persistLocale(AppLanguage lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeStorageKey, lang.locale.languageCode);
    } catch (_) {
      // Storage unavailable — in-memory choice still works.
    }
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
        _sessionInitialized = true;
        notifyListeners();
        return false;
      }
      _applySession(session);
      _sessionInitialized = true;
      notifyListeners();
      return true;
    } catch (_) {
      // Network error, server down, unexpected error — clear and fail safe.
      await TokenStorage.clearToken();
      _clearSession();
      _sessionInitialized = true;
      notifyListeners();
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

    // User info — preserve local language choice over backend preferred_locale.
    final AppLanguage uiLang;
    if (_savedLocaleChoice != null) {
      // User has made an explicit local language choice — keep it.
      uiLang = _savedLocaleChoice!;
    } else {
      // No local choice — use backend preferred_locale as initial fallback.
      final preferredLocale = session.user.preferredLocale;
      uiLang = preferredLocale == 'en' ? AppLanguage.en : AppLanguage.ar;
    }
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

      // Extract real role data from the membership's primary_role.
      final membership = session.memberships.firstWhere(
        (m) => m.workspaceId == aw.id,
        orElse: () => session.memberships.isNotEmpty
            ? session.memberships.first
            : const AuthMembership(id: '', workspaceId: ''),
      );
      _backendRoleName = membership.primaryRole?.roleName;
      _backendRoleKey = membership.primaryRole?.roleKey ?? aw.roleKey;
      _currentMembershipId = membership.id.isNotEmpty ? membership.id : null;

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
  /// Preserves the user's manually selected UI language.
  void _clearSession() {
    _authenticated = false;
    _platformRole = PlatformRole.none;
    _currentRole = AppRole.owner;
    // Preserve language choice across logout.
    final preservedLang = _savedLocaleChoice ?? _currentUser.uiLanguage;
    _currentUser = _defaultUser.copyWith(uiLanguage: preservedLang);
    _currentWorkspace = _defaultWorkspace;
    _onboardingCompleted = false;
    _lastSession = null;
    _backendRoleName = null;
    _backendRoleKey = null;
    _currentMembershipId = null;
    apiClient.setWorkspaceId(null);
    notifyListeners();
  }

  /// Map backend role_key to frontend AppRole.
  ///
  /// For real authenticated sessions, the dynamic blueprint navigation
  /// system uses backend permissions exclusively — AppRole.navFilter
  /// is only relevant in the legacy fallback path (mock sessions).
  /// Therefore, non-owner roles safely map to AppRole.employee as a
  /// neutral default; actual module visibility is controlled by
  /// backend permissions + enabled workspace modules.
  static AppRole _mapRoleKey(String? roleKey) {
    switch (roleKey) {
      case 'owner':
        return AppRole.owner;
      case 'admin':
        return AppRole.owner; // admin = full access like owner
      case 'general_manager':
        return AppRole.owner; // GM = broad access
      case 'inventory_manager':
        return AppRole.warehouse;
      case 'warehouse_staff':
      case 'warehouse':
      case 'warehouse_manager':
        return AppRole.warehouse;
      case 'cashier':
        return AppRole.cashier;
      case 'accountant':
      case 'finance':
        return AppRole.accountant;
      case 'super_admin':
        return AppRole.superAdmin;
      default:
        return AppRole.employee; // all other roles: dynamic nav handles filtering
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
