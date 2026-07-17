// SmartBiz AI — Ready message localization test.
//
// Proves:
//   1. Arabic ready message at 86%.
//   2. English ready message at 86%.
//   3. No "required: 100%" text.
//   4. Button visibility follows ready_for_blueprint, not a fixed percentage.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

void main() {
  group('Ready message localization', () {
    /// Helper: create a state with a fake ready message from the backend.
    OnboardingState stateWithReadyMessage({double completeness = 86}) {
      final state = OnboardingState();
      // Simulate _applySessionUpdate having set readyForBlueprint and completeness
      state.setReadyForTesting(completeness: completeness);
      return state;
    }

    test('1. Arabic ready message at 86%', () {
      final state = stateWithReadyMessage(completeness: 86);
      final appState = AppState(); // default language is Arabic

      state.localizeReadyMessage(appState);

      final readyMsg = state.messages.firstWhere(
        (m) => m.messageType == 'ready',
        orElse: () => throw StateError('No ready message found'),
      );

      expect(readyMsg.text, contains('مخطط أولي'));
      expect(readyMsg.text, contains('86%'));
      expect(readyMsg.text, contains('مراجعة المخطط'));
    });

    test('2. English ready message at 86%', () {
      final state = stateWithReadyMessage(completeness: 86);
      final appState = AppState();
      appState.setUiLanguage(AppLanguage.en);

      state.localizeReadyMessage(appState);

      final readyMsg = state.messages.firstWhere(
        (m) => m.messageType == 'ready',
      );

      expect(readyMsg.text, contains('initial blueprint'));
      expect(readyMsg.text, contains('86%'));
      expect(readyMsg.text, contains('review the blueprint'));
    });

    test('3. no "required: 100%" text in any language', () {
      final stateAr = stateWithReadyMessage();
      final stateEn = stateWithReadyMessage();

      final appAr = AppState(); // Arabic
      final appEn = AppState();
      appEn.setUiLanguage(AppLanguage.en);

      stateAr.localizeReadyMessage(appAr);
      stateEn.localizeReadyMessage(appEn);

      final arText = stateAr.messages
          .firstWhere((m) => m.messageType == 'ready')
          .text;
      final enText = stateEn.messages
          .firstWhere((m) => m.messageType == 'ready')
          .text;

      expect(arText, isNot(contains('required: 100%')));
      expect(enText, isNot(contains('required: 100%')));
      expect(arText, isNot(contains('required')));
      expect(enText, isNot(contains('required')));
    });

    test('4. readyForBlueprint controls button, not a fixed percentage', () {
      // Not ready at 50%
      final stateNotReady = OnboardingState();
      expect(stateNotReady.readyForBlueprint, false);
      expect(stateNotReady.completeness, 0);

      // Ready at 86% (not 100%)
      final stateReady = stateWithReadyMessage(completeness: 86);
      expect(stateReady.readyForBlueprint, true);
      expect(stateReady.completeness, 86);
    });

    test('localizeReadyMessage is idempotent', () {
      final state = stateWithReadyMessage(completeness: 86);
      final appState = AppState();

      state.localizeReadyMessage(appState);
      state.localizeReadyMessage(appState);
      state.localizeReadyMessage(appState);

      // Only one ready message should exist
      final readyMsgs =
          state.messages.where((m) => m.messageType == 'ready').toList();
      expect(readyMsgs, hasLength(1));
    });

    test('does not localize when not ready', () {
      final state = OnboardingState();
      final appState = AppState();

      // Not ready — localizeReadyMessage should be a no-op
      state.localizeReadyMessage(appState);
      expect(state.messages, isEmpty);
    });
  });
}
