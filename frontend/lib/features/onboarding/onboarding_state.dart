// SmartBiz AI — Onboarding state management.
//
// Orchestrates the full onboarding lifecycle:
//   Welcome → Adaptive AI Discovery → Real Blueprint → Provisioning → Complete
//
// Discovery uses the real backend adaptive API — no mock questions,
// no fixed question count, no scripted chips.
import 'package:flutter/material.dart';
import '../../core/api/discovery_models.dart';
import '../../core/api/discovery_service.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/api/provisioning_models.dart';
import '../../core/api/provisioning_service.dart';
import '../../core/state/app_state.dart';
import 'data/provisioning_repository.dart';
import 'models/onboarding_models.dart';

/// Phases of the onboarding flow.
enum OnboardingPhase { welcome, discovery, blueprint, provisioning, complete }

/// Sub-phases of the provisioning pipeline for granular UI feedback.
enum ProvisioningStep {
  idle,
  previewing,
  applying,
  applyingOperational,
  finalizing,
  refreshingSession,
}

/// Central state for the onboarding / discovery flow.
///
/// Discovery is driven by the real backend adaptive AI:
///   - Question count is dynamic (not fixed)
///   - AI asks only for missing information
///   - One detailed message may immediately produce a Blueprint
///   - Short answers cause additional adaptive questions
///   - The conversation is persisted server-side for resume
class OnboardingState extends ChangeNotifier {
  OnboardingPhase _phase = OnboardingPhase.welcome;
  final List<DiscoveryMessage> _messages = [];
  bool _isAiThinking = false;
  bool _isProvisioning = false;
  bool _provisioningDone = false;
  String? _provisioningError;

  /// Current sub-step within the provisioning phase.
  ProvisioningStep _provisioningStep = ProvisioningStep.idle;

  /// Run ID from the last successful apply, used for finalize.
  String? _activeRunId;

  /// Guard flag to prevent duplicate provisioning requests.
  bool _provisioningInFlight = false;

  /// Guard flag to prevent duplicate discovery sends.
  bool _discoveryInFlight = false;

  /// Discovery session from the backend.
  DiscoverySession? _discoverySession;

  /// Real generated Blueprint from the backend.
  DiscoveryBlueprintDto? _realBlueprint;

  /// Completeness percentage from the backend (0-100).
  double _completeness = 0;

  /// Whether the backend reports readiness for Blueprint generation.
  bool _readyForBlueprint = false;

  /// Discovery error message (retryable — conversation is preserved).
  String? _discoveryError;

  /// Injected discovery service. Set via [setDiscoveryService].
  DiscoveryService? _discoveryService;

  /// Whether a backend resume has been attempted (success or failure).
  /// Used to prevent the welcome greeting from appearing before resume.
  bool _resumeAttempted = false;

  /// Injected provisioning repository. Set via [setProvisioningRepository].
  ProvisioningRepository? _injectedRepo;

  /// Cached reference to AppState for language resolution in the blueprint bridge.
  AppState? _currentAppState;

  // ── Getters ─────────────────────────────────────────────
  OnboardingPhase get phase => _phase;

  /// Internal message types that are backend workflow events,
  /// not conversational assistant messages.
  static const _technicalMessageTypes = {
    'classification',
    'blueprint',
    'blueprint_generated',
    'classified',
  };

  /// User-facing messages — filters out internal backend workflow events.
  List<DiscoveryMessage> get messages => List.unmodifiable(
      _messages.where((m) => !_technicalMessageTypes.contains(m.messageType)));
  bool get isAiThinking => _isAiThinking;
  bool get isProvisioning => _isProvisioning;
  bool get provisioningDone => _provisioningDone;
  String? get provisioningError => _provisioningError;
  ProvisioningStep get provisioningStep => _provisioningStep;
  String? get activeRunId => _activeRunId;
  double get completeness => _completeness;
  bool get readyForBlueprint => _readyForBlueprint;
  String? get discoveryError => _discoveryError;
  DiscoverySession? get discoverySession => _discoverySession;
  bool get resumeAttempted => _resumeAttempted;
  DiscoveryBlueprintDto? get realBlueprint => _realBlueprint;

  /// Converts the real backend Blueprint to the UI BlueprintModel.
  ///
  /// Reads the canonical blueprint JSON structure and maps it to the
  /// BlueprintModel that the blueprint_screen.dart UI expects.
  BlueprintModel? get blueprint {
    if (_realBlueprint == null) return null;
    return _convertToBlueprintModel(_realBlueprint!);
  }

  /// Test-only access to the blueprint converter for regression testing.
  @visibleForTesting
  BlueprintModel testConvertBlueprint(DiscoveryBlueprintDto dto) =>
      _convertToBlueprintModel(dto);

