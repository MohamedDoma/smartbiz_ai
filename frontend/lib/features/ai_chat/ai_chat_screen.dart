// SmartBiz AI — Operational AI Chat screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive.dart';
import 'ai_chat_state.dart';
import 'models/chat_models.dart';
import 'widgets/chat_widgets.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    context.read<AiChatState>().sendMessage(text, context);
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AiChatState>();
    final isMobile = Responsive.isMobile(context);

    return Column(
      children: [
        // Header bar with credits
        _ChatHeader(credits: state.credits),

        // Messages or empty state
        Expanded(
          child: state.isEmpty
              ? _EmptyState(
                  isMobile: isMobile,
                  onSuggestion: (text) {
                    context.read<AiChatState>().sendMessage(text, context);
                    _scrollToBottom();
                  },
                )
              : _MessageList(
                  state: state,
                  scrollController: _scrollController,
                  isMobile: isMobile,
                  onQuickReply: (text) {
                    context.read<AiChatState>().sendQuickReply(text, context);
                    _scrollToBottom();
                  },
                  onConfirm: (id) {
                    context.read<AiChatState>().confirmAction(id, context);
                    _scrollToBottom();
                  },
                  onCancel: (id) {
                    context.read<AiChatState>().cancelAction(id);
                  },
                ),
        ),

        // Input bar
        _ChatInputBar(
          controller: _controller,
          isMobile: isMobile,
          isThinking: state.isThinking,
          onSend: _send,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Chat Header with Credits
// ═══════════════════════════════════════════════════════════
class _ChatHeader extends StatelessWidget {
  final int credits;
  const _ChatHeader({required this.credits});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(tr(context, 'chat_header_title'), style: AppTypography.labelLarge),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toll, size: 13, color: AppColors.accent),
                const SizedBox(width: 4),
                Text('$credits', style: AppTypography.labelMedium.copyWith(color: AppColors.accent)),
                const SizedBox(width: 2),
                Text(tr(context, 'chat_credits'), style: AppTypography.caption.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Empty State
// ═══════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final bool isMobile;
  final void Function(String) onSuggestion;
  const _EmptyState({required this.isMobile, required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.base : AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.auto_awesome, size: 32, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(tr(context, 'ai_title'), style: isMobile ? AppTypography.headingMedium : AppTypography.headingLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(tr(context, 'chat_empty_subtitle'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xxl),

              // Suggestion cards
              _SuggestionCard(icon: Icons.receipt_long, labelKey: 'chat_suggest_invoice', onTap: () => onSuggestion(tr(context, 'chat_suggest_invoice_cmd'))),
              const SizedBox(height: AppSpacing.sm),
              _SuggestionCard(icon: Icons.trending_up, labelKey: 'chat_suggest_revenue', onTap: () => onSuggestion(tr(context, 'chat_suggest_revenue_cmd'))),
              const SizedBox(height: AppSpacing.sm),
              _SuggestionCard(icon: Icons.inventory_2, labelKey: 'chat_suggest_stock', onTap: () => onSuggestion(tr(context, 'chat_suggest_stock_cmd'))),
              const SizedBox(height: AppSpacing.sm),
              _SuggestionCard(icon: Icons.person_add, labelKey: 'chat_suggest_contact', onTap: () => onSuggestion(tr(context, 'chat_suggest_contact_cmd'))),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String labelKey;
  final VoidCallback onTap;
  const _SuggestionCard({required this.icon, required this.labelKey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(tr(context, labelKey), style: AppTypography.bodyMedium)),
            const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.neutral400),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Message List
// ═══════════════════════════════════════════════════════════
class _MessageList extends StatelessWidget {
  final AiChatState state;
  final ScrollController scrollController;
  final bool isMobile;
  final void Function(String) onQuickReply;
  final void Function(String) onConfirm;
  final void Function(String) onCancel;

  const _MessageList({
    required this.state,
    required this.scrollController,
    required this.isMobile,
    required this.onQuickReply,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? AppSpacing.sm : AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          itemCount: state.messages.length + (state.isThinking ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == state.messages.length && state.isThinking) {
              return const TypingIndicator();
            }

            final msg = state.messages[index];
            final isLast = index == state.messages.length - 1 && !state.isThinking;

            return ChatBubble(
              message: msg,
              onQuickReply: isLast ? onQuickReply : null,
              onConfirm: msg.type == ChatMsgType.actionDraft && msg.actionStatus == ActionStatus.pending ? onConfirm : null,
              onCancel: msg.type == ChatMsgType.actionDraft && msg.actionStatus == ActionStatus.pending ? onCancel : null,
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Input Bar
// ═══════════════════════════════════════════════════════════
class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isMobile;
  final bool isThinking;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.controller,
    required this.isMobile,
    required this.isThinking,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textDirection: Directionality.of(context),
                    onSubmitted: (_) => onSend(),
                    enabled: !isThinking,
                    decoration: InputDecoration(
                      hintText: tr(context, 'chat_input_hint'),
                      hintTextDirection: Directionality.of(context),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.auto_awesome_outlined, color: AppColors.accent, size: 18),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Material(
                  color: isThinking ? AppColors.neutral300 : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: isThinking ? null : onSend,
                    borderRadius: BorderRadius.circular(12),
                    child: const SizedBox(width: 44, height: 44, child: Icon(Icons.send, size: 18, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
