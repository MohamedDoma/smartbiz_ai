// SmartBiz AI — Activation Campaigns screen (Step 58).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/api/platform_models.dart';
import '../platform_state.dart';

class ActivationCampaignsScreen extends StatefulWidget {
  const ActivationCampaignsScreen({super.key});

  @override
  State<ActivationCampaignsScreen> createState() => _ActivationCampaignsScreenState();
}

class _ActivationCampaignsScreenState extends State<ActivationCampaignsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<PlatformState>().loadCampaigns());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlatformState>();

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'plt_campaigns'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: state.campaignsLoading
          ? const Center(child: CircularProgressIndicator())
          : state.campaigns.isEmpty
              ? Center(child: Text(tr(context, 'plt_no_data')))
              : RefreshIndicator(
                  onRefresh: () => state.loadCampaigns(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.campaigns.length,
                    itemBuilder: (context, i) {
                      final c = state.campaigns[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.campaign),
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.targetMarket ?? ''} · '
                            '${tr(context, 'plt_plan')}: ${c.defaultPlanKey ?? '—'} · '
                            '${c.totalCodes} ${tr(context, 'plt_codes')} · '
                            '${c.usedCodes} ${tr(context, 'plt_used')}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.qr_code),
                                tooltip: tr(context, 'plt_generate_codes'),
                                onPressed: () => _showGenerateDialog(c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.list),
                                tooltip: tr(context, 'plt_codes'),
                                onPressed: () => context.go('/platform/codes?campaign=${c.id}'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final marketCtrl = TextEditingController();
    final trialCtrl = TextEditingController(text: '14');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'plt_create_campaign')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr(context, 'gen_name'))),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: InputDecoration(labelText: tr(context, 'gen_description'))),
              const SizedBox(height: 8),
              TextField(controller: marketCtrl, decoration: InputDecoration(labelText: tr(context, 'plt_target_market'))),
              const SizedBox(height: 8),
              TextField(controller: trialCtrl, decoration: InputDecoration(labelText: tr(context, 'plt_trial_days')), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'gen_cancel'))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<PlatformState>().createCampaign(PlatformActivationCampaignPayload(
                    name: nameCtrl.text,
                    description: descCtrl.text,
                    targetMarket: marketCtrl.text,
                    trialDays: int.tryParse(trialCtrl.text),
                    defaultPlanKey: 'starter',
                  ));
            },
            child: Text(tr(context, 'gen_save')),
          ),
        ],
      ),
    );
  }

  void _showGenerateDialog(PlatformActivationCampaign campaign) {
    final countCtrl = TextEditingController(text: '10');
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'plt_generate_codes')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${tr(context, 'plt_campaign')}: ${campaign.name}'),
            const SizedBox(height: 8),
            TextField(controller: countCtrl, decoration: InputDecoration(labelText: tr(context, 'plt_count')), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr(context, 'plt_assigned_to'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'gen_cancel'))),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<PlatformState>().generateCodes(
                    campaign.id,
                    ActivationCodeGenerationPayload(
                      count: int.tryParse(countCtrl.text) ?? 10,
                      assignedToName: nameCtrl.text.isNotEmpty ? nameCtrl.text : null,
                    ),
                  );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'plt_codes_generated'))));
              }
            },
            child: Text(tr(context, 'plt_generate_codes')),
          ),
        ],
      ),
    );
  }
}
