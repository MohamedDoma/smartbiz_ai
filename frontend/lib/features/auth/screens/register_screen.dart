// SmartBiz AI — Register screen.
// Collects owner info + workspace details, calls real backend register API.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/state/app_state.dart';
import '../../../core/api/api_exceptions.dart';
import '../widgets/auth_scaffold.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  final _bizNameC = TextEditingController();
  bool _obscure = true;
  String _bizSize = 'small';
  String _bizType = 'general';
  bool _loading = false;
  String? _errorMessage;

  /// Regex matching backend: digits, +, -, spaces, parens, dot
  static final _phoneRegex = RegExp(r'^[0-9+\-\s().]+$');

  @override
  void dispose() {
    _nameC.dispose(); _emailC.dispose(); _phoneC.dispose();
    _passC.dispose(); _confirmC.dispose(); _bizNameC.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await context.read<AppState>().registerBusinessOwnerReal(
        fullName: _nameC.text.trim(),
        email: _emailC.text.trim(),
        phoneNumber: _phoneC.text.trim(),
        password: _passC.text,
        passwordConfirmation: _confirmC.text,
        workspaceName: _bizNameC.text.trim(),
        businessSize: _bizSize,
        businessType: _bizType,
      );

      if (!mounted) return;
      context.go('/onboarding');
    } on ValidationException catch (e) {
      setState(() {
        _errorMessage = e.firstMessage ?? tr(context, 'reg_validation_failed');
      });
    } on AuthException {
      setState(() {
        _errorMessage = tr(context, 'reg_failed');
      });
    } on NetworkException {
      setState(() {
        _errorMessage = tr(context, 'auth_network_error');
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message.isNotEmpty
            ? e.message
            : tr(context, 'auth_unexpected_error');
      });
    } catch (_) {
      setState(() {
        _errorMessage = tr(context, 'auth_unexpected_error');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      children: [
        Text(tr(context, 'auth_register_title'), style: AppTypography.headingMedium),
        const SizedBox(height: 6),
        Text(tr(context, 'auth_register_sub'),
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center),
        const SizedBox(height: 24),

        // ── Error banner ──
        if (_errorMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        Form(
          key: _formKey,
          child: Column(children: [
            // ── Section: Your Account ──
            _sectionLabel(context, 'reg_section_account'),

            // Full name
            _textField(
              controller: _nameC,
              label: tr(context, 'auth_full_name'),
              hint: 'Mohamed Doma',
              icon: Icons.person_outline,
              validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'reg_required') : null,
            ),
            const SizedBox(height: 10),

            // Email
            _textField(
              controller: _emailC,
              label: tr(context, 'auth_email'),
              hint: 'name@company.com',
              icon: Icons.email_outlined,
              type: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return tr(context, 'reg_required');
                if (!v.contains('@') || !v.contains('.')) return tr(context, 'reg_email_invalid');
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Phone number
            _textField(
              controller: _phoneC,
              label: tr(context, 'reg_phone_label'),
              hint: '+218 91-234-5678',
              icon: Icons.phone_outlined,
              type: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return tr(context, 'reg_phone_required');
                final trimmed = v.trim();
                if (trimmed.length < 7) return tr(context, 'reg_phone_invalid');
                if (trimmed.length > 30) return tr(context, 'reg_phone_invalid');
                if (!_phoneRegex.hasMatch(trimmed)) return tr(context, 'reg_phone_invalid');
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Password
            _textField(
              controller: _passC,
              label: tr(context, 'auth_password'),
              icon: Icons.lock_outline,
              obscure: _obscure,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return tr(context, 'reg_required');
                if (v.length < 8) return tr(context, 'reg_pass_short');
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Confirm password
            _textField(
              controller: _confirmC,
              label: tr(context, 'auth_confirm_pass'),
              icon: Icons.lock_outline,
              obscure: true,
              validator: (v) {
                if (v == null || v.isEmpty) return tr(context, 'reg_required');
                if (v != _passC.text) return tr(context, 'reg_pass_mismatch');
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Section: Your Business ──
            _sectionLabel(context, 'reg_section_business'),

            // Business name
            _textField(
              controller: _bizNameC,
              label: tr(context, 'auth_biz_name'),
              hint: tr(context, 'auth_biz_hint'),
              icon: Icons.business_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'reg_required') : null,
            ),
            const SizedBox(height: 10),

            // Business size
            _dropdownField(
              label: tr(context, 'reg_biz_size'),
              icon: Icons.groups_outlined,
              value: _bizSize,
              items: [
                DropdownMenuItem(value: 'solo', child: Text(tr(context, 'reg_size_solo'))),
                DropdownMenuItem(value: 'small', child: Text(tr(context, 'reg_size_small'))),
                DropdownMenuItem(value: 'medium', child: Text(tr(context, 'reg_size_medium'))),
                DropdownMenuItem(value: 'large', child: Text(tr(context, 'reg_size_large'))),
              ],
              onChanged: (v) => setState(() => _bizSize = v ?? 'small'),
            ),
            const SizedBox(height: 10),

            // Business type
            _dropdownField(
              label: tr(context, 'reg_biz_type'),
              icon: Icons.category_outlined,
              value: _bizType,
              items: [
                DropdownMenuItem(value: 'general', child: Text(tr(context, 'reg_type_general'))),
                DropdownMenuItem(value: 'retail', child: Text(tr(context, 'reg_type_retail'))),
                DropdownMenuItem(value: 'restaurant', child: Text(tr(context, 'reg_type_restaurant'))),
                DropdownMenuItem(value: 'services', child: Text(tr(context, 'reg_type_services'))),
                DropdownMenuItem(value: 'manufacturing', child: Text(tr(context, 'reg_type_manufacturing'))),
                DropdownMenuItem(value: 'ecommerce', child: Text(tr(context, 'reg_type_ecommerce'))),
              ],
              onChanged: (v) => setState(() => _bizType = v ?? 'general'),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Register button
        SizedBox(width: double.infinity, height: 46, child: FilledButton(
          onPressed: _loading ? null : _handleRegister,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(tr(context, 'auth_register_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
        const SizedBox(height: 16),

        // Login link
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(tr(context, 'auth_have_account'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          TextButton(
            onPressed: () => context.go('/login'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: Size.zero),
            child: Text(tr(context, 'auth_sign_in'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  Widget _sectionLabel(BuildContext context, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(tr(context, key),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary, letterSpacing: 0.5, fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller, keyboardType: type, obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        filled: true, fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true, fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      dropdownColor: AppColors.surface,
      style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
    );
  }
}
