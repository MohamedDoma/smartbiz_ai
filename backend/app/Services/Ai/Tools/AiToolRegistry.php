<?php

namespace App\Services\Ai\Tools;

/**
 * Registry of AI-callable tools.
 *
 * Returns OpenAI-compatible function definitions filtered by user permissions.
 * Routes execution to ReadTools or ActionTools.
 */
class AiToolRegistry
{
    public function __construct(
        private readonly ReadTools   $readTools,
        private readonly ActionTools $actionTools,
    ) {}

    /**
     * Get all tool definitions the user is allowed to use.
     *
     * @param  string[]  $permissions  User's permission slugs
     * @return array  OpenAI-compatible tool definitions
     */
    public function getToolDefinitions(array $permissions): array
    {
        $tools = [];

        foreach ($this->allTools() as $tool) {
            if (empty($tool['permission']) || in_array($tool['permission'], $permissions, true)) {
                $tools[] = [
                    'type'     => 'function',
                    'function' => $tool['schema'],
                ];
            }
        }

        return $tools;
    }

    /**
     * Execute a tool by name.
     */
    public function executeTool(string $name, array $params, string $workspaceId, string $userId, ?string $conversationId = null): array
    {
        $readNames   = array_column($this->readTools->definitions(), 'name');
        $actionNames = array_column($this->actionTools->definitions(), 'name');

        if (in_array($name, $readNames, true)) {
            return $this->readTools->execute($name, $params, $workspaceId);
        }

        if (in_array($name, $actionNames, true)) {
            return $this->actionTools->execute($name, $params, $workspaceId, $userId, $conversationId);
        }

        return ['error' => "Unknown tool: {$name}"];
    }

    /**
     * Check if a tool name is an action (requires confirmation).
     */
    public function isActionTool(string $name): bool
    {
        return in_array($name, array_column($this->actionTools->definitions(), 'name'), true);
    }

    /**
     * All tool metadata with permission requirements.
     */
    private function allTools(): array
    {
        $tools = [];

        foreach ($this->readTools->definitions() as $def) {
            $tools[] = [
                'permission' => $def['permission'],
                'schema'     => $def['schema'],
            ];
        }

        foreach ($this->actionTools->definitions() as $def) {
            $tools[] = [
                'permission' => $def['permission'],
                'schema'     => $def['schema'],
            ];
        }

        return $tools;
    }
}
