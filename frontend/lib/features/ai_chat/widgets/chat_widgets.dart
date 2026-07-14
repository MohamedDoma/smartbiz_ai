// SmartBiz AI — AI Chat widgets.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/chat_models.dart';

// ═══════════════════════════════════════════════════════════
//  ChatBubble — routes to correct sub-widget by type
// ═══════════════════════════════════════════════════════════
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(String)? onQuickReply;
  final void Function(String)? onConfirm;
  final void Function(String)? onCancel;

  const ChatBubble({
    super.key,
    required this.message,
    this.onQuickReply,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == ChatSender.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _AiAvatar(),
          if (!isUser) const SizedBox(width: AppSpacing.sm),
          Flexible(child: _buildContent(context, isUser)),
          if (isUser) const SizedBox(width: AppSpacing.sm),
          if (isUser) _UserAvatar(),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    return switch (message.type) {
      ChatMsgType.text => _TextBubble(message: message, isUser: isUser, onQuickReply: onQuickReply),
      ChatMsgType.insight => _InsightCard(message: message),
      ChatMsgType.recommendation => _RecommendationCard(message: message, onQuickReply: onQuickReply),
      ChatMsgType.actionDraft => _ActionDraftCard(message: message, onConfirm: onConfirm, onCancel: onCancel),
      ChatMsgType.actionResult => _ResultCard(message: message),
    };
  }
}

// ── Avatars ──────────────────────────────────────────────
class _AiAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.person, size: 14, color: Colors.white),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Text Bubble
// ═══════════════════════════════════════════════════════════
class _TextBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;
  final void Function(String)? onQuickReply;

  const _TextBubble({required this.message, required this.isUser, this.onQuickReply});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: isUser ? null : Border.all(color: AppColors.divider),
          ),
          child: isUser
              ? Text(
                  message.text,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                )
              : MarkdownBody(
                  data: message.text,
                  selectable: true,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet(
                    p: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                    h1: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      height: 1.4,
                    ),
                    h2: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.4,
                    ),
                    h3: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    strong: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    em: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                    code: AppTypography.bodyMedium.copyWith(
                      color: AppColors.accent,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      backgroundColor: AppColors.primarySurface,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    listBullet: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                    listIndent: 16,
                    blockSpacing: 8,
                    pPadding: EdgeInsets.zero,
                    h1Padding: const EdgeInsets.only(bottom: 4),
                    h2Padding: const EdgeInsets.only(bottom: 4),
                    h3Padding: const EdgeInsets.only(bottom: 4),
                  ),
                  onTapLink: (text, href, title) {
                    // Do not open external links for security
                  },
                ),
        ),
        if (message.quickReplies != null && message.quickReplies!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: message.quickReplies!.map((r) => ActionChip(
              label: Text(r, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
              onPressed: () => onQuickReply?.call(r),
              backgroundColor: AppColors.primarySurface,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 2),
            )).toList(),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Insight Card
// ═══════════════════════════════════════════════════════════
class _InsightCard extends StatelessWidget {
  final ChatMessage message;
  const _InsightCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withValues(alpha: 0.08), AppColors.primary.withValues(alpha: 0.05)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(tr(context, message.insightTitleKey ?? 'chat_insight'), style: AppTypography.labelLarge.copyWith(color: AppColors.accent))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message.text, style: AppTypography.bodyMedium.copyWith(height: 1.5, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Recommendation Card
// ═══════════════════════════════════════════════════════════
class _RecommendationCard extends StatelessWidget {
  final ChatMessage message;
  final void Function(String)? onQuickReply;
  const _RecommendationCard({required this.message, this.onQuickReply});

  Color get _impactColor => switch (message.recImpact) {
    'high' => AppColors.error,
    'medium' => AppColors.warning,
    _ => AppColors.info,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _impactColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.lightbulb_outline, size: 14, color: _impactColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(tr(context, message.recTitleKey ?? ''), style: AppTypography.labelLarge)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(message.recImpact?.toUpperCase() ?? '', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _impactColor)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message.text, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.4)),
          if (message.quickReplies != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: message.quickReplies!.map((r) => _SmallAction(label: r, onTap: () => onQuickReply?.call(r))).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Action Draft Card
// ═══════════════════════════════════════════════════════════
class _ActionDraftCard extends StatelessWidget {
  final ChatMessage message;
  final void Function(String)? onConfirm;
  final void Function(String)? onCancel;
  const _ActionDraftCard({required this.message, this.onConfirm, this.onCancel});

  IconData get _typeIcon => switch (message.actionTypeKey) {
    'invoice' => Icons.receipt_long,
    'contact' => Icons.person_add,
    'product' => Icons.add_box,
    _ => Icons.task,
  };

  bool get _isPending => message.actionStatus == ActionStatus.pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _isPending ? AppColors.accent.withValues(alpha: 0.4) : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, message.actionTitleKey ?? ''), style: AppTypography.labelLarge)),
                if (!_isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (message.actionStatus == ActionStatus.confirmed ? AppColors.success : AppColors.neutral400).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message.actionStatus == ActionStatus.confirmed ? tr(context, 'chat_confirmed') : tr(context, 'chat_cancelled'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: message.actionStatus == ActionStatus.confirmed ? AppColors.success : AppColors.neutral500),
                    ),
                  ),
              ],
            ),
          ),

          // Fields
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: (message.actionFields ?? []).map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(tr(context, f.labelKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ),
                    Expanded(child: Text(f.value, style: AppTypography.labelMedium)),
                  ],
                ),
              )).toList(),
            ),
          ),

          // Actions
          if (_isPending)
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onCancel?.call(message.id),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(tr(context, 'chat_cancel')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => onConfirm?.call(message.id),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(tr(context, 'chat_confirm')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Result Card
// ═══════════════════════════════════════════════════════════
class _ResultCard extends StatelessWidget {
  final ChatMessage message;
  const _ResultCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 16, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.text, style: AppTypography.labelLarge.copyWith(color: AppColors.success)),
                if (message.resultSummary != null) ...[
                  const SizedBox(height: 2),
                  Text(message.resultSummary!, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Typing Indicator
// ═══════════════════════════════════════════════════════════
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          _AiAvatar(),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.3;
                  final t = ((_controller.value + delay) % 1.0);
                  final opacity = (1.0 - (t - 0.5).abs() * 2).clamp(0.3, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Small Action Button
// ═══════════════════════════════════════════════════════════
class _SmallAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SmallAction({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white)),
      ),
    );
  }
}
