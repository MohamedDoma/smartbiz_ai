// SmartBiz AI — Onboarding state management.
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/state/app_state.dart';
import 'models/onboarding_models.dart';
import 'data/mock_discovery.dart';

/// Phases of the onboarding flow.
enum OnboardingPhase { welcome, discovery, blueprint, provisioning, complete }

/// Central state for the onboarding / discovery flow.
class OnboardingState extends ChangeNotifier {
  OnboardingPhase _phase = OnboardingPhase.welcome;
  final List<DiscoveryMessage> _messages = [];
  DiscoveryProgress _progress = DiscoveryProgress.initial();
  BlueprintModel? _blueprint;
  bool _isAiThinking = false;
  bool _isProvisioning = false;
  bool _provisioningDone = false;
  String? _provisioningError;
  int _userMessageCount = 0;

  // ── Getters ─────────────────────────────────────────────
  OnboardingPhase get phase => _phase;
  List<DiscoveryMessage> get messages => List.unmodifiable(_messages);
  DiscoveryProgress get progress => _progress;
  BlueprintModel? get blueprint => _blueprint;
  bool get isAiThinking => _isAiThinking;
  bool get isProvisioning => _isProvisioning;
  bool get provisioningDone => _provisioningDone;
  String? get provisioningError => _provisioningError;

  // ── Phase transitions ───────────────────────────────────
  void startDiscovery(BuildContext context) {
    _phase = OnboardingPhase.discovery;
    // AI sends first message (localized)
    _addAiMessage(tr(context, MockDiscovery.welcomeMessageKey));
    notifyListeners();
  }

  void goToBlueprint() {
    _blueprint = MockDiscovery.sampleBlueprint;
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

  void startProvisioning() {
    _phase = OnboardingPhase.provisioning;
    _isProvisioning = true;
    _provisioningError = null;
    notifyListeners();

    // Simulate provisioning (2s delay) — mock-only fallback
    Future.delayed(const Duration(seconds: 2), () {
      _isProvisioning = false;
      _provisioningDone = true;
      _phase = OnboardingPhase.complete;
      notifyListeners();
    });
  }

  /// Apply a real business template via backend API.
  ///
  /// Maps the onboarding business type to a template_key and calls
  /// AppState.applyBusinessTemplate, which applies modules/roles on the server
  /// and refreshes the session.
  Future<void> startRealProvisioning(AppState appState) async {
    _phase = OnboardingPhase.provisioning;
    _isProvisioning = true;
    _provisioningError = null;
    notifyListeners();

    try {
      final templateKey = resolveTemplateKey(appState);
      await appState.applyBusinessTemplate(templateKey);

      _isProvisioning = false;
      _provisioningDone = true;
      _phase = OnboardingPhase.complete;
      notifyListeners();
    } catch (e) {
      _isProvisioning = false;
      _provisioningError = e.toString();
      _phase = OnboardingPhase.blueprint; // allow retry
      notifyListeners();
    }
  }

  /// Map the current onboarding context to a template_key.
  ///
  /// Uses the workspace's industry_type from registration, or the
  /// blueprint's businessType from the mock discovery flow.
  String resolveTemplateKey(AppState appState) {
    // Check registered business type
    final session = appState.lastSession;
    String? raw;
    if (session?.activeWorkspace != null) {
      // Fallback: try blueprint data if available
      raw = _blueprint?.businessType;
    }

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
    _messages.clear();
    _progress = DiscoveryProgress.initial();
    _blueprint = null;
    _isAiThinking = false;
    _isProvisioning = false;
    _provisioningDone = false;
    _provisioningError = null;
    _userMessageCount = 0;
    notifyListeners();
  }

  // ── Discovery conversation ──────────────────────────────
  void sendMessage(String text, BuildContext context) {
    if (text.trim().isEmpty) return;

    final userMsg = DiscoveryMessage(
      id: 'user-${_messages.length}',
      text: text.trim(),
      sender: MessageSender.user,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _userMessageCount++;
    _isAiThinking = true;
    notifyListeners();

    // Capture the current user msg index for the response lookup
    final stepIndex = _userMessageCount - 1;

    // Simulate AI response
    Future.delayed(const Duration(milliseconds: 800), () {
      _isAiThinking = false;

      final mockResponse = MockDiscovery.getResponseForStep(stepIndex);
      // ignore: use_build_context_synchronously
      final resolvedText = tr(context, mockResponse.textKey);
      final resolvedReplies = mockResponse.quickReplyKeys
          ?.map((key) => tr(context, key))
          .toList();

      _addAiMessage(resolvedText, quickReplies: resolvedReplies);

      // Advance progress — one category per user message, up to total categories
      _advanceProgress();
      notifyListeners();
    });
  }

  void sendQuickReply(String text, BuildContext context) => sendMessage(text, context);

  void _addAiMessage(String text, {List<String>? quickReplies}) {
    _messages.add(DiscoveryMessage(
      id: 'ai-${_messages.length}',
      text: text,
      sender: MessageSender.ai,
      timestamp: DateTime.now(),
      quickReplies: quickReplies,
    ));
  }

  void _advanceProgress() {
    final categories = DiscoveryCategory.values;
    // Mark one category per user message, sequentially
    for (int i = 0; i < categories.length && i < _userMessageCount; i++) {
      _progress = _progress.copyWith(categories[i], true);
    }
  }
}
