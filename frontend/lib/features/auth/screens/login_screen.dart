// SmartBiz AI — Login screen.
// Real auth via backend API. Mock session shortcut preserved for dev.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/state/app_state.dart';
import '../../../core/api/api_exceptions.dart';
import '../widgets/auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  bool _remember = false;
  bool _obscure = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() { _emailC.dispose(); _passC.dispose(); super.dispose(); }

  Future<void> _handleLogin() async {
    final email = _emailC.text.trim();
    final password = _passC.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = tr(context, 'auth_fields_required'));
      return;
    }

    setState(() { _loading = true; _errorMessage = null; });

    try {
      final app = context.read<AppState>();
      await app.signInWithEmailPassword(email, password);

      if (!mounted) return;

      // Route based on session state.
      if (app.isSuperAdmin) {
        context.go('/super-admin');
      } else if (app.isOnboardingCompleted) {
        context.go('/dashboard');
      } else {
        context.go('/onboarding');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errorMessage = e.firstMessage ?? e.message);
    } on NetworkException {
      if (mounted) {
        setState(() => _errorMessage = tr(context, 'auth_network_error'));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = tr(context, 'auth_unexpected_error'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      children: [
        Text(tr(context, 'auth_login_title'), style: AppTypography.headingMedium),
        const SizedBox(height: 6),
        Text(tr(context, 'auth_login_sub'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 28),

        // Error banner
        if (_errorMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Email
        TextField(
          controller: _emailC,
          keyboardType: TextInputType.emailAddress,
          enabled: !_loading,
          textInputAction: TextInputAction.next,
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
        const SizedBox(height: 14),

        // Password
        TextField(
          controller: _passC,
          obscureText: _obscure,
          enabled: !_loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
          decoration: InputDecoration(
            labelText: tr(context, 'auth_password'),
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
          ),
        ),
        const SizedBox(height: 10),

        // Remember + Forgot
        Row(children: [
          SizedBox(width: 22, height: 22, child: Checkbox(
            value: _remember, onChanged: _loading ? null : (v) => setState(() => _remember = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )),
          const SizedBox(width: 6),
          Expanded(child: Text(tr(context, 'auth_remember'), style: AppTypography.caption)),
          TextButton(
            onPressed: _loading ? null : () => context.go('/forgot-password'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(tr(context, 'auth_forgot'), style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 20),

        // Login button
        SizedBox(width: double.infinity, height: 46, child: FilledButton(
          onPressed: _loading ? null : _handleLogin,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(tr(context, 'auth_login_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
        const SizedBox(height: 18),

        // Register link
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(tr(context, 'auth_no_account'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          TextButton(
            onPressed: _loading ? null : () => context.go('/register'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero),
            child: Text(tr(context, 'auth_create_account'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ]),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),

        // Dev shortcut
        TextButton.icon(
          onPressed: _loading ? null : () => context.go('/auth/mock-session'),
          icon: const Icon(Icons.developer_mode, size: 14, color: AppColors.neutral400),
          label: Text(tr(context, 'auth_dev_shortcut'), style: TextStyle(fontSize: 11, color: AppColors.neutral400)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
        ),
      ],
    );
  }
}