  BlueprintModel _convertToBlueprintModel(DiscoveryBlueprintDto dto) {
    final bp = dto.blueprint;

    // Resolve the current UI language for localization
    final lang = _currentAppState?.uiLanguage ?? AppLanguage.ar;

    // Extract modules from canonical format.
    // Backend returns modules as a List of {key, enabled, reason, status}.
    final requiredMods = <BlueprintModule>[];
    final optionalMods = <BlueprintModule>[];

    final rawModules = bp['modules'];
    if (rawModules is List) {
      for (final item in rawModules) {
        if (item is! Map) continue;
        final mod = Map<String, dynamic>.from(item);
        final key = mod['key'] as String? ?? 'unknown';
        final enabled = mod['enabled'] as bool? ?? true;
        final module = BlueprintModule(
          id: key,
          displayName: _localizeModuleName(key, lang),
          displayDescription: _localizeModuleDesc(key, lang),
          icon: _moduleIconKey(key),
          included: enabled,
        );
        if (enabled) {
          requiredMods.add(module);
        } else {
          optionalMods.add(module);
        }
      }
    } else if (rawModules is Map) {
      // Legacy format: {module_id: {enabled: true, ...}}
      final modules = Map<String, dynamic>.from(rawModules);
      modules.forEach((id, config) {
        final mod = config is Map ? Map<String, dynamic>.from(config) : <String, dynamic>{};
        final enabled = mod['enabled'] as bool? ?? true;
        final module = BlueprintModule(
          id: id,
          displayName: _localizeModuleName(id, lang),
          displayDescription: _localizeModuleDesc(id, lang),
          icon: _moduleIconKey(id),
          included: enabled,
        );
        if (enabled) {
          requiredMods.add(module);
        } else {
          optionalMods.add(module);
        }
      });
    }

    // Extract roles — always a List of {key, name, description, permissions, ...}
    // Use the real backend name and description. These are scenario-specific
    // and must not be replaced with generic localization keys.
    final rawRoles = bp['roles'];
    final suggestedRoles = <BlueprintRole>[];
    if (rawRoles is List) {
      for (final r in rawRoles) {
        if (r is! Map) continue;
        final role = Map<String, dynamic>.from(r);
        final key = role['key'] as String? ?? role['name'] as String? ?? 'unknown';
        final name = role['name'] as String? ?? _humanizeKey(key);
        final desc = role['description'] as String? ?? '';
        suggestedRoles.add(BlueprintRole(
          id: key,
          displayName: name,
          displayDescription: desc,
          accessModules: (role['permissions'] as List<dynamic>?)
                  ?.map((p) => p.toString())
                  .toList() ??
              [],
        ));
      }
    }

    // Extract business name from business_profile sub-object
    final profile = bp['business_profile'] is Map
        ? Map<String, dynamic>.from(bp['business_profile'] as Map)
        : <String, dynamic>{};

    // Localize business type
    final rawBizType = dto.businessType ?? profile['business_type'] as String? ?? 'service';

    return BlueprintModel(
      businessName: profile['business_name'] as String? ??
          bp['company_name'] as String? ??
          _discoverySession?.businessDescription?.split('.').first ??
          'Your Business',
      businessType: _localizeBusinessType(rawBizType, lang),
      businessDescription:
          profile['business_description'] as String? ??
          _discoverySession?.businessDescription ?? '',
      requiredModules: requiredMods,
      optionalModules: optionalMods,
      suggestedRoles: suggestedRoles,
      suggestedWorkflows: _extractLocalizedNamedList(bp, 'pipelines', lang),
      suggestedDashboards: _extractLocalizedNamedList(bp, 'departments', lang),
      suggestedAutomations: _extractLocalizedNamedList(bp, 'approval_workflows', lang),
      notes: _extractStringList(bp, 'assumptions'),
    );
  }

  List<String> _extractStringList(Map<String, dynamic> bp, String key) {
    final raw = bp[key];
    if (raw is! List) return [];
    return raw.map((e) {
      if (e is String) return e;
      if (e is Map) return (e['name'] ?? e['key'] ?? e).toString();
      return e.toString();
    }).toList();
  }

  /// Extract names from a list-of-objects field, localizing known canonical values.
  List<String> _extractLocalizedNamedList(
      Map<String, dynamic> bp, String key, AppLanguage lang) {
    final raw = bp[key];
    if (raw is! List) return [];
    return raw.map((e) {
      if (e is String) return _localizeCanonicalName(e, lang);
      if (e is Map) {
        final name = (e['name'] ?? e['key'] ?? e).toString();
        return _localizeCanonicalName(name, lang);
      }
      return e.toString();
    }).toList();
  }

  String _moduleIconKey(String moduleId) {
    const iconMap = {
      'sales': 'point_of_sale',
      'products': 'inventory_2',
      'inventory': 'warehouse',
      'customers': 'people',
      'accounting': 'account_balance',
      'finance': 'account_balance',
      'reports': 'bar_chart',
      'employees': 'badge',
      'invoices': 'receipt_long',
      'quotations': 'request_quote',
      'purchases': 'shopping_cart',
      'pos': 'point_of_sale',
      'orders': 'receipt_long',
      'dashboard': 'dashboard',
      'commissions': 'payments',
      'ai': 'smart_toy',
      'leads': 'people',
      'payments': 'payments',
    };
    return iconMap[moduleId] ?? 'extension';
  }

  // ═══════════════════════════════════════════════════════════
  //  Localization maps for Blueprint display values
  // ═══════════════════════════════════════════════════════════

