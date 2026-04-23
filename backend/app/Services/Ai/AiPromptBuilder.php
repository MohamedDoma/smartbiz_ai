<?php

namespace App\Services\Ai;

use App\Models\WorkspaceConfiguration;
use Illuminate\Support\Facades\DB;

/**
 * Builds system prompts with workspace context, user role, memory, and tool instructions.
 */
class AiPromptBuilder
{
    private const PROMPT_VERSION = 'v2.0';

    public function promptVersion(): string
    {
        return self::PROMPT_VERSION;
    }

    /**
     * Build the system prompt for a chat conversation.
     */
    public function buildSystemPrompt(string $workspaceId, string $userId, array $permissions, array $memoryContext = []): string
    {
        $config = WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
        $role   = $this->detectRole($workspaceId, $userId);

        $modules = $config?->enabled_modules ?? ['contacts', 'products', 'invoices', 'payments'];
        $businessType = $config?->metadata['business_type'] ?? 'general';

        $parts = [];

        $parts[] = "You are SmartBiz AI, an intelligent business assistant for a {$businessType} business.";
        $parts[] = "You help users understand their business data, answer questions, and assist with common operations.";
        $parts[] = '';
        $parts[] = '## Rules';
        $parts[] = '- Only access data the user has permission to see.';
        $parts[] = '- Never execute actions directly — always create drafts that require user confirmation.';
        $parts[] = '- If a search returns multiple matches, ask the user to clarify before proceeding.';
        $parts[] = '- Be concise and professional. Use numbers and data when answering questions.';
        $parts[] = '- If you cannot answer a question with the available tools, say so honestly.';
        $parts[] = '- When referring to previous context, use specific names and numbers.';
        $parts[] = '';
        $parts[] = '## Available Modules: ' . implode(', ', $modules);
        $parts[] = '## User Role: ' . ($role ?? 'member');
        $parts[] = '## Workspace: ' . $workspaceId;
        $parts[] = '';

        // Inject memory context
        if (! empty($memoryContext)) {
            $parts[] = '## Context from previous interactions';

            if (! empty($memoryContext['session'])) {
                $parts[] = '### Recent session';
                foreach ($memoryContext['session'] as $key => $val) {
                    $parts[] = "- {$key}: " . (is_string($val) ? $val : json_encode($val));
                }
            }

            if (! empty($memoryContext['frequent_contacts'])) {
                $parts[] = '### Frequently used contacts: ' . implode(', ', $memoryContext['frequent_contacts']);
            }

            if (! empty($memoryContext['frequent_products'])) {
                $parts[] = '### Frequently used products: ' . implode(', ', $memoryContext['frequent_products']);
            }

            $parts[] = '';
        }

        $parts[] = '## Important';
        $parts[] = '- When creating drafts (invoices, contacts, products, orders, payments), use the appropriate draft_ tool.';
        $parts[] = '- The user will see the draft and can confirm or reject it.';
        $parts[] = '- If multiple contacts/products match a name, present the options and ask the user to choose.';
        $parts[] = '- For status updates, always confirm the current status before changing.';

        return implode("\n", $parts);
    }

    private function detectRole(string $workspaceId, string $userId): ?string
    {
        return DB::table('workspace_memberships as wm')
            ->join('membership_roles as mr', 'mr.membership_id', '=', 'wm.id')
            ->join('roles as r', 'r.id', '=', 'mr.role_id')
            ->where('wm.workspace_id', $workspaceId)
            ->where('wm.user_id', $userId)
            ->value('r.role_key');
    }
}
