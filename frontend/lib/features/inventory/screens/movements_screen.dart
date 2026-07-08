// SmartBiz AI — Stock movements screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/pages/widgets/generic_page_state.dart';
import '../inventory_state.dart';
import '../widgets/inventory_widgets.dart';

class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<InventoryState>();
    if (state.movements.isEmpty && !state.loading) {
      Future.microtask(() => state.loadAll(refresh: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryState>();
    final mvs = state.movements;

    // Loading
    if (state.loading && mvs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (state.error != null && mvs.isEmpty) {
      return GenericPageState.empty(
        title: tr(context, 'stk_load_failed'),
        message: state.error!,
        icon: Icons.error_outline,
        actionLabel: tr(context, 'retry'),
        onAction: () => state.loadAll(refresh: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => state.loadAll(refresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
      ),
    );
  }
}
