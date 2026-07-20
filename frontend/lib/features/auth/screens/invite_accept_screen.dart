// SmartBiz AI — Invite Accept Screen (real API).
// Employee opens /invite/:token → preview → completes profile → joins workspace.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/api/workspace_invite_models.dart';
import '../../../core/state/app_state.dart';
import '../widgets/auth_scaffold.dart';

class InviteAcceptScreen extends StatefulWidget {
  final String token;
  const InviteAcceptScreen({super.key, required this.token});
  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  bool _obscure = true;

  // Preview data
  InvitePreview? _preview;
  bool _loadingPreview = true;
  String? _previewError;

  // Accept state
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() { _loadingPreview = true; _previewError = null; });
    try {
      final appState = context.read<AppState>();
      final preview = await appState.inviteService.previewInvite(widget.token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
        if (preview.fullName != null && preview.fullName!.isNotEmpty) {
          _nameC.text = preview.fullName!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = _friendlyError(e);
      });
    }
  }

  Future<void> _handleAccept() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _submitting = true; _submitError = null; });

    try {
      await context.read<AppState>().acceptEmployeeInviteReal(
        token: widget.token,
        fullName: _nameC.text.trim(),
        phoneNumber: _phoneC.text.trim(),
        password: _passC.text,
        passwordConfirmation: _confirmC.text,
      );
      if (!mounted) return;

      final appState = context.read<AppState>();
      if (appState.isOnboardingCompleted) {
        context.go('/dashboard');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = _friendlyError(e);
      });
    }
  }

  String _friendlyError(dynamic e) {
    if (e is ValidationException) {
      final msgs = e.errors.values.expand((v) => v).toList();
      return msgs.isNotEmpty ? msgs.first : e.message;
    }
    if (e is ApiException) return e.message;
    return e.toString().replaceAll('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    // Loading preview
    if (_loadingPreview) {
      return const AuthScaffold(
        children: [
          SizedBox(height: 60),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
        ],
      );
    }

    // Preview error (invalid/expired/revoked token)
    if (_previewError != null) {
      return AuthScaffold(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text(tr(context, 'invite_invalid'), style: AppTypography.headingMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(_previewError!, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 44, child: OutlinedButton(
            onPressed: () => context.go('/login'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(tr(context, 'invite_go_login')),
          )),
        ],
      );
    }

    final preview = _preview!;

    return AuthScaffold(
      children: [
        // Invite badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.mail_outline, size: 14, color: AppColors.info),
            const SizedBox(width: 6),
            Text(tr(context, 'invite_badge'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.info)),
          ]),
        ),
        const SizedBox(height: 16),
        Text(tr(context, 'invite_title'), style: AppTypography.headingMedium),
        const SizedBox(height: 6),
        Text(tr(context, 'invite_sub'),
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center),
        const SizedBox(height: 20),

        // Invite info card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoRow(Icons.business_outlined, tr(context, 'invite_workspace'), preview.workspaceName ?? '—'),
            const SizedBox(height: 8),
            _infoRow(Icons.email_outlined, tr(context, 'invite_email'), preview.email),
            const SizedBox(height: 8),
            _infoRow(Icons.badge_outlined, tr(context, 'invite_role'), preview.roleNamesDisplay.isNotEmpty ? preview.roleNamesDisplay : preview.roleName ?? '—'),
            if (preview.jobTitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.work_outline, tr(context, 'emp_job_title'), preview.jobTitle!),
            ],
            if (preview.departmentName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.account_tree_outlined, tr(context, 'emp_department'), preview.departmentName!),
            ],
            if (preview.teamName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.groups_outlined, tr(context, 'emp_team'), preview.teamName!),
            ],
          ]),
        ),
        const SizedBox(height: 22),

        // Error banner
        if (_submitError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(child: Text(_submitError!, style: TextStyle(fontSize: 12, color: AppColors.error))),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Form
        Form(
          key: _formKey,
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(tr(context, 'invite_section_profile'),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary, letterSpacing: 0.5, fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Full name
            TextFormField(
              controller: _nameC,
              validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'reg_required') : null,
              decoration: _inputDeco(tr(context, 'auth_full_name'), Icons.person_outline),
            ),
            const SizedBox(height: 10),

            // Phone number
            TextFormField(
              controller: _phoneC,
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return tr(context, 'reg_required');
                if (v.trim().length < 7) return tr(context, 'invite_phone_short');
                return null;
              },
              decoration: _inputDeco(tr(context, 'invite_phone'), Icons.phone_outlined),
            ),
            const SizedBox(height: 10),

            // Password
            TextFormField(
              controller: _passC, obscureText: _obscure,
              validator: (v) {
                if (v == null || v.isEmpty) return tr(context, 'reg_required');
                if (v.length < 8) return tr(context, 'reg_pass_short');
                return null;
              },
              decoration: _inputDeco(tr(context, 'auth_password'), Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Confirm password
            TextFormField(
              controller: _confirmC, obscureText: true,
              validator: (v) {
                if (v == null || v.isEmpty) return tr(context, 'reg_required');
                if (v != _passC.text) return tr(context, 'reg_pass_mismatch');
                return null;
              },
              decoration: _inputDeco(tr(context, 'auth_confirm_pass'), Icons.lock_outline),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Accept button
        SizedBox(width: double.infinity, height: 46, child: _submitting
            ? const Center(child: CircularProgressIndicator())
            : FilledButton.icon(
                onPressed: _handleAccept,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(tr(context, 'invite_accept_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
        const SizedBox(height: 14),

        // Login link
        TextButton(
          onPressed: () => context.go('/login'),
          child: Text(tr(context, 'invite_have_account'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]);
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true, fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.error)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
