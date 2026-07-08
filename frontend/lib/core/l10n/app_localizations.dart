// SmartBiz AI — Localization service.
//
// Provides string lookup by key with fallback to English.
// Directionality is derived from the active UI locale.
import 'package:flutter/material.dart';
import 'strings_en.dart';
import 'strings_ar.dart';

/// Supported UI languages.
enum AppLanguage {
  en(locale: Locale('en'), label: 'English', nativeLabel: 'English', isRtl: false),
  ar(locale: Locale('ar'), label: 'Arabic', nativeLabel: 'العربية', isRtl: true);

  final Locale locale;
  final String label;
  final String nativeLabel;
  final bool isRtl;

  const AppLanguage({
    required this.locale,
    required this.label,
    required this.nativeLabel,
    required this.isRtl,
  });

  TextDirection get textDirection => isRtl ? TextDirection.rtl : TextDirection.ltr;

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.locale.languageCode == code,
      orElse: () => AppLanguage.ar,
    );
  }
}

/// String lookup table per language.
const Map<AppLanguage, Map<String, String>> _strings = {
  AppLanguage.en: enStrings,
  AppLanguage.ar: arStrings,
};

/// Get a localized string by key, falling back to English.
String tr(BuildContext context, String key) {
  final appState = _AppLocaleAccessor.of(context);
  final lang = appState ?? AppLanguage.ar;
  return _strings[lang]?[key] ?? _strings[AppLanguage.en]?[key] ?? '[$key]';
}

/// Standalone lookup (no context needed, for use in models).
String trForLang(AppLanguage lang, String key) {
  return _strings[lang]?[key] ?? _strings[AppLanguage.en]?[key] ?? '[$key]';
}

/// InheritedWidget to provide current language down the tree.
/// This is set up by AppState and consumed by tr().
class _AppLocaleAccessor extends InheritedWidget {
  final AppLanguage language;

  const _AppLocaleAccessor({
    required this.language,
    required super.child,
  });

  static AppLanguage? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AppLocaleAccessor>()?.language;
  }

  @override
  bool updateShouldNotify(_AppLocaleAccessor oldWidget) => language != oldWidget.language;
}

class AppLocaleProvider extends StatelessWidget {
  final AppLanguage language;
  final Widget child;

  const AppLocaleProvider({
    super.key,
    required this.language,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _AppLocaleAccessor(language: language, child: child);
  }
}
