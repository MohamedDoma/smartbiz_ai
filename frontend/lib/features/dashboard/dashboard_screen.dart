/// SmartBiz AI — Dashboard placeholder with metric cards.
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive.dart';
import '../../shared/widgets/common_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = Responsive.isDesktop(context) ? 4 : Responsive.isTablet(context) ? 3 : 2;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome
          Text('Good morning 👋', style: AppTypography.headingLarge),
          const SizedBox(height: AppSpacing.xs),
          Text('Here\'s what\'s happening in your business today.', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xl),

          // Metrics
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.base,
            crossAxisSpacing: AppSpacing.base,
            childAspectRatio: 1.6,
            children: const [
              MetricCard(icon: Icons.attach_money,     label: 'Revenue (30d)',   value: '—', delta: '—'),
              MetricCard(icon: Icons.receipt_long,      label: 'Invoices',        value: '—', delta: '—'),
              MetricCard(icon: Icons.people_outline,    label: 'Customers',       value: '—'),
              MetricCard(icon: Icons.inventory_2,       label: 'Products',        value: '—'),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // AI Advisor section
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 20, color: AppColors.accent),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('AI Advisor', style: AppTypography.headingSmall),
                      const Spacer(),
                      StatusBadge.info('3 new'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Your AI advisor has new recommendations for your business. Review them to improve operations.',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('View Recommendations'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Recent activity
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent Activity', style: AppTypography.headingSmall),
                  const SizedBox(height: AppSpacing.md),
                  _ActivityItem(icon: Icons.receipt, title: 'Invoice #INV-042 created', time: 'Just now', color: AppColors.primary),
                  _ActivityItem(icon: Icons.payment, title: 'Payment received — \$1,250', time: '2 hours ago', color: AppColors.success),
                  _ActivityItem(icon: Icons.inventory, title: 'Low stock alert — Widget Pro', time: '5 hours ago', color: AppColors.warning),
                  _ActivityItem(icon: Icons.person_add, title: 'New customer — Acme Corp', time: 'Yesterday', color: AppColors.info),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String time;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title, style: AppTypography.bodyMedium)),
          Text(time, style: AppTypography.caption),
        ],
      ),
    );
  }
}