  /// Localize a module key to a human-readable display name.
  static String _localizeModuleName(String key, AppLanguage lang) {
    const map = <String, Map<AppLanguage, String>>{
      'dashboard':   {AppLanguage.ar: 'لوحة التحكم', AppLanguage.en: 'Dashboard'},
      'customers':   {AppLanguage.ar: 'إدارة العملاء', AppLanguage.en: 'Customer Management'},
      'products':    {AppLanguage.ar: 'كتالوج المنتجات', AppLanguage.en: 'Product Catalog'},
      'invoices':    {AppLanguage.ar: 'الفواتير', AppLanguage.en: 'Invoicing'},
      'payments':    {AppLanguage.ar: 'المدفوعات', AppLanguage.en: 'Payments'},
      'orders':      {AppLanguage.ar: 'الطلبات', AppLanguage.en: 'Orders'},
      'employees':   {AppLanguage.ar: 'إدارة الموظفين', AppLanguage.en: 'Employee Management'},
      'reports':     {AppLanguage.ar: 'التقارير والتحليلات', AppLanguage.en: 'Reports & Analytics'},
      'finance':     {AppLanguage.ar: 'المحاسبة والمالية', AppLanguage.en: 'Accounting & Finance'},
      'accounting':  {AppLanguage.ar: 'المحاسبة والمالية', AppLanguage.en: 'Accounting & Finance'},
      'inventory':   {AppLanguage.ar: 'إدارة المخزون', AppLanguage.en: 'Inventory Management'},
      'pos':         {AppLanguage.ar: 'نقاط البيع', AppLanguage.en: 'Point of Sale'},
      'commissions': {AppLanguage.ar: 'العمولات', AppLanguage.en: 'Commissions'},
      'ai':          {AppLanguage.ar: 'المستشار الذكي', AppLanguage.en: 'AI Advisor'},
      'leads':       {AppLanguage.ar: 'إدارة العملاء المحتملين', AppLanguage.en: 'Lead Management'},
      'sales':       {AppLanguage.ar: 'المبيعات ونقاط البيع', AppLanguage.en: 'Sales & POS'},
      'spare_parts':     {AppLanguage.ar: 'قطع الغيار', AppLanguage.en: 'Spare Parts'},
      'parts_inventory': {AppLanguage.ar: 'مخزون قطع الغيار', AppLanguage.en: 'Parts Inventory'},
      'jobs':            {AppLanguage.ar: 'الوظائف', AppLanguage.en: 'Jobs'},
    };
    return map[key]?[lang] ?? map[key]?[AppLanguage.en] ?? _humanizeKey(key);
  }

  /// Localize a module key to a human-readable description.
  static String _localizeModuleDesc(String key, AppLanguage lang) {
    const map = <String, Map<AppLanguage, String>>{
      'dashboard':   {AppLanguage.ar: 'نظرة عامة على أداء الأعمال والمؤشرات الرئيسية.', AppLanguage.en: 'Business performance overview and key metrics.'},
      'customers':   {AppLanguage.ar: 'سجلات العملاء وجهات الاتصال والتاريخ.', AppLanguage.en: 'Customer records, contacts, and history.'},
      'products':    {AppLanguage.ar: 'إدارة المنتجات والفئات والأسعار.', AppLanguage.en: 'Product, category, and pricing management.'},
      'invoices':    {AppLanguage.ar: 'إنشاء وإدارة فواتير البيع.', AppLanguage.en: 'Create and manage sales invoices.'},
      'payments':    {AppLanguage.ar: 'تتبع المدفوعات والمستحقات.', AppLanguage.en: 'Track payments and receivables.'},
      'orders':      {AppLanguage.ar: 'إدارة طلبات البيع والعروض.', AppLanguage.en: 'Manage sales orders and quotations.'},
      'employees':   {AppLanguage.ar: 'سجلات الموظفين والأدوار وإدارة الصلاحيات.', AppLanguage.en: 'Employee records, roles, and access management.'},
      'reports':     {AppLanguage.ar: 'لوحات أداء الأعمال والتقارير المخصصة.', AppLanguage.en: 'Business performance dashboards and custom reports.'},
      'finance':     {AppLanguage.ar: 'القيود المحاسبية والميزانية والقوائم المالية.', AppLanguage.en: 'Journal entries, balance sheet, and financial statements.'},
      'accounting':  {AppLanguage.ar: 'القيود المحاسبية والميزانية والقوائم المالية.', AppLanguage.en: 'Journal entries, balance sheet, and financial statements.'},
      'inventory':   {AppLanguage.ar: 'تتبع المخزون والمستودعات وحركات البضائع.', AppLanguage.en: 'Stock tracking, warehouses, and movement logs.'},
      'pos':         {AppLanguage.ar: 'نقاط البيع والعمليات النقدية.', AppLanguage.en: 'Point-of-sale and cash operations.'},
      'commissions': {AppLanguage.ar: 'حساب وإدارة عمولات المبيعات.', AppLanguage.en: 'Sales commission calculation and management.'},
      'ai':          {AppLanguage.ar: 'توصيات ذكية مدعومة بالذكاء الاصطناعي.', AppLanguage.en: 'AI-powered smart business recommendations.'},
      'leads':       {AppLanguage.ar: 'تتبع وتحويل العملاء المحتملين.', AppLanguage.en: 'Lead tracking and conversion.'},
      'sales':       {AppLanguage.ar: 'نقاط البيع وعروض الأسعار وإدارة الطلبات.', AppLanguage.en: 'Point-of-sale, quotations, and order management.'},
      'spare_parts':     {AppLanguage.ar: 'إدارة قطع الغيار وأسعارها.', AppLanguage.en: 'Spare parts catalog and pricing.'},
      'parts_inventory': {AppLanguage.ar: 'تتبع مخزون قطع الغيار.', AppLanguage.en: 'Parts inventory tracking.'},
      'jobs':            {AppLanguage.ar: 'إدارة المهام والوظائف.', AppLanguage.en: 'Job and task management.'},
    };
    return map[key]?[lang] ?? map[key]?[AppLanguage.en] ?? '';
  }

  /// Localize a business type to a human-readable display value.
  static String _localizeBusinessType(String type, AppLanguage lang) {
    const map = <String, Map<AppLanguage, String>>{
      'retail':         {AppLanguage.ar: 'تجارة التجزئة', AppLanguage.en: 'Retail'},
      'wholesale':      {AppLanguage.ar: 'تجارة الجملة', AppLanguage.en: 'Wholesale'},
      'service':        {AppLanguage.ar: 'خدمات', AppLanguage.en: 'Service'},
      'manufacturing':  {AppLanguage.ar: 'تصنيع', AppLanguage.en: 'Manufacturing'},
      'restaurant':     {AppLanguage.ar: 'مطاعم', AppLanguage.en: 'Restaurant'},
      'ecommerce':      {AppLanguage.ar: 'تجارة إلكترونية', AppLanguage.en: 'E-Commerce'},
    };
    return map[type]?[lang] ?? map[type]?[AppLanguage.en] ?? type;
  }

