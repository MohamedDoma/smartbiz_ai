// SmartBiz AI — Employee invitations (real API + persistent links + email resend).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/api/org_models.dart';
import '../../../core/api/org_service.dart';
import '../../../core/api/workspace_invite_models.dart';
import '../../../core/api/workspace_invite_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/responsive.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

class InviteEmployeeScreen extends StatefulWidget {
  const InviteEmployeeScreen({super.key});

  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  static const _none = '__none__';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _selectedRoleIds = <String>{};
  final _busyInviteIds = <String>{};

  String? _primaryRoleId;
  String? _departmentId;
  String? _teamId;
  List<WorkspaceRoleSummary> _roles = const [];
  List<WorkspaceInvitation> _invites = const [];
  List<OrgDepartment> _departments = const [];
  List<OrgTeam> _teams = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  WorkspaceInvitation? _latestInvite;

  late final WorkspaceInviteService _inviteService;
  late final OrgService _orgService;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _inviteService = appState.inviteService;
    _orgService = OrgService(appState.apiClient);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  List<OrgTeam> get _availableTeams => _departmentId == null
      ? _teams
      : _teams.where((team) => team.departmentId == _departmentId).toList();

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _inviteService.listWorkspaceRoles(),
        _inviteService.listInvites(),
        _orgService.listDepartments(),
        _orgService.listTeams(),
      ]);
      if (!mounted) return;
      setState(() {
        _roles = (results[0] as List<WorkspaceRoleSummary>)
            .where((role) => role.roleKey != 'owner')
            .toList();
        _invites = results[1] as List<WorkspaceInvitation>;
        _departments = results[2] as List<OrgDepartment>;
        _teams = results[3] as List<OrgTeam>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate() || _selectedRoleIds.isEmpty) {
      if (_selectedRoleIds.isEmpty) {
        setState(() => _error = tr(context, 'emp_invite_role_required'));
      }
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _latestInvite = null;
    });

    try {
      final locale = Directionality.of(context) == TextDirection.rtl ? 'ar' : 'en';
      final invite = await _inviteService.createInvite(
        CreateWorkspaceInvitationPayload(
          email: _emailController.text.trim(),
          fullName: _nameController.text.trim(),
          roleIds: _selectedRoleIds.toList(),
          primaryRoleId: _primaryRoleId ?? _selectedRoleIds.first,
          departmentId: _departmentId,
          teamId: _teamId,
          jobTitle: _jobTitleController.text.trim(),
          preferredLocale: locale,
        ),
      );

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _latestInvite = invite;
        _invites = [invite, ..._invites.where((item) => item.id != invite.id)];
        _nameController.clear();
        _emailController.clear();
        _jobTitleController.clear();
        _selectedRoleIds.clear();
        _primaryRoleId = null;
        _departmentId = null;
        _teamId = null;
      });

      _showMessage(
        invite.deliveryStatus == 'sent'
            ? tr(context, 'emp_invite_email_sent')
            : tr(context, 'emp_invite_email_failed'),
        invite.deliveryStatus == 'sent' ? AppColors.success : AppColors.warning,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _copyLink(WorkspaceInvitation invite) async {
    if (!invite.hasCopyableLink) {
      _showMessage(tr(context, 'emp_invite_link_unavailable'), AppColors.warning);
      return;
    }
    await Clipboard.setData(ClipboardData(text: invite.inviteUrl!));
    if (!mounted) return;
    _showMessage(tr(context, 'emp_invite_link_copied'), AppColors.success);
  }

  Future<void> _resend(WorkspaceInvitation invite) async {
    setState(() => _busyInviteIds.add(invite.id));
    try {
      final updated = await _inviteService.resendInvite(invite.id);
      if (!mounted) return;
      _replaceInvite(updated);
      _showMessage(
        updated.deliveryStatus == 'sent'
            ? tr(context, 'emp_invite_resent')
            : tr(context, 'emp_invite_email_failed'),
        updated.deliveryStatus == 'sent' ? AppColors.success : AppColors.warning,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(_friendlyError(error), AppColors.error);
    } finally {
      if (mounted) setState(() => _busyInviteIds.remove(invite.id));
    }
  }

  Future<void> _revoke(WorkspaceInvitation invite) async {
    setState(() => _busyInviteIds.add(invite.id));
    try {
      final updated = await _inviteService.revokeInvite(invite.id);
      if (!mounted) return;
      _replaceInvite(updated);
      _showMessage(tr(context, 'emp_invite_revoked'), AppColors.warning);
    } catch (error) {
      if (!mounted) return;
      _showMessage(_friendlyError(error), AppColors.error);
    } finally {
      if (mounted) setState(() => _busyInviteIds.remove(invite.id));
    }
  }

  void _replaceInvite(WorkspaceInvitation updated) {
    setState(() {
      _invites = _invites
          .map((invite) => invite.id == updated.id ? updated : invite)
          .toList();
      if (_latestInvite?.id == updated.id) _latestInvite = updated;
    });
  }

  String _friendlyError(Object error) {
    if (error is ValidationException) {
      final messages = error.errors.values.expand((items) => items).toList();
      return messages.isNotEmpty ? messages.first : error.message;
    }
    if (error is ApiException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/employees'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        tr(context, 'emp_invite_title'),
                        style: AppTypography.headingLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _loadData,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_latestInvite?.hasCopyableLink == true) ...[
                  _LatestLinkCard(
                    invite: _latestInvite!,
                    onCopy: () => _copyLink(_latestInvite!),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _buildForm(context),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  children: [
                    const Icon(Icons.mark_email_read_outlined,
                        size: 19, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      tr(context, 'emp_invitation_history'),
                      style: AppTypography.headingSmall,
                    ),
                    const Spacer(),
                    Text(
                      '${_invites.length}',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_invites.isEmpty)
                  _EmptyInvites(message: tr(context, 'emp_no_invites'))
                else
                  ..._invites.map(
                    (invite) => _InviteTile(
                      invite: invite,
                      busy: _busyInviteIds.contains(invite.id),
                      onCopy: invite.hasCopyableLink
                          ? () => _copyLink(invite)
                          : null,
                      onResend: invite.canResend ? () => _resend(invite) : null,
                      onRevoke:
                          invite.isPending ? () => _revoke(invite) : null,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'emp_new_invitation'),
                style: AppTypography.headingSmall),
            const SizedBox(height: AppSpacing.lg),
            _TextField(
              controller: _nameController,
              label: tr(context, 'emp_name'),
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _emailController,
              label: tr(context, 'emp_email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return tr(context, 'field_required');
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return tr(context, 'emp_invalid_email');
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _TextField(
              controller: _jobTitleController,
              label: tr(context, 'emp_job_title'),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _departmentId ?? _none,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_department'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: _none,
                  child: Text(tr(context, 'asgn_none')),
                ),
                ..._departments.map(
                  (department) => DropdownMenuItem(
                    value: department.id,
                    child: Text(department.name),
                  ),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                        _departmentId = value == _none ? null : value;
                        if (_departmentId == null ||
                            (_teamId != null &&
                                !_availableTeams
                                    .any((team) => team.id == _teamId))) {
                          _teamId = null;
                        }
                      }),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _teamId ?? _none,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_team'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: _none,
                  child: Text(tr(context, 'asgn_none')),
                ),
                ..._availableTeams.map(
                  (team) => DropdownMenuItem(
                    value: team.id,
                    child: Text(team.name),
                  ),
                ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                        _teamId = value == _none ? null : value;
                        if (_teamId != null) {
                          final team = _teams.firstWhere(
                            (item) => item.id == _teamId,
                          );
                          _departmentId = team.departmentId ?? _departmentId;
                        }
                      }),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(tr(context, 'emp_select_role'),
                style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.neutral300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _roles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        tr(context, 'emp_no_roles_available'),
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    )
                  : Column(
                      children: _roles.map((role) {
                        final selected = _selectedRoleIds.contains(role.id);
                        return CheckboxListTile(
                          value: selected,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(role.name),
                          subtitle: role.description?.isNotEmpty == true
                              ? Text(role.description!, maxLines: 1)
                              : null,
                          secondary: selected && _selectedRoleIds.length > 1
                              ? IconButton(
                                  tooltip: tr(context, 'emr_set_primary'),
                                  icon: Icon(
                                    _primaryRoleId == role.id
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: _primaryRoleId == role.id
                                        ? AppColors.warning
                                        : AppColors.neutral400,
                                  ),
                                  onPressed: () =>
                                      setState(() => _primaryRoleId = role.id),
                                )
                              : null,
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selectedRoleIds.add(role.id);
                              _primaryRoleId ??= role.id;
                            } else {
                              _selectedRoleIds.remove(role.id);
                              if (_primaryRoleId == role.id) {
                                _primaryRoleId = _selectedRoleIds.isNotEmpty
                                    ? _selectedRoleIds.first
                                    : null;
                              }
                            }
                          }),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _send,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(tr(context, 'emp_send_invite')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

class _LatestLinkCard extends StatelessWidget {
  final WorkspaceInvitation invite;
  final VoidCallback onCopy;

  const _LatestLinkCard({required this.invite, required this.onCopy});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, 'emp_invite_link'),
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.success),
                  ),
                ),
                IconButton(
                  onPressed: onCopy,
                  tooltip: tr(context, 'emp_copy_link'),
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
            SelectableText(invite.inviteUrl!, style: AppTypography.caption),
          ],
        ),
      );
}

class _InviteTile extends StatelessWidget {
  final WorkspaceInvitation invite;
  final bool busy;
  final VoidCallback? onCopy;
  final VoidCallback? onResend;
  final VoidCallback? onRevoke;

  const _InviteTile({
    required this.invite,
    required this.busy,
    this.onCopy,
    this.onResend,
    this.onRevoke,
  });

  Color get _statusColor => switch (invite.status) {
        'pending' => AppColors.warning,
        'accepted' => AppColors.success,
        'revoked' => AppColors.error,
        _ => AppColors.neutral500,
      };

  String _statusLabel(BuildContext context) => switch (invite.status) {
        'pending' => tr(context, 'emp_invite_status_pending'),
        'accepted' => tr(context, 'emp_invite_status_accepted'),
        'revoked' => tr(context, 'emp_invite_status_revoked'),
        'expired' => tr(context, 'emp_invite_status_expired'),
        _ => invite.status,
      };

  String _deliveryLabel(BuildContext context) => switch (invite.deliveryStatus) {
        'sent' => tr(context, 'emp_delivery_sent'),
        'failed' => tr(context, 'emp_delivery_failed'),
        _ => tr(context, 'emp_delivery_pending'),
      };

  @override
  Widget build(BuildContext context) {
    final details = [
      if (invite.jobTitle?.isNotEmpty == true) invite.jobTitle!,
      if (invite.department != null) invite.department!.name,
      if (invite.team != null) invite.team!.name,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              invite.isAccepted
                  ? Icons.check_circle_outline
                  : invite.isRevoked
                      ? Icons.cancel_outlined
                      : invite.isExpired
                          ? Icons.timer_off_outlined
                          : Icons.schedule_send_outlined,
              color: _statusColor,
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.fullName?.isNotEmpty == true
                      ? invite.fullName!
                      : invite.email,
                  style: AppTypography.labelMedium,
                ),
                Text(
                  invite.email,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (invite.roleNamesDisplay.isNotEmpty)
                  Text(
                    invite.roleNamesDisplay,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primary),
                  ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _SmallBadge(label: _statusLabel(context), color: _statusColor),
                    _SmallBadge(
                      label: _deliveryLabel(context),
                      color: invite.deliveryStatus == 'sent'
                          ? AppColors.success
                          : invite.deliveryStatus == 'failed'
                              ? AppColors.error
                              : AppColors.neutral500,
                    ),
                    if (invite.sendCount > 0)
                      _SmallBadge(
                        label: '${tr(context, 'emp_sent_count')}: ${invite.sendCount}',
                        color: AppColors.info,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'copy') onCopy?.call();
                if (value == 'resend') onResend?.call();
                if (value == 'revoke') onRevoke?.call();
              },
              itemBuilder: (_) => [
                if (onCopy != null)
                  PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.copy_outlined, size: 18),
                      title: Text(tr(context, 'emp_copy_link')),
                    ),
                  ),
                if (onResend != null)
                  PopupMenuItem(
                    value: 'resend',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.send_outlined, size: 18),
                      title: Text(tr(context, 'emp_resend')),
                    ),
                  ),
                if (onRevoke != null)
                  PopupMenuItem(
                    value: 'revoke',
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.block, size: 18, color: AppColors.error),
                      title: Text(
                        tr(context, 'emp_revoke_invite'),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
}

class _EmptyInvites extends StatelessWidget {
  final String message;

  const _EmptyInvites({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.neutral50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
      );
}
