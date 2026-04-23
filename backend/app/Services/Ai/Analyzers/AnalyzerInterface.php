<?php
namespace App\Services\Ai\Analyzers;

/**
 * All analyzers implement this interface.
 *
 * Each returns an array of recommendation data arrays.
 */
interface AnalyzerInterface
{
    /**
     * Run analysis for a workspace.
     *
     * @return array[] Each element is a recommendation array with keys:
     *   category, title, description, impact_level, confidence_score,
     *   reasoning, data_triggers, expected_impact, action_type, action_payload,
     *   related_entities, analyzer, dedup_key
     */
    public function analyze(string $workspaceId): array;
}
