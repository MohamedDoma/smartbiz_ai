// SmartBiz AI — Shared auth layout scaffold.
// Provides consistent branding + centered card for login/register/forgot.
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class AuthScaffold extends StatelessWidget {
  final List<Widget> children;
  const AuthScaffold({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Logo
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text('SmartBiz AI', style: AppTypography.labelLarge.copyWith(color: AppColors.primary, letterSpacing: 0.5)),
            const SizedBox(height: 24),

            // Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ]),
        ),
      ))),
    );
  }
}