  /// Localize known canonical names (departments, pipelines, workflows).
  static String _localizeCanonicalName(String name, AppLanguage lang) {
    const map = <String, Map<AppLanguage, String>>{
      'Management':          {AppLanguage.ar: 'الإدارة', AppLanguage.en: 'Management'},
      'Sales':               {AppLanguage.ar: 'المبيعات', AppLanguage.en: 'Sales'},
      'Warehouse':           {AppLanguage.ar: 'المستودعات', AppLanguage.en: 'Warehouse'},
      'Finance':             {AppLanguage.ar: 'المالية', AppLanguage.en: 'Finance'},
      'Sales Pipeline':      {AppLanguage.ar: 'مسار المبيعات', AppLanguage.en: 'Sales Pipeline'},
      'High Value Approval': {AppLanguage.ar: 'موافقة القيمة العالية', AppLanguage.en: 'High Value Approval'},
      'Warehouse 1':         {AppLanguage.ar: 'المستودع ١', AppLanguage.en: 'Warehouse 1'},
      'Warehouse 2':         {AppLanguage.ar: 'المستودع ٢', AppLanguage.en: 'Warehouse 2'},
    };
    return map[name]?[lang] ?? name;
  }

  /// Convert a snake_case key to a human-readable title.
  static String _humanizeKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Whether the repository has been injected (for structural assertions).
  bool get hasInjectedRepository => _injectedRepo != null;

  /// Whether the discovery service has been injected.
  bool get hasDiscoveryService => _discoveryService != null;

  /// Test-only: set readyForBlueprint + completeness and inject a fake
  /// backend ready message to exercise the localizer.
  @visibleForTesting
  void setReadyForTesting({double completeness = 86}) {
    _readyForBlueprint = true;
    _completeness = completeness;
    _messages.add(DiscoveryMessage(
      id: 'backend-ready-1',
      text: 'I have enough information. Completeness: ${completeness.round()}% (required: 100%).',
      sender: MessageSender.ai,
      timestamp: DateTime.now(),
      messageType: 'ready',
    ));
  }

  /// Test-only: set the discovery session directly.
  @visibleForTesting
  void setSessionForTesting(DiscoverySession session) {
    _discoverySession = session;
    _completeness = session.completeness ?? 0;
    _readyForBlueprint = session.readyForBlueprint;
    if (session.blueprint != null) {
      _realBlueprint = session.blueprint;
    }
  }

  /// Test-only: set the real Blueprint directly.
  @visibleForTesting
  void setBlueprintForTesting(DiscoveryBlueprintDto bp) {
    _realBlueprint = bp;
  }

  /// Test-only: add a message to the internal list.
  @visibleForTesting
  void addMessageForTesting(DiscoveryMessage msg) {
    _messages.add(msg);
  }

  // ── Dependency injection ────────────────────────────────

  /// Inject the [DiscoveryService] from the provider layer.
  void setDiscoveryService(DiscoveryService svc) {
    _discoveryService = svc;
  }

  /// Inject the [ProvisioningRepository] from the provider layer.
  void setProvisioningRepository(ProvisioningRepository repo) {
    _injectedRepo = repo;
  }

  /// Resolve the repository — use injected if available, otherwise create inline.
  ProvisioningRepository _resolveRepo(AppState appState) {
    return _injectedRepo ??
        ProvisioningRepository(
          ProvisioningService(appState.apiClient),
        );
  }

  // ── Phase transitions ───────────────────────────────────

  /// Start the discovery phase. If an active session exists on the backend,
  /// resume it. Otherwise, show the welcome → discovery transition.
  void startDiscovery(BuildContext context) {
    _phase = OnboardingPhase.discovery;
    _discoveryError = null;
    notifyListeners();
  }

  /// Insert a local-only welcome greeting when the conversation is empty.
  ///
  /// This is a UI-only message (no OpenAI call, no backend session).
  /// Guards:
  ///   - Only added when [_messages] is empty
  ///   - Never added when a backend session already exists (resume case)
  ///   - Idempotent: safe to call on every build
  ///
  /// The greeting text is language-aware and uses real user/company names.
  void ensureWelcomeGreeting(AppState appState) {
    // Cache for language resolution in the blueprint bridge
    _currentAppState = appState;
    // Guard: only inject into an empty, fresh conversation
    if (_messages.isNotEmpty) return;
    // Wait until backend resume has been attempted (or skipped if no service)
    if (!_resumeAttempted && _discoveryService != null) return;
    if (_discoverySession != null) return;

    final firstName = appState.currentUser.fullName.split(' ').first;
    final companyName = appState.currentWorkspace.name;
    final isArabic = appState.uiLanguage == AppLanguage.ar;

    final greeting = isArabic
        ? 'مرحبًا $firstName 👋\n\n'
            'يسعدنا انضمام شركة $companyName إلى SmartBiz AI.\n\n'
            'سأساعدك الآن في بناء نظام تشغيل متكامل ومخصص لشركتك. '
            'اكتب لي بالتفصيل كيف تعمل شركتك حاليًا، مثل الأقسام والموظفين '
            'والأدوار، المنتجات أو الخدمات، المبيعات، المخزون، المحاسبة، '
            'الموافقات، وأي إجراءات خاصة بعملك.\n\n'
            'يمكنك كتابة كل التفاصيل في رسالة واحدة، وسأسألك فقط عن '
            'المعلومات التي نحتاج إلى توضيحها.'
        : 'Welcome, $firstName 👋\n\n'
            'We\'re pleased to have $companyName join SmartBiz AI.\n\n'
            'I\'ll help you build a complete business operating system tailored '
            'to your company. Tell me how your business currently works, including '
            'departments, employees and roles, products or services, sales, '
            'inventory, accounting, approvals, and any special processes.\n\n'
            'You can provide all details in one message. I\'ll only ask about '
            'information that still needs clarification.';

    _messages.add(DiscoveryMessage(
      id: 'greeting-local',
      text: greeting,
      sender: MessageSender.ai,
      timestamp: DateTime.now(),
      messageType: 'greeting',
    ));
    notifyListeners();
  }

