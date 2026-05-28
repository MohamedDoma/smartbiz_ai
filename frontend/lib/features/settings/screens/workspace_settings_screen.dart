// SmartBiz AI — Workspace settings screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../settings_state.dart';

class WorkspaceSettingsScreen extends StatelessWidget {
  const WorkspaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsState>();
    final ws = state.workspace;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(tr(context, 'set_workspace'), style: AppTypography.headingLarge)),
            ]),
            const SizedBox(height: AppSpacing.xl),

            _EditField(label: tr(context, 'ws_company_name'), value: ws.companyName, onChanged: state.updateCompanyName, context: context),
            const SizedBox(height: AppSpacing.md),
            _EditField(label: tr(context, 'ws_industry'), value: ws.industry, onChanged: state.updateIndustry, context: context),
            const SizedBox(height: AppSpacing.md),
            _EditField(label: tr(context, 'ws_timezone'), value: ws.timezone, onChanged: state.updateTimezone, context: context),
            const SizedBox(height: AppSpacing.md),
            _EditField(label: tr(context, 'ws_currency'), value: ws.currency, onChanged: state.updateCurrency, context: context),
            const SizedBox(height: AppSpacing.xl),

            // Language note
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'ws_lang_note'), style: AppTypography.caption.copyWith(color: AppColors.info))),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Save button
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(tr(context, 'fb_ws_saved')),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              },
              icon: const Icon(Icons.save, size: 18),
              label: Text(tr(context, 'fb_save')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),

            // Backend note
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
        ),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final String label; final String value; final ValueChanged<String> onChanged; final BuildContext context;
  const _EditField({required this.label, required this.value, required this.onChanged, required this.context});
  @override
  Widget build(BuildContext _) {
    final c = TextEditingController(text: value);
    return TextField(
      controller: c, textDirection: Directionality.of(context),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
    );
  }
}
