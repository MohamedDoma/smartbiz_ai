// SmartBiz AI — Onboarding state management.
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
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

    // Simulate provisioning (2s delay)
    Future.delayed(const Duration(seconds: 2), () {
      _isProvisioning = false;
      _provisioningDone = true;
      _phase = OnboardingPhase.complete;
      notifyListeners();
    });
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
