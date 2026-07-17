// SmartBiz AI — AI Discovery conversation screen.
//
// Adaptive conversation UI — no fixed question count, no scripted chips.
// Shows real AI messages from the backend and allows free-form input.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/state/app_state.dart';
import '../models/onboarding_models.dart';
import '../onboarding_state.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/discovery_progress_bar.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Trigger backend resume on page startup (e.g. after browser refresh)
    final state = context.read<OnboardingState>();
    if (!state.resumeAttempted) {
      state.resumeDiscovery();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    context.read<OnboardingState>().sendMessage(text, context);
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final isMobile = Responsive.isMobile(context);

    // Inject local welcome greeting if conversation is empty
    final appState = context.read<AppState>();
    state.ensureWelcomeGreeting(appState);

    // Replace backend English ready-notification with localized version
    state.localizeReadyMessage(appState);

    return Column(
      children: [
        // Progress bar — dynamic, backend-driven
        DiscoveryProgressBar(
          completeness: state.completeness,
          readyForBlueprint: state.readyForBlueprint,
        ),

        // Error banner (retryable)
        if (state.discoveryError != null) _buildErrorBanner(context, state),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl,
              vertical: AppSpacing.md,
            ),
            itemCount: state.messages.length + (state.isAiThinking ? 1 : 0),
            itemBuilder: (context, index) {
              // Thinking indicator
              if (index == state.messages.length && state.isAiThinking) {
                return ChatBubble.thinking();
              }

              final msg = state.messages[index];
              final isLast =
                  index == state.messages.length - 1 && !state.isAiThinking;

              return ChatBubble(
                message: msg,
                showQuickReplies: isLast && msg.sender == MessageSender.ai,
                onQuickReply: (reply) {
                  context
                      .read<OnboardingState>()
                      .sendQuickReply(reply, context);
                  _scrollToBottom();
                },
              );
            },
          ),
        ),

        // Blueprint CTA (show when backend reports ready)
        if (state.readyForBlueprint) _buildBlueprintCta(context, state),

        // Input bar
        _buildInputBar(context, state, isMobile),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context, OnboardingState state) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              state.discoveryError!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              // Retry: just re-send the last user message
              // The conversation is preserved
            },
            child: Text(tr(context, 'retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildBlueprintCta(BuildContext context, OnboardingState state) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: state.isAiThinking
              ? null
              : () => context
                  .read<OnboardingState>()
                  .classifyAndGenerateBlueprint(),
          icon: const Icon(Icons.architecture, size: 18),
          label: Text(tr(context, 'onboard_view_blueprint')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(
      BuildContext context, OnboardingState state, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AppSpacing.sm : AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textDirection: Directionality.of(context),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: tr(context, 'onboard_input_hint'),
                  hintTextDirection: Directionality.of(context),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.auto_awesome_outlined,
                        color: AppColors.accent, size: 18),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 42, minHeight: 42),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: state.isAiThinking ? null : _send,
                borderRadius: BorderRadius.circular(12),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.send, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
