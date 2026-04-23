/// SmartBiz AI — Placeholder screen for unmapped routes.
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/common_widgets.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle = 'This feature is coming soon.',
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
    );
  }
}
