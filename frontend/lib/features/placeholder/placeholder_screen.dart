// SmartBiz AI — Placeholder screen with localization.
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/widgets/common_widgets.dart';

class PlaceholderScreen extends StatelessWidget {
  final String titleKey;
  final IconData icon;
  final String? subtitleKey;

  const PlaceholderScreen({
    super.key,
    required this.titleKey,
    required this.icon,
    this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: tr(context, titleKey),
      subtitle: tr(context, subtitleKey ?? 'coming_soon'),
    );
  }
}