  /// Replace the backend English ready-notification with a localized version.
  ///
  /// The backend sends a `message_type: 'ready'` message in English:
  ///   "I have enough information... Completeness: 86% (required: 100%)."
  ///
  /// This replaces it with a clean, language-aware message that:
  ///   - Uses the real dynamic completeness
  ///   - Does NOT say "required: 100%"
  ///   - Matches the current UI language
  ///
  /// Idempotent: safe to call on every build. Tracked by a sentinel prefix
  /// in the message ID to avoid double-localization.
  void localizeReadyMessage(AppState appState) {
    if (!_readyForBlueprint) return;

    final idx = _messages.indexWhere((m) =>
        m.messageType == 'ready' && !m.id.startsWith('ready-local-'));
    if (idx == -1) return;

    final isArabic = appState.uiLanguage == AppLanguage.ar;
    final pct = _completeness.round();

    final localizedText = isArabic
        ? 'أصبحت لدي معلومات كافية لإنشاء مخطط أولي لنظام شركتك.\n'
            'نسبة اكتمال التفاصيل: $pct%.\n'
            'يمكنك الآن مراجعة المخطط وتعديله لاحقًا.'
        : 'I now have enough information to create an initial blueprint '
            'for your business system.\n'
            'Detail completeness: $pct%.\n'
            'You can review the blueprint now and refine it later.';

    _messages[idx] = DiscoveryMessage(
      id: 'ready-local-${_messages[idx].id}',
      text: localizedText,
      sender: MessageSender.ai,
      timestamp: _messages[idx].timestamp,
      messageType: 'ready',
    );
    notifyListeners();
  }

  /// Navigate to the Blueprint review phase using the real generated Blueprint.
  void goToBlueprint() {
    if (_realBlueprint == null) return;
    _phase = OnboardingPhase.blueprint;
    notifyListeners();
  }

