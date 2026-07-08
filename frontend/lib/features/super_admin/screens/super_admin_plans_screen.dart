// SmartBiz AI — Super Admin Plans / Subscriptions screen.
// Mutable local state for Add/Edit/Duplicate/Enable-Disable actions.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/modules/erp_module_registry.dart';
import '../data/mock_tenants.dart';

// ═══════════════════════════════════════════════════════════
//  Billing Period
// ═══════════════════════════════════════════════════════════

enum BillingPeriod { monthly, semiAnnual, annual }

class _BillingOption {
  final double price;
  final String? saveLabel;
  const _BillingOption(this.price, [this.saveLabel]);
}

// ═══════════════════════════════════════════════════════════
//  Mutable Plan Model
// ═══════════════════════════════════════════════════════════

class _Plan {
  String id;
  String name;
  Map<BillingPeriod, _BillingOption> pricing;
  bool enabled;
  Color accentColor;
  bool recommended;
  int userLimit;
  int moduleLimit;
  int aiCredits;
  String storage;
  String supportKey;
  bool posAccess;
  List<String> modules;
  // Offer
  bool offerEnabled;
  String offerLabel;
  int offerDiscount;
  String offerExpiry;
  // Custom duration
  String customDurationLabel;
  String customDurationPrice;

  _Plan({required this.id, required this.name, required this.pricing,
    this.enabled = true, required this.accentColor, this.recommended = false,
    required this.userLimit, required this.moduleLimit, required this.aiCredits,
    required this.storage, required this.supportKey, required this.posAccess,
    required this.modules, this.offerEnabled = false, this.offerLabel = '',
    this.offerDiscount = 0, this.offerExpiry = '',
    this.customDurationLabel = '', this.customDurationPrice = ''});

  String priceStr(BillingPeriod bp) => '\$${pricing[bp]!.price.toStringAsFixed(0)}';
  String? saveStr(BillingPeriod bp) => pricing[bp]?.saveLabel;

  String get monthlyPriceStr => priceStr(BillingPeriod.monthly);

  _Plan copy() => _Plan(id: '${id}_copy_${DateTime.now().millisecondsSinceEpoch}',
    name: '$name Copy', pricing: Map.of(pricing), enabled: enabled, accentColor: accentColor,
    recommended: false, userLimit: userLimit, moduleLimit: moduleLimit,
    aiCredits: aiCredits, storage: storage, supportKey: supportKey,
    posAccess: posAccess, modules: List.of(modules),
    offerEnabled: offerEnabled, offerLabel: offerLabel, offerDiscount: offerDiscount,
    offerExpiry: offerExpiry, customDurationLabel: customDurationLabel,
    customDurationPrice: customDurationPrice);

  int get tenantCount {
    final tp = switch (id) { 'starter' => TenantPlan.starter, 'professional' => TenantPlan.professional, 'enterprise' => TenantPlan.enterprise, _ => null };
    return tp == null ? 0 : mockTenants.where((t) => t.plan == tp).length;
  }
}

List<_Plan> _seedPlans() => [
  _Plan(id: 'starter', name: 'Starter', accentColor: AppColors.info,
    pricing: {
      BillingPeriod.monthly: const _BillingOption(29),
      BillingPeriod.semiAnnual: const _BillingOption(150, 'Save 14%'),
      BillingPeriod.annual: const _BillingOption(278, 'Save 20%'),
    },
    userLimit: 5, moduleLimit: 5, aiCredits: 1000, storage: '5 GB',
    supportKey: 'sap_support_email', posAccess: false,
    modules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'AI Chat']),
  _Plan(id: 'professional', name: 'Professional', accentColor: AppColors.primary, recommended: true,
    pricing: {
      BillingPeriod.monthly: const _BillingOption(79),
      BillingPeriod.semiAnnual: const _BillingOption(420, 'Save 12%'),
      BillingPeriod.annual: const _BillingOption(790, 'Save 17%'),
    },
    userLimit: 25, moduleLimit: 10, aiCredits: 5000, storage: '25 GB',
    supportKey: 'sap_support_priority', posAccess: true,
    modules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'POS', 'Inventory', 'Reports', 'Employees', 'AI Chat']),
  _Plan(id: 'enterprise', name: 'Enterprise', accentColor: AppColors.success,
    pricing: {
      BillingPeriod.monthly: const _BillingOption(199),
      BillingPeriod.semiAnnual: const _BillingOption(1050, 'Save 12%'),
      BillingPeriod.annual: const _BillingOption(1990, 'Save 17%'),
    },
    userLimit: 100, moduleLimit: 15, aiCredits: 20000, storage: '100 GB',
    supportKey: 'sap_support_dedicated', posAccess: true,
    modules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'POS', 'Inventory', 'Accounting', 'Reports', 'Employees', 'Roles', 'Departments', 'Teams', 'Settings', 'AI Chat']),
];

