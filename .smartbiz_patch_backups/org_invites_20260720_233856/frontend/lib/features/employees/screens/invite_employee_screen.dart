// SmartBiz AI — Invite employee screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/api/workspace_invite_models.dart';
import '../../../core/api/workspace_invite_service.dart';
import '../../../core/state/app_state.dart';

class InviteEmployeeScreen extends StatefulWidget {
  const InviteEmployeeScreen({super.key});
  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _selectedRoleIds = <String>{};
  String? _primaryRoleId;

  // State
  List<WorkspaceRoleSummary> _roles = [];
  List<WorkspaceInvitation> _invites = [];
  bool _loadingRoles = true;
  bool _loadingInvites = true;
  bool _submitting = false;
  String? _error;

  // Created invite link
  String? _createdInviteLink;

  late final WorkspaceInviteService _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<AppState>().inviteService;
    _loadData();
  }

  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadRoles(), _loadInvites()]);
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await _service.listWorkspaceRoles();
      if (!mounted) return;
      setState(() {
        _roles = roles.where((r) => r.roleKey != 'owner').toList();
        _loadingRoles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingRoles = false; _error = _friendlyError(e); });
    }
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    try {
      final invites = await _service.listInvites();
      if (!mounted) return;
      setState(() { _invites = invites; _loadingInvites = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingInvites = false);
    }
  }

  Future<void> _send() async {
    if (_emailC.text.trim().isEmpty || _selectedRoleIds.isEmpty) return;

    setState(() { _submitting = true; _error = null; _createdInviteLink = null; });

    try {
      final invite = await _service.createInvite(CreateWorkspaceInvitationPayload(
        email: _emailC.text.trim(),
        fullName: _nameC.text.trim().isNotEmpty ? _nameC.text.trim() : null,
        roleIds: _selectedRoleIds.toList(),
        primaryRoleId: _primaryRoleId ?? _selectedRoleIds.first,
      ));

      if (!mounted) return;

      final token = invite.token ?? '';
      // Build URL: use window.location.origin if web, or localhost fallback
      final baseUrl = 'http://localhost:8080';
      final link = token.isNotEmpty ? '$baseUrl/#/invite/$token' : '';

      setState(() {
        _submitting = false;
        _createdInviteLink = link;
      });

      // Refresh invites list
      _loadInvites();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'emp_invite_created')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _revokeInvite(String id) async {
    try {
      await _service.revokeInvite(id);
      if (!mounted) return;
      _loadInvites();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'emp_invite_revoked')),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_friendlyError(e)),
        backgroundColor: AppColors.error,
      ));
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
    final isMobile = Responsive.isMobile(context);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'emp_invite_title'), style: AppTypography.headingLarge)),
              ]),
              const SizedBox(height: AppSpacing.xl),

              // Error
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error))),
                  ]),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Created invite link
              if (_createdInviteLink != null && _createdInviteLink!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.link, size: 16, color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(tr(context, 'emp_invite_link'), style: AppTypography.labelMedium.copyWith(color: AppColors.success)),
                    ]),
                    const SizedBox(height: 8),
                    SelectableText(
                      _createdInviteLink!,
                      style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(tr(context, 'emp_invite_copy_hint'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                  ]),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Name
              _Field(controller: _nameC, label: tr(context, 'emp_name'), context: context),
              const SizedBox(height: AppSpacing.md),

              // Email
              _Field(controller: _emailC, label: tr(context, 'emp_email'), context: context),
              const SizedBox(height: AppSpacing.md),

              // Role selector (multi-select checkboxes)
              Text(tr(context, 'emp_select_role'), style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              if (_loadingRoles)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              else
                Container(
                  decoration: BoxDecoration(border: Border.all(color: AppColors.neutral300), borderRadius: BorderRadius.circular(10)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ..._roles.map((r) {
                      final isSelected = _selectedRoleIds.contains(r.id);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedRoleIds.add(r.id);
                            _primaryRoleId ??= r.id;
                          } else {
                            _selectedRoleIds.remove(r.id);
                            if (_primaryRoleId == r.id) {
                              _primaryRoleId = _selectedRoleIds.isNotEmpty ? _selectedRoleIds.first : null;
                            }
                          }
                        }),
                        title: Text('${r.name} (${r.roleKey})', style: AppTypography.labelMedium),
                        secondary: isSelected && _selectedRoleIds.length > 1
                            ? IconButton(
                                icon: Icon(_primaryRoleId == r.id ? Icons.star : Icons.star_border,
                                    color: _primaryRoleId == r.id ? AppColors.warning : AppColors.neutral400, size: 20),
                                tooltip: tr(context, 'emr_set_primary'),
                                onPressed: () => setState(() => _primaryRoleId = r.id),
                              )
                            : null,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ]),
                ),
              const SizedBox(height: AppSpacing.xl),

              // Actions
              if (_submitting)
                const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.base), child: CircularProgressIndicator()))
              else
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => context.go('/employees'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text(tr(context, 'inv_cancel')),
                  )),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(flex: 2, child: FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(tr(context, 'emp_send_invite')),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  )),
                ]),
              const SizedBox(height: AppSpacing.xxl),

              // ── Pending Invites Section ────────────────────
              Row(children: [
                const Icon(Icons.pending_outlined, size: 18, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Text(tr(context, 'emp_pending_invites'), style: AppTypography.headingSmall),
              ]),
              const SizedBox(height: AppSpacing.md),

              if (_loadingInvites)
                const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
              else if (_invites.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(color: AppColors.neutral50, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(tr(context, 'emp_no_invites'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))),
                )
              else
                ..._invites.map((inv) => _InviteTile(
                  invite: inv,
                  onRevoke: inv.isPending ? () => _revokeInvite(inv.id) : null,
                )),

              const SizedBox(height: AppSpacing.xxl),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final BuildContext context;
  const _Field({required this.controller, required this.label, required this.context});
  @override
  Widget build(BuildContext _) => TextField(
    controller: controller,
    textDirection: Directionality.of(context),
    decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
  );
}

class _InviteTile extends StatelessWidget {
  final WorkspaceInvitation invite;
  final VoidCallback? onRevoke;
  const _InviteTile({required this.invite, this.onRevoke});

  Color get _statusColor => switch (invite.status) {
    'pending' => AppColors.warning,
    'accepted' => AppColors.success,
    'revoked' => AppColors.error,
    'expired' => AppColors.neutral400,
    _ => AppColors.neutral400,
  };

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.divider),
    ),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(
          invite.isAccepted ? Icons.check_circle : invite.isRevoked ? Icons.cancel : Icons.schedule,
          size: 18, color: _statusColor,
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(invite.fullName ?? invite.email, style: AppTypography.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(invite.email, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(invite.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _statusColor)),
          ),
          if (invite.roles.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(invite.roleNamesDisplay, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          ] else if (invite.role != null) ...[
            const SizedBox(width: 6),
            Text(invite.role!.name, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          ],
        ]),
      ])),
      if (onRevoke != null)
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: AppColors.error),
          tooltip: tr(context, 'emp_revoke_invite'),
          onPressed: onRevoke,
        ),
    ]),
  );
}
