// SmartBiz AI — Welcome Greeting UX Test.
//
// Proves:
//   1. Fresh discovery shows the localized dynamic greeting
//   2. Existing/resumed conversation does not add it again
//   3. Switching language displays the correct text

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

void main() {
  group('Welcome greeting', () {
    // Default AppState language is Arabic, user is Mohamed Doma

    test('fresh discovery shows Arabic greeting with real names (default)', () {
      final state = OnboardingState();
      final appState = AppState();

      state.ensureWelcomeGreeting(appState);

      expect(state.messages, hasLength(1));

      final greeting = state.messages.first;
      expect(greeting.sender.name, 'ai');
      expect(greeting.messageType, 'greeting');
      expect(greeting.id, 'greeting-local');

      // Contains the real user first name
      expect(greeting.text, contains('Mohamed'));
      // Contains the company/workspace name
      expect(greeting.text, contains('SmartBiz Demo'));
      // Contains Arabic content (default language)
      expect(greeting.text, contains('مرحبًا'));
      expect(greeting.text, contains('SmartBiz AI'));
      expect(greeting.text, contains('نظام تشغيل'));
    });

    test('fresh discovery shows English greeting when language is English', () {
      final state = OnboardingState();
      final appState = AppState();
      appState.setUiLanguage(AppLanguage.en);

      state.ensureWelcomeGreeting(appState);

      expect(state.messages, hasLength(1));

      final greeting = state.messages.first;
      expect(greeting.text, contains('Welcome, Mohamed'));
      expect(greeting.text, contains('SmartBiz Demo'));
      expect(greeting.text, contains('SmartBiz AI'));
      expect(greeting.text, contains('business operating system'));
    });

    test('switching language shows correct text', () {
      // Arabic (default)
      final stateAr = OnboardingState();
      final appAr = AppState();
      stateAr.ensureWelcomeGreeting(appAr);
      expect(stateAr.messages.first.text, contains('مرحبًا'));

      // English
      final stateEn = OnboardingState();
      final appEn = AppState();
      appEn.setUiLanguage(AppLanguage.en);
      stateEn.ensureWelcomeGreeting(appEn);
      expect(stateEn.messages.first.text, contains('Welcome,'));
    });

    test('does not duplicate on repeated calls', () {
      final state = OnboardingState();
      final appState = AppState();

      state.ensureWelcomeGreeting(appState);
      state.ensureWelcomeGreeting(appState);
      state.ensureWelcomeGreeting(appState);

      expect(state.messages, hasLength(1),
          reason: 'Greeting must not be duplicated');
    });

    test('resumed conversation does not add greeting again', () {
      final state = OnboardingState();
      final appState = AppState();

      // Add greeting first
      state.ensureWelcomeGreeting(appState);
      expect(state.messages, hasLength(1));

      // Calling again should not add another
      state.ensureWelcomeGreeting(appState);
      expect(state.messages, hasLength(1));
    });

    test('resetOnboarding clears greeting, fresh call re-adds it', () {
      final state = OnboardingState();
      final appState = AppState();

      state.ensureWelcomeGreeting(appState);
      expect(state.messages, hasLength(1));

      state.resetOnboarding();
      expect(state.messages, isEmpty);

      state.ensureWelcomeGreeting(appState);
      expect(state.messages, hasLength(1));
      expect(state.messages.first.messageType, 'greeting');
    });

    test('greeting uses first name only', () {
      final state = OnboardingState();
      final appState = AppState();

      state.ensureWelcomeGreeting(appState);

      final text = state.messages.first.text;
      // Default is Arabic, so check Arabic greeting with first name
      expect(text, contains('مرحبًا Mohamed'));
    });
  });
}
