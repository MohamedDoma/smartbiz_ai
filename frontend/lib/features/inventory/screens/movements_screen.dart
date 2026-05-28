// SmartBiz AI — Stock movements screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../inventory_state.dart';
import '../widgets/inventory_widgets.dart';

class MovementsScreen extends StatelessWidget {
  const MovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryState>();
    final mvs = state.movements;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/inventory'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'stk_movements'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(tr(context, 'stk_mv_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xl),
          if (mvs.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: Text(tr(context, 'stk_no_movements'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary))))
          else
            ...mvs.map((m) => MovementTile(movement: m)),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}