  void goBack() {
    if (_phase == OnboardingPhase.blueprint) {
      _phase = OnboardingPhase.discovery;
    } else if (_phase == OnboardingPhase.provisioning) {
      _phase = OnboardingPhase.blueprint;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  //  Adaptive AI Discovery
  // ═══════════════════════════════════════════════════════════

  /// Send a user message through the adaptive discovery flow.
  ///
  /// If no session exists, starts a new one with the message as the
  /// business description. Otherwise, submits the message as an answer
  /// to the last follow-up question.
  ///
  /// Duplicate sends are blocked while a request is in progress.
  /// Network errors preserve the conversation and set a retryable error.
  Future<void> sendMessage(String text, BuildContext context) async {
    if (text.trim().isEmpty) return;
    if (_discoveryInFlight) return;
    if (_discoveryService == null) return;

    _discoveryInFlight = true;
    _discoveryError = null;

    // Add user message to local state immediately
    final userMsg = DiscoveryMessage(
      id: 'user-${_messages.length}',
      text: text.trim(),
      sender: MessageSender.user,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _isAiThinking = true;
    notifyListeners();

    try {
      DiscoverySession session;

      // Derive locale from current UI language
      final locale = (_currentAppState?.uiLanguage == AppLanguage.en)
          ? 'en'
          : 'ar';

      if (_discoverySession == null) {
        // First message — start a new session
        session = await _discoveryService!.startSession(
          businessDescription: text.trim(),
          locale: locale,
        );
      } else {
        // Subsequent messages — submit as answer to last follow-up
        final lastQuestion = _discoverySession!.lastFollowUpQuestion;
        if (lastQuestion == null) {
          // No pending question — this shouldn't happen normally.
          // Re-start session with the message as additional context.
          session = await _discoveryService!.startSession(
            businessDescription: text.trim(),
            locale: locale,
          );
        } else {
          session = await _discoveryService!.submitAnswer(
            sessionId: _discoverySession!.id,
            messageId: lastQuestion.id,
            answers: [
              {'answer': text.trim()}
            ],
            locale: locale,
          );
        }
      }

      _applySessionUpdate(session);
    } catch (e) {
      _isAiThinking = false;
      _discoveryError = e.toString();
      notifyListeners();
    } finally {
      _discoveryInFlight = false;
    }
  }

  /// Quick-reply convenience — same as sendMessage.
  Future<void> sendQuickReply(String text, BuildContext context) =>
      sendMessage(text, context);

  /// Resume an existing discovery session from the backend.
  ///
  /// Called when the app restarts or user navigates back to onboarding.
  /// Finds the most recent active session and restores the conversation.
  Future<void> resumeDiscovery() async {
    if (_discoveryService == null) {
      _resumeAttempted = true;
      return;
    }

    try {
      final sessions = await _discoveryService!.listSessions();

      // Find the most recent resumable session.
      // Any session that hasn't been fully provisioned is resumable:
      //   intake, questioning, classified, blueprint_ready, completed.
      const resumableStatuses = {
        'intake', 'questioning', 'classified', 'blueprint_ready', 'completed',
      };
      final candidates = sessions.where(
          (s) => resumableStatuses.contains(s.status)).toList();
      if (candidates.isEmpty) {
        _resumeAttempted = true;
        notifyListeners();
        return;
      }

      // Priority-based selection:
      //   1. blueprint_ready without Blueprint (retry generation)
      //   2. questioning/classified with meaningful progress
      //   3. intake with progress
      //   4. any other resumable session
      // Within the same priority, prefer the most recently updated.
      DiscoverySession? best;
      int bestPriority = 999;
      for (final s in candidates) {
        int priority;
        if (s.status == 'blueprint_ready' && s.blueprint == null) {
          priority = 1;
        } else if (s.status == 'completed' && s.blueprint != null) {
          priority = 2;
        } else if ((s.status == 'questioning' || s.status == 'classified') &&
            (s.completeness ?? 0) > 0) {
          priority = 3;
        } else {
          priority = 4;
        }
        if (priority < bestPriority) {
          bestPriority = priority;
          best = s;
        }
      }
      best ??= candidates.first;

      // Load full session with messages
      final session =
          await _discoveryService!.getSession(sessionId: best.id);

      _discoverySession = session;
      _completeness = session.completeness ?? 0;
      _readyForBlueprint = session.readyForBlueprint;

      // Rebuild local message list from backend messages
      _messages.clear();
      for (final msg in session.messages) {
        _messages.add(DiscoveryMessage(
          id: msg.id,
          text: msg.content,
          sender: msg.role == 'user' ? MessageSender.user : MessageSender.ai,
          timestamp: DateTime.now(),
          quickReplies: msg.suggestionChips,
          messageType: msg.messageType,
        ));
      }

      // If the session has a blueprint, load it
      if (session.blueprint != null) {
        _realBlueprint = session.blueprint;
      }

      if (_messages.isNotEmpty) {
        _phase = OnboardingPhase.discovery;
      }

      _resumeAttempted = true;
      notifyListeners();
    } catch (e) {
      // Resume failure is non-fatal — user can start fresh
      _resumeAttempted = true;
      notifyListeners();
      debugPrint('Discovery resume failed: $e');
    }
  }

  /// Classify the business and generate the Blueprint.
  ///
  /// Smart flow:
  ///   - If the Blueprint is already loaded → direct-open (0 API calls)
  ///   - If the session is already classified → skip classify
  ///   - If the session is already completed → skip classify
  ///   - Otherwise → classify then generate
  Future<void> classifyAndGenerateBlueprint() async {
    if (_discoverySession == null) return;
    if (_discoveryInFlight) return;

    // ── Fast path: Blueprint already loaded (from resume or prior generation)
    if (_realBlueprint != null) {
      _phase = OnboardingPhase.blueprint;
      notifyListeners();
      return;
    }

    // Need the service for API calls
    if (_discoveryService == null) return;

    _discoveryInFlight = true;
    _isAiThinking = true;
    _discoveryError = null;
    notifyListeners();

    try {
      final sessionId = _discoverySession!.id;
      final status = _discoverySession!.status;

      // ── Step 1: Classify (only if not already classified/completed/blueprint_ready)
      if (status != 'classified' && status != 'completed' && status != 'blueprint_ready') {
        final classified = await _discoveryService!.classify(
          sessionId: sessionId,
        );
        _discoverySession = classified;
      }

      // ── Step 2: Generate Blueprint
      final blueprint = await _discoveryService!.generateBlueprint(
        sessionId: sessionId,
      );
      _realBlueprint = blueprint;

      _isAiThinking = false;

      // Auto-transition to Blueprint review
      _phase = OnboardingPhase.blueprint;
      notifyListeners();
    } catch (e) {
      _isAiThinking = false;
      _discoveryError = e.toString();
      notifyListeners();
    } finally {
      _discoveryInFlight = false;
    }
  }

  /// Force a Blueprint regeneration from the backend.
  ///
  /// Clears the cached Blueprint so [classifyAndGenerateBlueprint] will
  /// make a fresh API call instead of using the fast path.
  Future<void> regenerateBlueprint() async {
    _realBlueprint = null;
    await classifyAndGenerateBlueprint();
  }

  /// Apply the backend session update to local state.
  void _applySessionUpdate(DiscoverySession session) {
    _discoverySession = session;
    _completeness = session.completeness ?? 0;
    _readyForBlueprint = session.readyForBlueprint;
    _isAiThinking = false;

    // Append new AI messages from the backend response
    // Only add messages we don't already have locally
    final existingIds = _messages.map((m) => m.id).toSet();

    for (final msg in session.messages) {
      if (msg.role == 'ai' && !existingIds.contains(msg.id)) {
        _messages.add(DiscoveryMessage(
          id: msg.id,
          text: msg.content,
          sender: MessageSender.ai,
          timestamp: DateTime.now(),
          quickReplies: msg.suggestionChips,
          messageType: msg.messageType,
        ));
      }
    }

    // If the session already has a blueprint (e.g., resumed completed session)
    if (session.blueprint != null) {
      _realBlueprint = session.blueprint;
    }

    notifyListeners();
  }

  /// Clear discovery state (on logout or account switch).
  void clearDiscoveryState() {
    _discoverySession = null;
    _realBlueprint = null;
    _messages.clear();
    _completeness = 0;
    _readyForBlueprint = false;
    _discoveryError = null;
    _discoveryInFlight = false;
    _resumeAttempted = false;
  }

  // ═══════════════════════════════════════════════════════════
  //  Real Provisioning — ProvisioningRepository Integration
  // ═══════════════════════════════════════════════════════════

  /// Full real provisioning pipeline:
  ///   preview → core apply → operational apply → finalize → refresh session → dashboard
  ///
  /// Uses [ProvisioningRepository] for all backend calls and
  /// [AppState.loadCurrentSession] for session synchronization.
  ///
  /// Includes:
  ///   - Duplicate request prevention via [_provisioningInFlight]
  ///   - Resume logic via [getActiveConfig] to pick up interrupted runs
  ///   - Granular [ProvisioningStep] tracking for UI sub-state
  ///   - Post-refresh verification that onboardingCompleted is true
  ///   - Preview validation before apply
  ///   - 409 status recheck for operational and finalize steps
  Future<void> startRealProvisioning(AppState appState) async {
    // ── Guard: prevent duplicate taps ──
    if (_provisioningInFlight) return;
    _provisioningInFlight = true;

    _phase = OnboardingPhase.provisioning;
    _isProvisioning = true;
    _provisioningError = null;
    _provisioningStep = ProvisioningStep.previewing;
    notifyListeners();

    try {
      final repo = _resolveRepo(appState);

      // ── Step 0: Check for an existing run (resume logic) ──
      final resumePoint = await _resolveActiveRun(repo);

      String? runId = resumePoint.runId;
      var startFrom = resumePoint.startFrom;

      if (runId != null) {
        _activeRunId = runId;
      }

      // Resolve the blueprint ID — prefer the real discovery blueprint UUID,
      // fall back to resolveTemplateKey for legacy compatibility.
      final blueprintId = resolveBlueprintId(appState);

      // ── Step 0.5: Preview (if starting from scratch) ──
      if (startFrom <= _PipelinePhase.preview) {
        _provisioningStep = ProvisioningStep.previewing;
        notifyListeners();

        final previewOk = await _previewProvisioning(repo, blueprintId);
        if (!previewOk) return; // error already set
      }

      // ── Step 1: Core Apply (if not resuming past it) ──
      if (startFrom <= _PipelinePhase.coreApply) {
        _provisioningStep = ProvisioningStep.applying;
        notifyListeners();

        final applyResult = await _applyProvisioning(repo, blueprintId);
        if (applyResult == null) return; // error already set

        runId = applyResult.runId;
        _activeRunId = runId;
      }

      // ── Step 2: Operational Apply (if not resuming past it) ──
      if (startFrom <= _PipelinePhase.operationalApply) {
        _provisioningStep = ProvisioningStep.applyingOperational;
        notifyListeners();

        final opResult = await _applyOperational(repo, runId!);
        if (opResult == null) return; // error already set
      }

      // ── Step 3: Finalize ──
      if (startFrom <= _PipelinePhase.finalize) {
        _provisioningStep = ProvisioningStep.finalizing;
        notifyListeners();

        final finalizeOk = await _finalizeProvisioning(repo, runId!);
        if (!finalizeOk) return; // error already set
      }

      // ── Step 4: Refresh session ──
      _provisioningStep = ProvisioningStep.refreshingSession;
      notifyListeners();

      await appState.loadCurrentSession();

      // ── Step 4b: Verify session sync ──
      if (!appState.isOnboardingCompleted) {
        _setProvisioningError(
          'Session sync failed — onboarding flag not set. Please try again.',
        );
        return;
      }

      // ── Done ──
      _isProvisioning = false;
      _provisioningDone = true;
      _provisioningStep = ProvisioningStep.idle;
      _phase = OnboardingPhase.complete;
      notifyListeners();
    } catch (e) {
      _setProvisioningError(e.toString());
    } finally {
      _provisioningInFlight = false;
    }
  }

  /// Check for an existing provisioning run and determine resume point.
  Future<_ResumePoint> _resolveActiveRun(ProvisioningRepository repo) async {
    final configResult = await repo.getActiveConfig();
    if (configResult.isFailure || configResult.data == null) {
      return _ResumePoint(null, _PipelinePhase.preview);
    }

    final run = configResult.data!;
    switch (run.status) {
      case ProvisioningRunStatus.preview:
      case ProvisioningRunStatus.prepared:
        return _ResumePoint(run.id, _PipelinePhase.coreApply);

      case ProvisioningRunStatus.foundationApplied:
        return _ResumePoint(run.id, _PipelinePhase.operationalApply);

      case ProvisioningRunStatus.applied:
        return _ResumePoint(run.id, _PipelinePhase.finalize);

      case ProvisioningRunStatus.onboardingComplete:
        return _ResumePoint(run.id, _PipelinePhase.refreshSession);

      case ProvisioningRunStatus.processing:
        return _ResumePoint(null, _PipelinePhase.preview);

      default:
        return _ResumePoint(null, _PipelinePhase.preview);
    }
  }

  Future<bool> _previewProvisioning(
    ProvisioningRepository repo,
    String blueprintId,
  ) async {
    final result = await repo.preview(blueprintId: blueprintId);

    if (result.isFailure) {
      _setProvisioningError(
        _humanReadableError(result.error!, 'preview'),
      );
      return false;
    }

    final preview = result.data!;

    if (!preview.isValid) {
      final errors = preview.validationErrors.join('\n');
      _setProvisioningError(
        errors.isNotEmpty
            ? 'Blueprint validation failed:\n$errors'
            : 'Blueprint validation failed. Please revise your configuration.',
      );
      return false;
    }

    return true;
  }

  Future<ApplyResult?> _applyProvisioning(
    ProvisioningRepository repo,
    String templateKey,
  ) async {
    final result = await repo.apply(blueprintId: templateKey);

    if (result.isFailure) {
      _setProvisioningError(
        _humanReadableError(result.error!, 'core apply'),
      );
      return null;
    }

    final data = result.data!;

    if (data.activeRunId != null && data.activeRunId!.isNotEmpty) {
      _activeRunId = data.activeRunId;
      return data;
    }

    return data;
  }

  Future<ApplyResult?> _applyOperational(
    ProvisioningRepository repo,
    String runId,
  ) async {
    final result = await repo.applyOperational(runId: runId);

    if (result.isFailure) {
      if (result.error?.errorCode == 'invalid_status_transition') {
        final recheckResult = await repo.getActiveConfig();
        if (recheckResult.isSuccess && recheckResult.data != null) {
          final currentStatus = recheckResult.data!.status;
          if (currentStatus == ProvisioningRunStatus.applied ||
              currentStatus == ProvisioningRunStatus.onboardingComplete) {
            return ApplyResult(runId: runId, status: currentStatus.name);
          }
        }
        _setProvisioningError(
          'Operational apply conflict — current status does not confirm completion. Please try again.',
        );
        return null;
      }
      _setProvisioningError(
        _humanReadableError(result.error!, 'operational apply'),
      );
      return null;
    }

    return result.data;
  }

  Future<bool> _finalizeProvisioning(
    ProvisioningRepository repo,
    String runId,
  ) async {
    final result = await repo.finalize(runId: runId);

    if (result.isFailure) {
      if (result.error?.errorCode == 'invalid_status_transition') {
        final recheckResult = await repo.getActiveConfig();
        if (recheckResult.isSuccess && recheckResult.data != null) {
          final currentStatus = recheckResult.data!.status;
          if (currentStatus == ProvisioningRunStatus.onboardingComplete) {
            return true;
          }
        }
        _setProvisioningError(
          'Finalize conflict — onboarding not yet complete. Please try again.',
        );
        return false;
      }
      _setProvisioningError(
        _humanReadableError(result.error!, 'finalize'),
      );
      return false;
    }

    return true;
  }

  /// Set error state and revert to blueprint phase for retry.
  void _setProvisioningError(String message) {
    _isProvisioning = false;
    _provisioningError = message;
    _provisioningStep = ProvisioningStep.idle;
    _phase = OnboardingPhase.blueprint; // allow retry
    _provisioningInFlight = false;
    notifyListeners();
  }

  /// Map provisioning errors to user-facing messages.
  String _humanReadableError(ProvisioningError error, String phase) {
    switch (error.statusCode) {
      case 401:
        return 'Session expired. Please log in again.';
      case 403:
        return 'You do not have permission to configure this workspace.';
      case 404:
        return 'Configuration not found. Please try again.';
      case 409:
        return error.message.isNotEmpty
            ? error.message
            : 'A provisioning run is already active.';
      case 422:
        return error.message.isNotEmpty
            ? error.message
            : 'Validation error during $phase.';
      default:
        if (error.statusCode >= 500) {
          return 'Server error. Please try again later.';
        }
        return error.message.isNotEmpty
            ? error.message
            : 'Provisioning failed during $phase. Please try again.';
    }
  }

  /// Resolve the blueprint ID for provisioning.
  ///
  /// Prefers the real discovery Blueprint UUID (required for the backend
  /// provisioning endpoint which expects `blueprint_id` as a UUID).
  /// Falls back to [resolveTemplateKey] for legacy/manual provisioning.
  String resolveBlueprintId(AppState appState) {
    // Real discovery Blueprint UUID — this is what the backend expects
    if (_realBlueprint != null) {
      return _realBlueprint!.id;
    }
    // Fallback to keyword-based template key
    return resolveTemplateKey(appState);
  }

  /// Map the current onboarding context to a template_key.
  ///
  /// Uses the real Blueprint's business_type from the adaptive discovery,
  /// or falls back to workspace metadata.
  String resolveTemplateKey(AppState appState) {
    // Prefer the real Blueprint's business type from discovery
    String? raw = _realBlueprint?.businessType ??
        _discoverySession?.businessType;

    // Normalize and map to template key
    final normalized = (raw ?? '').toLowerCase().trim();

    if (normalized.contains('automotive') ||
        normalized.contains('car') ||
        normalized.contains('vehicle') ||
        normalized.contains('dealer')) {
      return 'automotive_dealer';
    }
    if (normalized.contains('retail') ||
        normalized.contains('shop') ||
        normalized.contains('pos') ||
        normalized.contains('store')) {
      return 'retail_pos';
    }
    if (normalized.contains('workshop') ||
        normalized.contains('service') && normalized.contains('repair') ||
        normalized.contains('garage') ||
        normalized.contains('maintenance')) {
      return 'workshop_service';
    }
    if (normalized.contains('restaurant') ||
        normalized.contains('food') ||
        normalized.contains('fnb') ||
        normalized.contains('café') ||
        normalized.contains('cafe')) {
      return 'restaurant_fnb';
    }
    if (normalized.contains('consulting') ||
        normalized.contains('agency') ||
        normalized.contains('services') ||
        normalized.contains('professional')) {
      return 'professional_services';
    }

    // Safe default
    return 'professional_services';
  }

  void resetOnboarding() {
    _phase = OnboardingPhase.welcome;
    clearDiscoveryState();
    _isAiThinking = false;
    _isProvisioning = false;
    _provisioningDone = false;
    _provisioningError = null;
    _provisioningStep = ProvisioningStep.idle;
    _activeRunId = null;
    _provisioningInFlight = false;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════
//  Internal Pipeline Helpers
// ═══════════════════════════════════════════════════════════

/// Ordered pipeline phases for comparison-based resume logic.
class _PipelinePhase {
  static const int preview = 0;
  static const int coreApply = 1;
  static const int operationalApply = 2;
  static const int finalize = 3;
  static const int refreshSession = 4;
}

/// Describes where to resume the provisioning pipeline.
class _ResumePoint {
  final String? runId;
  final int startFrom;
  const _ResumePoint(this.runId, this.startFrom);
}
