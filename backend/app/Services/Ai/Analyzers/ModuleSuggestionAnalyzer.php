<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class ModuleSuggestionAnalyzer implements AnalyzerInterface
{
    /**
     * Suggests modules that should be enabled based on business type and data patterns.
     */
    public function analyze(string $workspaceId): array
    {
        $config = DB::table('workspace_configurations')
            ->where('workspace_id', $workspaceId)
            ->first();

        $enabledModules = $config ? (is_string($config->enabled_modules) ? json_decode($config->enabled_modules, true) : $config->enabled_modules) : [];

        $recommendations = [];

        // Check if inventory module should be enabled
        $hasProducts = DB::table('products')->where('workspace_id', $workspaceId)->where('is_deleted', false)->exists();
        if ($hasProducts && !in_array('inventory', $enabledModules)) {
            $recommendations[] = $this->buildRec(
                $workspaceId,
                'Enable Inventory Management module',
                'You have products but the inventory module is not enabled. Enabling it allows tracking stock levels, warehouses, and receiving low-stock alerts.',
                'enable_module',
                ['module' => 'inventory'],
                'module_inventory',
            );
        }

        // Check if reporting module should be enabled
        $invoiceCount = DB::table('invoices')->where('workspace_id', $workspaceId)->count();
        if ($invoiceCount >= 5 && !in_array('reporting', $enabledModules)) {
            $recommendations[] = $this->buildRec(
                $workspaceId,
                'Enable Reporting module',
                "You have {$invoiceCount} invoices. The reporting module provides revenue analysis, aging reports, and business insights.",
                'enable_module',
                ['module' => 'reporting'],
                'module_reporting',
            );
        }

        // Check if manufacturing module should be enabled
        $hasBom = DB::table('bill_of_materials')->where('workspace_id', $workspaceId)->exists();
        if ($hasBom && !in_array('manufacturing', $enabledModules)) {
            $recommendations[] = $this->buildRec(
                $workspaceId,
                'Enable Manufacturing module',
                'You have bill of materials defined but the manufacturing module is not enabled. Enable it for production order management.',
                'enable_module',
                ['module' => 'manufacturing'],
                'module_manufacturing',
            );
        }

        return $recommendations;
    }

    private function buildRec(string $wsId, string $title, string $desc, string $actionType, array $payload, string $dedupSuffix): array
    {
        return [
            'category'         => 'erp',
            'title'            => $title,
            'description'      => $desc,
            'impact_level'     => 'medium',
            'confidence_score' => 85,
            'reasoning'        => "Analyzed workspace data patterns against enabled modules. The suggested module addresses a gap in the current configuration.",
            'data_triggers'    => json_encode($payload),
            'expected_impact'  => "Enabling this module adds capabilities that match your business activity.",
            'action_type'      => $actionType,
            'action_payload'   => json_encode($payload),
            'related_entities' => json_encode([]),
            'analyzer'         => 'ModuleSuggestionAnalyzer',
            'dedup_key'        => "module_suggestion:{$dedupSuffix}:" . now()->toDateString(),
        ];
    }
}
