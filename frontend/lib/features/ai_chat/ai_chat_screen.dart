/// SmartBiz AI — AI Chat placeholder.
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';

class AiChatScreen extends StatelessWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Chat area
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 40, color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('SmartBiz AI Assistant', style: AppTypography.headingLarge),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                  child: Text(
                    'Ask me anything about your business.\nI can read data, create records, and suggest improvements.',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    _SuggestionChip(label: 'Show revenue this month'),
                    _SuggestionChip(label: 'Find overdue invoices'),
                    _SuggestionChip(label: 'Low stock products'),
                    _SuggestionChip(label: 'Create a new invoice'),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Ask SmartBiz AI...',
                    prefixIcon: const Icon(Icons.auto_awesome_outlined, color: AppColors.accent, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FloatingActionButton.small(
                onPressed: () {},
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  const _SuggestionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () {},
      backgroundColor: AppColors.neutral100,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
