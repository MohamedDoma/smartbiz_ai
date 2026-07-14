// SmartBiz AI — AI Chat Screen (Step 59.1).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ai_state.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AiState>().sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AiState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'ai_chat')),
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: tr(context, 'ai_new_chat'),
              onPressed: () => state.clearChat(),
            ),
          IconButton(
            icon: const Icon(Icons.wifi_tethering),
            tooltip: tr(context, 'ai_test_connection'),
            onPressed: state.testing ? null : () => state.testConnection(),
          ),
        ],
      ),
      body: Column(children: [
        // Test result banner
        if (state.testResult != null || state.testError != null)
          _buildTestBanner(state),

        // Step 59.1 notice
        if (state.messages.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 48, color: AppColors.primary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(tr(context, 'ai_chat'), style: AppTypography.headingSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    tr(context, 'ai_no_business_data_yet'),
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            itemCount: state.messages.length,
            itemBuilder: (_, i) => _buildMessage(state.messages[i]),
          ),
        ),

        // Error
        if (state.chatError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            color: AppColors.error.withValues(alpha: 0.1),
            child: Text(state.chatError!, style: AppTypography.caption.copyWith(color: AppColors.error)),
          ),

        // Input
        _buildInput(state),
      ]),
    );
  }

  Widget _buildTestBanner(AiState state) {
    if (state.testing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        color: AppColors.info.withValues(alpha: 0.1),
        child: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpacing.sm),
          Text(tr(context, 'ai_loading'), style: AppTypography.caption),
        ]),
      );
    }
    if (state.testError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        color: AppColors.error.withValues(alpha: 0.1),
        child: Text('${tr(context, 'ai_error')}: ${state.testError}', style: AppTypography.caption.copyWith(color: AppColors.error)),
      );
    }
    final r = state.testResult;
    if (r != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        color: r.success ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
        child: Text(
          r.success
              ? '✅ ${r.text ?? "AI ready"} (${r.model}, ${r.durationMs}ms)'
              : '❌ ${r.error ?? "Failed"}',
          style: AppTypography.caption.copyWith(
            color: r.success ? AppColors.success : AppColors.error,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMessage(dynamic msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary.withValues(alpha: 0.15) : AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          msg.content ?? '',
          style: AppTypography.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildInput(AiState state) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: AppColors.neutral200)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: tr(context, 'ai_type_message'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filled(
          onPressed: state.sending ? null : _send,
          icon: state.sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
        ),
      ]),
    );
  }
}
