// SmartBiz AI — Settings state (workspace, branding, billing).
// Performance: lazy subscription init.
import 'package:flutter/material.dart';
import 'models/settings_models.dart';

class SettingsState extends ChangeNotifier {
  final WorkspaceConfig workspace = WorkspaceConfig();
  final BrandingSettings branding = BrandingSettings();

  SubscriptionInfo? _subscription;

  SubscriptionInfo get subscription => _subscription ??= SubscriptionInfo(
    plan: PlanType.growth,
    cycle: BillingCycle.monthly,
    isTrial: true,
    renewalDate: DateTime.now().add(const Duration(days: 22)),
    employeeLimit: 15,
    activeEmployees: 4,
    aiCreditsTotal: 5000,
    aiCreditsUsed: 3420,
  );

  // ── Workspace ───────────────────────────────────────────
  void updateCompanyName(String v) { workspace.companyName = v; notifyListeners(); }
  void updateIndustry(String v) { workspace.industry = v; notifyListeners(); }
  void updateTimezone(String v) { workspace.timezone = v; notifyListeners(); }
  void updateCurrency(String v) { workspace.currency = v; notifyListeners(); }

  // ── Branding ────────────────────────────────────────────
  void setPrimaryColor(Color c) { branding.primaryColor = c; notifyListeners(); }
  void setAccentColor(Color c) { branding.accentColor = c; notifyListeners(); }
  void toggleDarkMode() { branding.darkMode = !branding.darkMode; notifyListeners(); }

  // ── Billing ─────────────────────────────────────────────
  void setCycle(BillingCycle c) {
    final s = subscription;
    _subscription = SubscriptionInfo(
      plan: s.plan, cycle: c, isTrial: s.isTrial,
      renewalDate: s.renewalDate, employeeLimit: s.employeeLimit,
      activeEmployees: s.activeEmployees, aiCreditsTotal: s.aiCreditsTotal,
      aiCreditsUsed: s.aiCreditsUsed,
    );
    notifyListeners();
  }

  /// Plan definitions for pricing cards.
  static const List<PlanFeatures> plans = [
    PlanFeatures(type: PlanType.starter, nameKey: 'plan_starter', priceKey: 'plan_starter_price', employees: 5, aiCredits: 1000, featureKeys: ['plan_feat_basic', 'plan_feat_invoices', 'plan_feat_products'], supportKey: 'plan_support_email'),
    PlanFeatures(type: PlanType.growth, nameKey: 'plan_growth', priceKey: 'plan_growth_price', employees: 15, aiCredits: 5000, featureKeys: ['plan_feat_basic', 'plan_feat_invoices', 'plan_feat_products', 'plan_feat_accounting', 'plan_feat_advisor'], supportKey: 'plan_support_priority', recommended: true),
    PlanFeatures(type: PlanType.business, nameKey: 'plan_business', priceKey: 'plan_business_price', employees: 50, aiCredits: 20000, featureKeys: ['plan_feat_basic', 'plan_feat_invoices', 'plan_feat_products', 'plan_feat_accounting', 'plan_feat_advisor', 'plan_feat_api', 'plan_feat_roles'], supportKey: 'plan_support_dedicated'),
    PlanFeatures(type: PlanType.enterprise, nameKey: 'plan_enterprise', priceKey: 'plan_enterprise_price', employees: 999, aiCredits: 100000, featureKeys: ['plan_feat_basic', 'plan_feat_invoices', 'plan_feat_products', 'plan_feat_accounting', 'plan_feat_advisor', 'plan_feat_api', 'plan_feat_roles', 'plan_feat_custom', 'plan_feat_sla'], supportKey: 'plan_support_247'),
  ];
}
