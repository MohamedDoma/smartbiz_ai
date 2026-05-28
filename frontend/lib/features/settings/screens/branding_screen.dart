// SmartBiz AI — Branding settings screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../settings_state.dart';

class BrandingScreen extends StatelessWidget {
  const BrandingScreen({super.key});

  static const _primaries = [
    Color(0xFF1A56DB), Color(0xFF059669), Color(0xFF7C3AED),
    Color(0xFFDC2626), Color(0xFFD97706), Color(0xFF0891B2),
    Color(0xFF4F46E5), Color(0xFFDB2777),
  ];
  static const _accents = [
    Color(0xFF7C3AED), Color(0xFFF59E0B), Color(0xFF10B981),
    Color(0xFFEC4899), Color(0xFF3B82F6), Color(0xFF8B5CF6),
  ];

  void _showLogoSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context, 'fb_logo_coming')),
      backgroundColor: AppColors.info,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsState>();
    final b = state.branding;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'set_branding'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.xl),
          Text(tr(context, 'brand_primary'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 10, runSpacing: 10, children: _primaries.map((c) => _Dot(color: c, sel: b.primaryColor.value == c.value, onTap: () => state.setPrimaryColor(c))).toList()),
          const SizedBox(height: AppSpacing.xl),
          Text(tr(context, 'brand_accent'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 10, runSpacing: 10, children: _accents.map((c) => _Dot(color: c, sel: b.accentColor.value == c.value, onTap: () => state.setAccentColor(c))).toList()),
          const SizedBox(height: AppSpacing.xl),
          Text(tr(context, 'brand_logo'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: () => _showLogoSnackbar(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(width: double.infinity, height: 100, decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.cloud_upload_outlined, size: 28, color: AppColors.neutral400),
                const SizedBox(height: 4),
                Text(tr(context, 'brand_upload'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ])),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(tr(context, 'brand_preview'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _Preview(state: state),
          const SizedBox(height: AppSpacing.xl),

          // Save branding button
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr(context, 'fb_brand_saved')),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            },
            icon: const Icon(Icons.save, size: 18),
            label: Text(tr(context, 'fb_save')),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.cloud_off_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(child: Text(tr(context, 'fb_local_only'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary))),
            ]),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color; final bool sel; final VoidCallback onTap;
  const _Dot({required this.color, required this.sel, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
      border: sel ? Border.all(color: Colors.white, width: 3) : null,
      boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)] : null),
      child: sel ? const Icon(Icons.check, size: 16, color: Colors.white) : null));
}

class _Preview extends StatelessWidget {
  final SettingsState state;
  const _Preview({required this.state});
  @override
  Widget build(BuildContext context) {
    final b = state.branding;
    return Container(padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(color: b.primaryColor, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [const Icon(Icons.diamond, size: 18, color: Colors.white), const SizedBox(width: AppSpacing.sm),
            Text(state.workspace.companyName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))])),
        const SizedBox(height: AppSpacing.md),
        Text(tr(context, 'brand_preview_note'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]));
  }
}
