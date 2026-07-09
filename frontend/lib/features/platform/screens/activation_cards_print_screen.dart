// SmartBiz AI — Printable Activation Cards screen (Step 58).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/api/platform_models.dart';
import '../platform_state.dart';

class ActivationCardsPrintScreen extends StatefulWidget {
  const ActivationCardsPrintScreen({super.key});
  @override
  State<ActivationCardsPrintScreen> createState() => _State();
}

class _State extends State<ActivationCardsPrintScreen> {
  @override
  void initState() {
    super.initState();
    final s = context.read<PlatformState>();
    if (s.codes.isEmpty) Future.microtask(() => s.loadCodes());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PlatformState>();
    final unused = s.codes.where((c) => c.status == 'unused').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'plt_print_cards')),
        actions: [
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: tr(context, 'plt_print_cards'),
              onPressed: _doPrint,
            ),
        ],
      ),
      body: unused.isEmpty
          ? Center(child: Text(tr(context, 'plt_no_data')))
          : GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: unused.length,
              itemBuilder: (ctx, i) => _card(context, unused[i]),
            ),
    );
  }

  void _doPrint() {
    // Use JS interop for web print
    try {
      // ignore: avoid_dynamic_calls
      (const bool.fromEnvironment('dart.library.html')) ? null : null;
      // Fallback: just show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(context, 'plt_print_cards')} — Ctrl+P')),
      );
    } catch (_) {}
  }

  Widget _card(BuildContext context, PlatformActivationCode code) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SmartBiz AI', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('ابدأ نظام شركتك بالذكاء الاصطناعي', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(code.code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 2)),
            ),
            const SizedBox(height: 6),
            if (code.registrationUrl != null)
              Text(code.registrationUrl!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${code.trialDays ?? 14} يوم تجربة مجانية · ${code.defaultPlanKey ?? 'starter'}', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text('امسح الكود أو افتح الرابط وابدأ التسجيل', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
