// SmartBiz AI — Payments list screen (real API).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/pages/widgets/generic_page_state.dart';
import '../payments_state.dart';
import '../models/payment_models.dart';

class PaymentsListScreen extends StatefulWidget {
  const PaymentsListScreen({super.key});

  @override
  State<PaymentsListScreen> createState() => _PaymentsListScreenState();
}

class _PaymentsListScreenState extends State<PaymentsListScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<PaymentsState>();
    if (state.filtered.isEmpty && !state.loading) {
      Future.microtask(() => state.loadPayments(refresh: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PaymentsState>();
    final isMobile = Responsive.isMobile(context);
    final payments = state.filtered;

    return Column(
      children: [
        // ── Header ──────────────────────────────────────
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'pay_title'), style: AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.md),
              _SummaryRow(state: state),
              const SizedBox(height: AppSpacing.md),
              TextField(
                onChanged: state.setSearch,
                textDirection: Directionality.of(context),
                decoration: InputDecoration(
                  hintText: tr(context, 'pay_search'),
                  hintTextDirection: Directionality.of(context),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _StatusChip(label: tr(context, 'inv_all'), selected: state.statusFilter == null, onTap: () => state.setStatusFilter(null)),
                    ...PaymentStatus.values.map((s) {
                      final key = switch (s) {
                        PaymentStatus.completed => 'pay_status_completed',
                        PaymentStatus.pending   => 'pay_status_pending',
                        PaymentStatus.failed    => 'pay_status_failed',
                        PaymentStatus.refunded  => 'pay_status_refunded',
                      };
                      return _StatusChip(label: tr(context, key), selected: state.statusFilter == s, onTap: () => state.setStatusFilter(s));
                    }),
                  ],
                ),
              ),
            ],
          ),
          )),
        ),

        // ── Payment list ────────────────────────────────
        Expanded(
          child: _buildContent(context, state, payments, isMobile),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, PaymentsState state, List<Payment> payments, bool isMobile) {
    // Loading
    if (state.loading && payments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (state.error != null && payments.isEmpty) {
      return GenericPageState.empty(
        title: tr(context, 'pay_load_failed'),
        message: state.error!,
        icon: Icons.error_outline,
        actionLabel: tr(context, 'retry'),
        onAction: () => state.loadPayments(refresh: true),
      );
    }

    // Empty
    if (payments.isEmpty) {
      return GenericPageState.empty(
        title: tr(context, 'pay_empty'),
        message: tr(context, 'pay_empty_hint'),
        icon: Icons.payments_outlined,
      );
    }

    // List
    return RefreshIndicator(
      onRefresh: () => state.loadPayments(refresh: true),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: ListView.separated(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          itemCount: payments.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => _PaymentRow(payment: payments[i]),
        ),
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Summary Cards Row
// ═══════════════════════════════════════════════════════════

class _SummaryRow extends StatelessWidget {
  final PaymentsState state;
  const _SummaryRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SummaryCard(
            label: tr(context, 'pay_received'),
            value: '\$${state.totalReceived.toStringAsFixed(0)}',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          _SummaryCard(
            label: tr(context, 'pay_pending'),
            value: '\$${state.totalPending.toStringAsFixed(0)}',
            icon: Icons.schedule,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          _SummaryCard(
            label: tr(context, 'pay_failed_label'),
            value: '\$${state.totalFailed.toStringAsFixed(0)}',
            icon: Icons.error_outline,
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              Text(value, style: AppTypography.labelLarge.copyWith(color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Status Chip
// ═══════════════════════════════════════════════════════════

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primarySurface,
        checkmarkColor: AppColors.primary,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Payment Row Card
// ═══════════════════════════════════════════════════════════

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _methodColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_methodIcon, size: 20, color: _methodColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.referenceNumber, style: AppTypography.labelLarge),
                const SizedBox(height: 2),
                if (payment.customerName.isNotEmpty)
                  Text(payment.customerName, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                if (payment.invoiceNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${tr(context, 'pay_invoice_ref')}: ${payment.invoiceNumber!.substring(0, 8)}...',
                      style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${payment.amount.toStringAsFixed(2)}', style: AppTypography.labelLarge),
              const SizedBox(height: 4),
              _PaymentStatusBadge(status: payment.status),
              const SizedBox(height: 2),
              Text(
                '${payment.date.day}/${payment.date.month}/${payment.date.year}',
                style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData get _methodIcon => switch (payment.method) {
    PaymentMethod.cash     => Icons.money,
    PaymentMethod.card     => Icons.credit_card,
    PaymentMethod.transfer => Icons.swap_horiz,
    PaymentMethod.online   => Icons.language,
  };

  Color get _methodColor => switch (payment.method) {
    PaymentMethod.cash     => AppColors.success,
    PaymentMethod.card     => AppColors.primary,
    PaymentMethod.transfer => AppColors.info,
    PaymentMethod.online   => AppColors.warning,
  };
}

// ═══════════════════════════════════════════════════════════
//  Payment Status Badge
// ═══════════════════════════════════════════════════════════

class _PaymentStatusBadge extends StatelessWidget {
  final PaymentStatus status;
  const _PaymentStatusBadge({required this.status});

  Color get _color => switch (status) {
    PaymentStatus.completed => AppColors.success,
    PaymentStatus.pending   => AppColors.warning,
    PaymentStatus.failed    => AppColors.error,
    PaymentStatus.refunded  => AppColors.neutral500,
  };

  String _key(BuildContext context) => switch (status) {
    PaymentStatus.completed => 'pay_status_completed',
    PaymentStatus.pending   => 'pay_status_pending',
    PaymentStatus.failed    => 'pay_status_failed',
    PaymentStatus.refunded  => 'pay_status_refunded',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(tr(context, _key(context)), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _color)),
  );
}
