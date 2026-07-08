// SmartBiz AI — Forgot Password screen.
// Frontend-only mock. Real flow will send a reset email.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailC = TextEditingController();
  bool _sent = false;

  @override
  void dispose() { _emailC.dispose(); super.dispose(); }

  void _handleSend() {
    setState(() => _sent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'auth_reset_sent')), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      children: [
        const Icon(Icons.lock_reset_outlined, size: 48, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(tr(context, 'auth_forgot_title'), style: AppTypography.headingMedium),
        const SizedBox(height: 6),
        Text(tr(context, 'auth_forgot_sub'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 28),

        if (!_sent) ...[
          // Email
          TextField(
            controller: _emailC,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: tr(context, 'auth_email'),
              hintText: 'name@company.com',
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
              filled: true, fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(width: double.infinity, height: 46, child: FilledButton(
            onPressed: _handleSend,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(tr(context, 'auth_send_reset'), style: const TextStyle(fontWeight: FontWeight.w600)),
          )),
        ] else ...[
          // Confirmation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(context, 'auth_reset_confirm'), style: AppTypography.bodySmall.copyWith(color: AppColors.success))),
            ]),
          ),
        ],

        const SizedBox(height: 22),

        // Back to login
        TextButton.icon(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: Text(tr(context, 'auth_back_login'), style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
