<?php

namespace App\Services;

use App\Models\Contact;
use App\Models\DuplicateMatch;
use App\Models\DuplicateRule;
use App\Models\PipelineRecord;
use Illuminate\Support\Str;

class DuplicateDetectionService
{
    /**
     * Check for duplicates based on active rules.
     * Returns ['blocked' => bool, 'matches' => array].
     */
    public function check(
        string $wsId,
        string $entityType,
        array $payload,
        ?string $excludeEntityId = null,
    ): array {
        $rules = DuplicateRule::where('workspace_id', $wsId)
            ->where('entity_type', $entityType)
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->get();

        $blocked = false;
        $matches = [];

        foreach ($rules as $rule) {
            $found = $this->findMatches($wsId, $entityType, $rule, $payload, $excludeEntityId);

            foreach ($found as $matchedId => $matchedFields) {
                // Only create/check match records when we have a real source entity
                if ($excludeEntityId) {
                    $existing = DuplicateMatch::where('workspace_id', $wsId)
                        ->where('entity_type', $entityType)
                        ->where('duplicate_rule_id', $rule->id)
                        ->where(function ($q) use ($excludeEntityId, $matchedId) {
                            $q->where(function ($q2) use ($excludeEntityId, $matchedId) {
                                $q2->where('source_entity_id', $excludeEntityId)->where('matched_entity_id', $matchedId);
                            })->orWhere(function ($q2) use ($excludeEntityId, $matchedId) {
                                $q2->where('source_entity_id', $matchedId)->where('matched_entity_id', $excludeEntityId);
                            });
                        })
                        ->first();

                    if (!$existing) {
                        DuplicateMatch::create([
                            'workspace_id'      => $wsId,
                            'duplicate_rule_id'  => $rule->id,
                            'entity_type'        => $entityType,
                            'source_entity_id'   => $excludeEntityId,
                            'matched_entity_id'  => $matchedId,
                            'match_fields'       => $matchedFields,
                            'match_score'        => 100,
                            'status'             => 'open',
                        ]);
                    }
                }

                $matches[] = [
                    'rule_id'           => $rule->id,
                    'rule_name'         => $rule->name,
                    'matched_entity_id' => $matchedId,
                    'match_fields'      => $matchedFields,
                    'match_score'       => 100,
                    'action'            => $rule->action,
                ];

                if ($rule->action === 'block') {
                    $blocked = true;
                }
            }
        }

        return ['blocked' => $blocked, 'matches' => $matches];
    }

    private function findMatches(
        string $wsId,
        string $entityType,
        DuplicateRule $rule,
        array $payload,
        ?string $excludeEntityId,
    ): array {
        $matchFields = $rule->match_fields;
        $strategy = $rule->match_strategy;

        return match ($entityType) {
            'contact'         => $this->matchContacts($wsId, $matchFields, $strategy, $payload, $excludeEntityId),
            'pipeline_record' => $this->matchPipelineRecords($wsId, $matchFields, $strategy, $payload, $excludeEntityId),
            default           => [],
        };
    }

    private function matchContacts(string $wsId, array $fields, string $strategy, array $payload, ?string $exclude): array
    {
        $results = [];

        try {
            \Illuminate\Support\Facades\DB::statement("SET app.workspace_id = '{$wsId}'");
        } catch (\Throwable $e) {
            // Ignore
        }

        $contacts = Contact::where('workspace_id', $wsId)
            ->when($exclude, fn ($q) => $q->where('id', '!=', $exclude))
            ->get();

        foreach ($contacts as $contact) {
            $matchedFields = [];
            $allMatch = true;

            foreach ($fields as $field) {
                $payloadVal = $payload[$field] ?? null;
                $contactVal = $contact->{$field} ?? null;

                if ($payloadVal === null || $contactVal === null) {
                    $allMatch = false;
                    break;
                }

                if ($this->valuesMatch($payloadVal, $contactVal, $strategy, $field)) {
                    $matchedFields[] = $field;
                } else {
                    $allMatch = false;
                    break;
                }
            }

            if ($allMatch && !empty($matchedFields)) {
                $results[$contact->id] = $matchedFields;
            }
        }

        return $results;
    }

    private function matchPipelineRecords(string $wsId, array $fields, string $strategy, array $payload, ?string $exclude): array
    {
        $results = [];

        try {
            // Set workspace context for RLS policies if applicable
            \Illuminate\Support\Facades\DB::statement("SET app.workspace_id = '{$wsId}'");
        } catch (\Throwable $e) {
            // Ignore — not all setups use RLS
        }

        $records = PipelineRecord::where('workspace_id', $wsId)
            ->when($exclude, fn ($q) => $q->where('id', '!=', $exclude))
            ->get();

        foreach ($records as $record) {
            $matchedFields = [];
            $allMatch = true;

            foreach ($fields as $field) {
                $payloadVal = $payload[$field] ?? null;
                $recordVal = $record->{$field} ?? null;

                if ($payloadVal === null || $recordVal === null) {
                    $allMatch = false;
                    break;
                }

                if ($this->valuesMatch($payloadVal, $recordVal, $strategy, $field)) {
                    $matchedFields[] = $field;
                } else {
                    $allMatch = false;
                    break;
                }
            }

            if ($allMatch && !empty($matchedFields)) {
                $results[$record->id] = $matchedFields;
            }
        }

        return $results;
    }

    private function valuesMatch(mixed $a, mixed $b, string $strategy, string $field): bool
    {
        if ($strategy === 'exact') {
            return (string) $a === (string) $b;
        }

        // normalized_exact
        $a = $this->normalize($a, $field);
        $b = $this->normalize($b, $field);

        return $a === $b && $a !== '';
    }

    private function normalize(mixed $value, string $field): string
    {
        $v = Str::lower(trim((string) $value));

        if (in_array($field, ['phone', 'phone_number'], true)) {
            $v = preg_replace('/[\s\-\(\)\+]/', '', $v);
        }

        return $v;
    }
}
