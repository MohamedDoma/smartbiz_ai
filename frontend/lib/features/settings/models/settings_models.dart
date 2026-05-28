// SmartBiz AI — Workspace branding + billing models.

import 'package:flutter/material.dart';

/// Subscription plan type.
enum PlanType { starter, growth, business, enterprise }

/// Billing cycle.
enum BillingCycle { monthly, yearly, semiAnnual }

/// Workspace branding settings.
class BrandingSettings {
  Color primaryColor;
  Color accentColor;
  bool darkMode;

  BrandingSettings({
    this.primaryColor = const Color(0xFF1A56DB),
    this.accentColor = const Color(0xFF7C3AED),
    this.darkMode = false,
  });
}

/// Workspace config fields.
class WorkspaceConfig {
  String companyName;
  String industry;
  String timezone;
  String currency;

  WorkspaceConfig({
    this.companyName = 'SmartBiz Demo',
    this.industry = 'Retail & Distribution',
    this.timezone = 'Asia/Riyadh (GMT+3)',
    this.currency = 'SAR — Saudi Riyal',
  });
}

/// Subscription info.
class SubscriptionInfo {
  final PlanType plan;
  final BillingCycle cycle;
  final bool isTrial;
  final DateTime renewalDate;
  final int employeeLimit;
  final int activeEmployees;
  final int aiCreditsTotal;
  final int aiCreditsUsed;

  const SubscriptionInfo({
    required this.plan,
    required this.cycle,
    this.isTrial = false,
    required this.renewalDate,
    required this.employeeLimit,
    required this.activeEmployees,
    required this.aiCreditsTotal,
    required this.aiCreditsUsed,
  });

  int get aiCreditsRemaining => aiCreditsTotal - aiCreditsUsed;
  double get aiUsagePercent => aiCreditsTotal > 0 ? aiCreditsUsed / aiCreditsTotal : 0;
  double get employeeUsagePercent => employeeLimit > 0 ? activeEmployees / employeeLimit : 0;
  bool get isAiLow => aiUsagePercent > 0.8;
}

/// Plan feature definition for pricing cards.
class PlanFeatures {
  final PlanType type;
  final String nameKey;
  final String priceKey;
  final int employees;
  final int aiCredits;
  final List<String> featureKeys;
  final String supportKey;
  final bool recommended;

  const PlanFeatures({
    required this.type,
    required this.nameKey,
    required this.priceKey,
    required this.employees,
    required this.aiCredits,
    required this.featureKeys,
    required this.supportKey,
    this.recommended = false,
  });
}
