// SmartBiz AI — Activation Codes screen (Step 58).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../platform_state.dart';

class ActivationCodesScreen extends StatefulWidget {
  const ActivationCodesScreen({super.key});
  @override
  State<ActivationCodesScreen> createState() => _State();
}

class _State extends State<ActivationCodesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<PlatformState>().loadCodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PlatformState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'plt_codes'))),
      body: s.codesLoading
          ? const Center(child: CircularProgressIndicator())
          : s.codes.isEmpty
              ? Center(child: Text(tr(context, 'plt_no_data')))
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: s.codes.length,
                  itemBuilder: (ctx, i) {
                    final c = s.codes[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.qr_code_2, color: c.status == 'unused' ? Colors.green : Colors.grey),
                        title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        subtitle: Text('${c.campaignName ?? ''} · ${c.status} · ${c.trialDays ?? 14} يوم'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.copy), onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.code));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'plt_copied'))));
                          }),
                          if (c.registrationUrl != null) IconButton(icon: const Icon(Icons.link), onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.registrationUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'plt_copied'))));
                          }),
                          IconButton(icon: const Icon(Icons.share), onPressed: () {
                            final txt = 'ابدأ نظام شركتك مع SmartBiz AI 🚀\nاستخدم الكود: ${c.code}\nالرابط: ${c.registrationUrl ?? ''}';
                            Clipboard.setData(ClipboardData(text: txt));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'plt_whatsapp_copied'))));
                          }),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