// ═══════════════════════════════════════════════════════════
//  Plans Screen (StatefulWidget)
// ═══════════════════════════════════════════════════════════

class SuperAdminPlansScreen extends StatefulWidget {
  const SuperAdminPlansScreen({super.key});
  @override
  State<SuperAdminPlansScreen> createState() => _SuperAdminPlansScreenState();
}

class _SuperAdminPlansScreenState extends State<SuperAdminPlansScreen> {
  late final List<_Plan> _plans = _seedPlans();
  BillingPeriod _selectedPeriod = BillingPeriod.monthly;

  int get _activeSubs => mockTenants.where((t) => t.status == TenantStatus.active).length;
  int get _trialCount => mockTenants.where((t) => t.status == TenantStatus.trial).length;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header + Add button ─────────────────────
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'sap_title'), style: AppTypography.headingLarge),
              const SizedBox(height: 4),
              Text(tr(context, 'sap_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _openDialog(null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr(context, 'sap_add_plan')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // ── Summary chips ──────────────────────────
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _SummaryChip(label: tr(context, 'sap_total_plans'), value: '${_plans.length}', color: AppColors.primary, icon: Icons.card_membership),
            _SummaryChip(label: tr(context, 'sap_active_subs'), value: '$_activeSubs', color: AppColors.success, icon: Icons.check_circle_outline),
            _SummaryChip(label: tr(context, 'sap_trial_tenants'), value: '$_trialCount', color: AppColors.warning, icon: Icons.hourglass_top),
            _SummaryChip(label: tr(context, 'sap_mrr'), value: '\$4,280', color: AppColors.info, icon: Icons.payments_outlined),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ── Billing period toggle ──────────────────
          Row(children: [
            Expanded(child: Text(tr(context, 'sap_plans_section'), style: AppTypography.labelLarge)),
            SegmentedButton<BillingPeriod>(
              segments: [
                ButtonSegment(value: BillingPeriod.monthly, label: Text(tr(context, 'sap_bp_monthly'), style: const TextStyle(fontSize: 11))),
                ButtonSegment(value: BillingPeriod.semiAnnual, label: Text(tr(context, 'sap_bp_semi'), style: const TextStyle(fontSize: 11))),
                ButtonSegment(value: BillingPeriod.annual, label: Text(tr(context, 'sap_bp_annual'), style: const TextStyle(fontSize: 11))),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (s) => setState(() => _selectedPeriod = s.first),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),

          // ── Plan cards ─────────────────────────────
          LayoutBuilder(builder: (_, c) {
            if (c.maxWidth > 750 && _plans.length <= 4) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: _plans.asMap().entries.map((e) => Expanded(child: Padding(
                  padding: EdgeInsetsDirectional.only(end: e.key < _plans.length - 1 ? AppSpacing.sm : 0),
                  child: _buildCard(e.value),
                ))).toList());
            }
            return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm,
              children: _plans.map((p) => SizedBox(width: c.maxWidth > 750 ? (c.maxWidth - AppSpacing.sm * 2) / 3 : double.infinity, child: _buildCard(p))).toList());
          }),
          const SizedBox(height: AppSpacing.xl),

          // ── Comparison table ───────────────────────
          Text(tr(context, 'sap_comparison'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),
          _buildComparison(),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  // ── Plan Card ──────────────────────────────────────────

  Widget _buildCard(_Plan p) {
    final statusColor = p.enabled ? AppColors.success : AppColors.neutral400;
    final statusKey = p.enabled ? 'sap_status_active' : 'sap_status_disabled';
    return Opacity(
      opacity: p.enabled ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.recommended ? p.accentColor.withValues(alpha: 0.4) : AppColors.divider, width: p.recommended ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.name, style: AppTypography.headingSmall)),
            if (p.recommended) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: p.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(tr(context, 'sap_recommended'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.accentColor)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(p.priceStr(_selectedPeriod), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: p.accentColor)),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_periodSuffix, style: AppTypography.caption.copyWith(color: AppColors.textTertiary))),
          ]),
          if (p.saveStr(_selectedPeriod) != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(p.saveStr(_selectedPeriod)!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success)),
            )),
          if (p.offerEnabled && p.offerLabel.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.accent.withValues(alpha: 0.2))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_offer, size: 12, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(p.offerLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                if (p.offerDiscount > 0) Text(' (-${p.offerDiscount}%)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                if (p.offerExpiry.isNotEmpty) Text(' · ${p.offerExpiry}', style: TextStyle(fontSize: 9, color: AppColors.accent.withValues(alpha: 0.7))),
              ]),
            )),
          if (p.customDurationLabel.isNotEmpty && p.customDurationPrice.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
              Icon(Icons.schedule, size: 12, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text('${p.customDurationLabel}: ${p.customDurationPrice}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ])),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(tr(context, statusKey), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor))),
            const SizedBox(width: 8),
            Icon(Icons.people_outline, size: 13, color: AppColors.textTertiary), const SizedBox(width: 3),
            Text('${p.tenantCount} ${tr(context, 'sap_tenants')}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ]),
          const Divider(height: 24),
          _LimitRow(icon: Icons.people, label: tr(context, 'sap_lim_users'), value: '${p.userLimit}'),
          _LimitRow(icon: Icons.extension, label: tr(context, 'sap_lim_modules'), value: '${p.moduleLimit}'),
          _LimitRow(icon: Icons.auto_awesome, label: tr(context, 'sap_lim_ai'), value: '${p.aiCredits}'),
          _LimitRow(icon: Icons.storage, label: tr(context, 'sap_lim_storage'), value: p.storage),
          _LimitRow(icon: Icons.point_of_sale, label: tr(context, 'sap_lim_pos'),
            value: p.posAccess ? tr(context, 'sap_yes') : tr(context, 'sap_no'),
            valueColor: p.posAccess ? AppColors.success : AppColors.neutral400),
          const Divider(height: 20),
          Text('${tr(context, 'sap_included_modules')} (${p.modules.length})', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            ...p.modules.take(4).map((m) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: p.accentColor.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(5)),
              child: Text(m, style: TextStyle(fontSize: 10, color: p.accentColor, fontWeight: FontWeight.w500)),
            )),
            if (p.modules.length > 4) Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(5)),
              child: Text('+${p.modules.length - 4} ${tr(context, 'sap_more')}', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            PopupMenuButton<String>(
              onSelected: (a) => _onAction(p, a),
              icon: Icon(Icons.more_horiz, size: 20, color: AppColors.neutral500),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sap_act_view'))])),
                PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sap_act_edit'))])),
                PopupMenuItem(value: 'duplicate', child: Row(children: [const Icon(Icons.copy_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sap_act_duplicate'))])),
                PopupMenuItem(value: 'toggle', child: Row(children: [
                  Icon(p.enabled ? Icons.block : Icons.check_circle_outline, size: 16, color: p.enabled ? AppColors.error : AppColors.success), const SizedBox(width: 8),
                  Text(p.enabled ? tr(context, 'sap_act_disable') : tr(context, 'sap_act_enable'), style: TextStyle(color: p.enabled ? AppColors.error : AppColors.success)),
                ])),
              ],
            ),
          ]),
        ]),
      ),
    );
  }

  String get _periodSuffix => switch (_selectedPeriod) {
    BillingPeriod.monthly => '/mo',
    BillingPeriod.semiAnnual => '/6mo',
    BillingPeriod.annual => '/yr',
  };

  // ── Actions ────────────────────────────────────────────

  void _onAction(_Plan p, String action) {
    switch (action) {
      case 'view': _snack('${tr(context, 'sap_act_view')}: ${p.name}');
      case 'edit': _openDialog(p);
      case 'duplicate': setState(() => _plans.add(p.copy())); _snack('${tr(context, 'sap_act_duplicate')}: ${p.name}');
      case 'toggle': setState(() => p.enabled = !p.enabled); _snack(p.enabled ? '${tr(context, 'sap_act_enable')}: ${p.name}' : '${tr(context, 'sap_act_disable')}: ${p.name}');
    }
  }

  // ── Add / Edit Dialog ──────────────────────────────────

  void _openDialog(_Plan? existing) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?.name ?? '');
    final moPC = TextEditingController(text: existing?.pricing[BillingPeriod.monthly]?.price.toStringAsFixed(0) ?? '49');
    final saPC = TextEditingController(text: existing?.pricing[BillingPeriod.semiAnnual]?.price.toStringAsFixed(0) ?? '260');
    final anPC = TextEditingController(text: existing?.pricing[BillingPeriod.annual]?.price.toStringAsFixed(0) ?? '470');
    final usersC = TextEditingController(text: '${existing?.userLimit ?? 10}');
    final modulesC = TextEditingController(text: '${existing?.moduleLimit ?? 5}');
    final aiC = TextEditingController(text: '${existing?.aiCredits ?? 1000}');
    final storageC = TextEditingController(text: existing?.storage ?? '10 GB');
    var selectedMods = Set<String>.from(existing?.modules ?? ['Dashboard', 'AI Chat']);
    var pos = existing?.posAccess ?? false;
    var supportIdx = existing == null ? 0 : ['sap_support_email', 'sap_support_priority', 'sap_support_dedicated'].indexOf(existing.supportKey).clamp(0, 2);
    // Offer
    var offerOn = existing?.offerEnabled ?? false;
    final offerLblC = TextEditingController(text: existing?.offerLabel ?? '');
    final offerPctC = TextEditingController(text: '${existing?.offerDiscount ?? 0}');
    final offerExpC = TextEditingController(text: existing?.offerExpiry ?? '');
    // Custom duration
    final custLblC = TextEditingController(text: existing?.customDurationLabel ?? '');
    final custPrC = TextEditingController(text: existing?.customDurationPrice ?? '');

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        title: Text(isEdit ? tr(context, 'sap_edit_plan') : tr(context, 'sap_add_plan')),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'sap_field_name'), border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          // Billing prices
          Text(tr(context, 'sap_billing_prices'), style: AppTypography.labelSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: moPC, decoration: InputDecoration(labelText: tr(context, 'sap_bp_monthly'), prefixText: '\$ ', border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))])),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: saPC, decoration: InputDecoration(labelText: tr(context, 'sap_bp_semi'), prefixText: '\$ ', border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))])),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: anPC, decoration: InputDecoration(labelText: tr(context, 'sap_bp_annual'), prefixText: '\$ ', border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))])),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: usersC, decoration: InputDecoration(labelText: tr(context, 'sap_lim_users'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: modulesC, decoration: InputDecoration(labelText: tr(context, 'sap_lim_modules'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: aiC, decoration: InputDecoration(labelText: tr(context, 'sap_lim_ai'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: storageC, decoration: InputDecoration(labelText: tr(context, 'sap_lim_storage'), border: const OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Text(tr(context, 'sap_lim_pos'), style: AppTypography.bodySmall),
            const Spacer(),
            Switch(value: pos, onChanged: (v) => setD(() => pos = v)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(tr(context, 'sap_cmp_support'), style: AppTypography.bodySmall),
            const Spacer(),
            SegmentedButton<int>(segments: [
              ButtonSegment(value: 0, label: Text(tr(context, 'sap_support_email'), style: const TextStyle(fontSize: 11))),
              ButtonSegment(value: 1, label: Text(tr(context, 'sap_support_priority'), style: const TextStyle(fontSize: 11))),
              ButtonSegment(value: 2, label: Text(tr(context, 'sap_support_dedicated'), style: const TextStyle(fontSize: 11))),
            ], selected: {supportIdx}, onSelectionChanged: (s) => setD(() => supportIdx = s.first)),
          ]),
          const SizedBox(height: 12),
          // Module picker
          Row(children: [
            Text('${tr(context, 'sap_included_modules')} (${selectedMods.length})', style: AppTypography.labelSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setD(() => selectedMods = Set.from(ErpModuleRegistry.all.map((m) => tr(context, m.labelKey)))),
              icon: const Icon(Icons.select_all, size: 14),
              label: Text(tr(context, 'sap_select_all'), style: const TextStyle(fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: Wrap(spacing: 6, runSpacing: 6,
              children: ErpModuleRegistry.all.map((m) {
                final label = tr(context, m.labelKey);
                final sel = selectedMods.contains(label);
                return FilterChip(
                  label: Text(label, style: TextStyle(fontSize: 11, color: sel ? AppColors.primary : AppColors.textSecondary)),
                  selected: sel,
                  onSelected: (v) => setD(() => v ? selectedMods.add(label) : selectedMods.remove(label)),
                  selectedColor: AppColors.primary.withValues(alpha: 0.1),
                  checkmarkColor: AppColors.primary,
                  side: BorderSide(color: sel ? AppColors.primary.withValues(alpha: 0.3) : AppColors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            )),
          ),
          const SizedBox(height: 16),
          // Offers section
          Text(tr(context, 'sap_offers'), style: AppTypography.labelSmall),
          const SizedBox(height: 6),
          Row(children: [
            Text(tr(context, 'sap_offer_enabled'), style: AppTypography.bodySmall),
            const Spacer(),
            Switch(value: offerOn, onChanged: (v) => setD(() => offerOn = v)),
          ]),
          if (offerOn) ...[
            const SizedBox(height: 8),
            TextField(controller: offerLblC, decoration: InputDecoration(labelText: tr(context, 'sap_offer_label'), border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: offerPctC, decoration: InputDecoration(labelText: tr(context, 'sap_offer_discount'), suffixText: '%', border: const OutlineInputBorder()),
                keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: offerExpC, decoration: InputDecoration(labelText: tr(context, 'sap_offer_expiry'), hintText: 'e.g. Dec 2026', border: const OutlineInputBorder()))),
            ]),
          ],
          const SizedBox(height: 16),
          // Custom duration section
          Text(tr(context, 'sap_custom_duration'), style: AppTypography.labelSmall),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: custLblC, decoration: InputDecoration(labelText: tr(context, 'sap_cust_label'), hintText: 'e.g. 2 Years', border: const OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: custPrC, decoration: InputDecoration(labelText: tr(context, 'sap_cust_price'), hintText: 'e.g. \$1,500', border: const OutlineInputBorder()))),
          ]),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'sap_cancel'))),
          FilledButton(onPressed: () {
            if (nameC.text.trim().isEmpty) return;
            final supportKeys = ['sap_support_email', 'sap_support_priority', 'sap_support_dedicated'];
            final mods = selectedMods.toList();
            final moPr = double.tryParse(moPC.text) ?? 49;
            final saPr = double.tryParse(saPC.text) ?? (moPr * 5.5);
            final anPr = double.tryParse(anPC.text) ?? (moPr * 10);
            String? saveLbl(double full, double discounted) {
              final pct = ((1 - discounted / full) * 100).round();
              return pct > 0 ? 'Save $pct%' : null;
            }
            final newPricing = {
              BillingPeriod.monthly: _BillingOption(moPr),
              BillingPeriod.semiAnnual: _BillingOption(saPr, saveLbl(moPr * 6, saPr)),
              BillingPeriod.annual: _BillingOption(anPr, saveLbl(moPr * 12, anPr)),
            };
            if (isEdit) {
              setState(() {
                existing.name = nameC.text.trim();
                existing.pricing = newPricing;
                existing.userLimit = int.tryParse(usersC.text) ?? existing.userLimit;
                existing.moduleLimit = int.tryParse(modulesC.text) ?? existing.moduleLimit;
                existing.aiCredits = int.tryParse(aiC.text) ?? existing.aiCredits;
                existing.storage = storageC.text.trim();
                existing.posAccess = pos;
                existing.supportKey = supportKeys[supportIdx];
                existing.modules = mods;
                existing.offerEnabled = offerOn;
                existing.offerLabel = offerLblC.text.trim();
                existing.offerDiscount = int.tryParse(offerPctC.text) ?? 0;
                existing.offerExpiry = offerExpC.text.trim();
                existing.customDurationLabel = custLblC.text.trim();
                existing.customDurationPrice = custPrC.text.trim();
              });
              _snack('${tr(context, 'sap_plan_updated')}: ${existing.name}');
            } else {
              final np = _Plan(
                id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
                name: nameC.text.trim(), pricing: newPricing,
                accentColor: [AppColors.info, AppColors.primary, AppColors.success, AppColors.accent, AppColors.warning][_plans.length % 5],
                userLimit: int.tryParse(usersC.text) ?? 10, moduleLimit: int.tryParse(modulesC.text) ?? 5,
                aiCredits: int.tryParse(aiC.text) ?? 1000, storage: storageC.text.trim(),
                supportKey: supportKeys[supportIdx], posAccess: pos, modules: mods,
                offerEnabled: offerOn, offerLabel: offerLblC.text.trim(),
                offerDiscount: int.tryParse(offerPctC.text) ?? 0, offerExpiry: offerExpC.text.trim(),
                customDurationLabel: custLblC.text.trim(), customDurationPrice: custPrC.text.trim());
              setState(() => _plans.add(np));
              _snack('${tr(context, 'sap_plan_created')}: ${np.name}');
            }
            Navigator.pop(ctx);
          }, child: Text(isEdit ? tr(context, 'sap_save') : tr(context, 'sap_create'))),
        ],
      );
    }));
  }

  // ── Comparison Table (dynamic) ─────────────────────────

  Widget _buildComparison() {
    final active = _plans.where((p) => p.enabled).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 400),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.neutral100),
          headingTextStyle: AppTypography.labelSmall, dataTextStyle: AppTypography.bodySmall, columnSpacing: 20,
          columns: [DataColumn(label: Text(tr(context, 'sap_cmp_feature'))), ...active.map((p) => DataColumn(label: Text(p.name)))],
          rows: [
            _cmpRow(tr(context, 'sap_field_price'), active.map((p) => p.priceStr(_selectedPeriod)).toList()),
            _cmpRow(tr(context, 'sap_lim_users'), active.map((p) => '${p.userLimit}').toList()),
            _cmpRow(tr(context, 'sap_lim_modules'), active.map((p) => '${p.moduleLimit}').toList()),
            _cmpRow(tr(context, 'sap_lim_ai'), active.map((p) => '${p.aiCredits}').toList()),
            _cmpRow(tr(context, 'sap_lim_pos'), active.map((p) => p.posAccess ? '✓' : '—').toList()),
            _cmpRow(tr(context, 'sap_cmp_support'), active.map((p) => tr(context, p.supportKey)).toList()),
          ],
        ),
      )),
    );
  }

  DataRow _cmpRow(String feature, List<String> vals) => DataRow(cells: [
    DataCell(Text(feature, style: AppTypography.labelSmall)),
    ...vals.map((v) => DataCell(Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
      color: v == '✓' ? AppColors.success : (v == '—' ? AppColors.neutral400 : AppColors.textPrimary))))),
  ]);
}

// ═══════════════════════════════════════════════════════════
//  Shared Widgets
// ═══════════════════════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final String label; final String value; final Color color; final IconData icon;
  const _SummaryChip({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)), child: Icon(icon, size: 15, color: color)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]),
    ]),
  );
}

class _LimitRow extends StatelessWidget {
  final IconData icon; final String label; final String value; final Color? valueColor;
  const _LimitRow({required this.icon, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
    Icon(icon, size: 14, color: AppColors.textTertiary), const SizedBox(width: 8),
    Expanded(child: Text(label, style: AppTypography.bodySmall)),
    Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary)),
  ]));
}
