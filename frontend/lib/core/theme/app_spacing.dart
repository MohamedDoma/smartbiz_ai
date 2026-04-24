/// SmartBiz AI — Spacing, radius, shadows.
import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double base = 16;
  static const double lg  = 20;
  static const double xl  = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Page padding
  static const EdgeInsets pagePadding = EdgeInsets.all(base);
  static const EdgeInsets pagePaddingHorizontal = EdgeInsets.symmetric(horizontal: base);
  static const EdgeInsets cardPadding = EdgeInsets.all(base);
}

class AppRadius {
  AppRadius._();

  static const double xs  = 4;
  static const double sm  = 6;
  static const double md  = 8;
  static const double lg  = 12;
  static const double xl  = 16;
  static const double xxl = 24;
  static const double full = 999;

  static BorderRadius get cardRadius  => BorderRadius.circular(lg);
  static BorderRadius get inputRadius => BorderRadius.circular(md);
  static BorderRadius get buttonRadius => BorderRadius.circular(md);
  static BorderRadius get chipRadius  => BorderRadius.circular(full);
  static BorderRadius get dialogRadius => BorderRadius.circular(xl);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get sm => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get xl => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
