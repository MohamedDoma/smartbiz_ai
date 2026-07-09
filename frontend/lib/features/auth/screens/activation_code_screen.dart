// SmartBiz AI — Activation Code landing screen (Step 58).
// Shown when user opens /#/activate?code=SBZ-XXX
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/api/platform_models.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/platform_service.dart';
import '../../../core/theme/app_spacing.dart';

class ActivationCodeScreen extends StatefulWidget {
  final String? code;
  const ActivationCodeScreen({super.key, this.code});
  @override
  State<ActivationCodeScreen> createState() => _State();
}

class _State extends State<ActivationCodeScreen> {
  ActivationCodeValidationResult? result;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.code != null && widget.code!.isNotEmpty) {
      _validate(widget.code!);
    } else {
      loading = false;
      error = 'no_code';
    }
  }

  Future<void> _validate(String code) async {
    setState(() { loading = true; error = null; });
    try {
      // Use a bare ApiClient without workspace header for public endpoint
      final client = ApiClient();
      final svc = PlatformService(client);
      result = await svc.validateActivationCode(code);
    } catch (e) {
      error = e.toString();
    }
    setState(() { loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: loading
                  ? const CircularProgressIndicator()
                  : error != null
                      ? _errorView(context)
                      : result != null
                          ? result!.valid
                              ? _validView(context)
                              : _invalidView(context)
                          : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _validView(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 64),
      const SizedBox(height: 12),
      Text('SmartBiz AI', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('ابدأ نظام شركتك بالذكاء الاصطناعي', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      if (result!.campaign != null)
        Text('${tr(context, 'plt_campaign')}: ${result!.campaign}'),
      Text('${tr(context, 'plt_plan')}: ${result!.planKey ?? 'starter'}'),
      Text('${tr(context, 'plt_trial_days')}: ${result!.trialDays ?? 14}'),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => context.go('/register?activation_code=${widget.code}'),
          icon: const Icon(Icons.arrow_forward),
          label: Text(tr(context, 'plt_continue_register')),
        ),
      ),
    ]);
  }

  Widget _invalidView(BuildContext context) {
    final reasons = {
      'not_found': tr(context, 'plt_code_not_found'),
      'disabled': tr(context, 'plt_code_disabled'),
      'expired': tr(context, 'plt_code_expired'),
      'used': tr(context, 'plt_code_used'),
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error, color: Colors.red, size: 64),
      const SizedBox(height: 12),
      Text(reasons[result!.reason] ?? tr(context, 'plt_code_invalid'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 20),
      TextButton(onPressed: () => context.go('/register'), child: Text(tr(context, 'plt_register_without_code'))),
    ]);
  }

  Widget _errorView(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.orange, size: 64),
      const SizedBox(height: 12),
      Text(tr(context, 'plt_load_failed')),
      const SizedBox(height: 20),
      TextButton(onPressed: () => context.go('/register'), child: Text(tr(context, 'plt_register_without_code'))),
    ]);
  }
}
