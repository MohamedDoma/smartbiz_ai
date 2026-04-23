<?php

namespace App\Services;

use App\Models\DiscoveryBlueprint;
use App\Models\DiscoveryMessage;
use App\Models\DiscoverySession;
use App\Services\Ai\LlmService;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class DiscoverySessionService
{
    public function __construct(
        private readonly BlueprintGeneratorService $blueprintGenerator,
        private readonly ?LlmService              $llm = null,
    ) {}

    /**
     * LLM-enhanced classification: uses LLM to classify business type.
     * Falls back to rule-based if LLM is unavailable.
     */
    public function classifyWithLlm(DiscoverySession $session): array
    {
        if (! $this->llm) {
            return $this->blueprintGenerator->classifyBusiness($session->business_description, $this->gatherContext($session));
        }

        try {
            $context = $this->gatherContext($session);
            $contextStr = implode("\n", array_map(fn($c) => "- {$c['content']}", $context));

            $response = $this->llm->chat([
                ['role' => 'system', 'content' => 'You are a business classification expert. Classify the business type from the description. Return ONLY a JSON object with keys: business_type (string), confidence (int 0-100), reasoning (string). Valid types: retail, restaurant, services, manufacturing, wholesale, healthcare, education, technology, logistics, hospitality, construction, agriculture, real_estate, consulting, general.'],
                ['role' => 'user', 'content' => "Business description: {$session->business_description}\n\nAdditional context:\n{$contextStr}"],
            ], ['temperature' => 0.1, 'max_tokens' => 200]);

            $parsed = json_decode($response->content, true);
            if ($parsed && isset($parsed['business_type'])) {
                return [
                    'business_type' => $parsed['business_type'],
                    'confidence'    => $parsed['confidence'] ?? 80,
                    'method'        => 'llm_classification',
                    'version'       => '1.0.0',
                    'provider'      => $response->provider,
                    'model'         => $response->model,
                    'reasoning'     => $parsed['reasoning'] ?? null,
                ];
            }
        } catch (\Throwable $e) {
            Log::warning('LLM classification failed, falling back to rule-based', ['error' => $e->getMessage()]);
        }

        return $this->blueprintGenerator->classifyBusiness($session->business_description, $this->gatherContext($session));
    }

    /**
     * LLM-enhanced follow-up question generation.
     */
    public function generateFollowUpsWithLlm(string $description, array $context = []): array
    {
        if (! $this->llm) {
            return $this->blueprintGenerator->generateFollowUpQuestions($description, $context);
        }

        try {
            $contextStr = implode("\n", array_map(fn($c) => "- {$c['content']}", $context));
            $response = $this->llm->chat([
                ['role' => 'system', 'content' => 'You are a business discovery expert. Generate follow-up questions to better understand this business. Return a JSON array of objects with keys: question (string), purpose (string). Max 5 questions. Focus on: business scale, key processes, team structure, technology needs, and compliance requirements.'],
                ['role' => 'user', 'content' => "Business: {$description}\n\nAlready gathered:\n{$contextStr}"],
            ], ['temperature' => 0.5, 'max_tokens' => 500]);

            $parsed = json_decode($response->content, true);
            if (is_array($parsed) && count($parsed) > 0) {
                return $parsed;
            }
        } catch (\Throwable $e) {
            Log::warning('LLM follow-up generation failed, falling back to rule-based', ['error' => $e->getMessage()]);
        }

        return $this->blueprintGenerator->generateFollowUpQuestions($description, $context);
    }

    /**
     * List all discovery sessions for a workspace.
     */
    public function list(string $workspaceId): Collection
    {
        return DiscoverySession::where('workspace_id', $workspaceId)
            ->orderByDesc('created_at')
            ->get();
    }

    /**
     * Find a session by ID + workspace, eager-loading messages + blueprint.
     */
    public function find(string $workspaceId, string $id): ?DiscoverySession
    {
        return DiscoverySession::where('workspace_id', $workspaceId)
            ->where('id', $id)
            ->with(['messages', 'blueprint'])
            ->first();
    }

    /**
     * Start a new discovery session with the initial business description.
     */
    public function startSession(string $workspaceId, string $userId, string $description): DiscoverySession
    {
        return DB::transaction(function () use ($workspaceId, $userId, $description) {
            $session = DiscoverySession::create([
                'workspace_id'         => $workspaceId,
                'created_by'           => $userId,
                'status'               => 'intake',
                'business_description' => $description,
            ]);

            // Store the initial description as a user message
            DiscoveryMessage::create([
                'session_id'   => $session->id,
                'workspace_id' => $workspaceId,
                'role'         => 'user',
                'content'      => $description,
                'message_type' => 'description',
                'metadata'     => ['source' => 'initial_intake'],
            ]);

            // Generate and store follow-up questions
            $questions = $this->blueprintGenerator->generateFollowUpQuestions($description);
            if (! empty($questions)) {
                DiscoveryMessage::create([
                    'session_id'   => $session->id,
                    'workspace_id' => $workspaceId,
                    'role'         => 'ai',
                    'content'      => implode("\n", array_map(
                        fn($q, $i) => ($i + 1) . ". " . $q['question'],
                        $questions, array_keys($questions)
                    )),
                    'message_type' => 'follow_up_question',
                    'metadata'     => ['questions' => $questions],
                ]);

                $session->update(['status' => 'questioning']);
            }

            return $session->load('messages');
        });
    }

    /**
     * Process answers submitted by the user.
     * Answers reference the follow-up message by message_id.
     */
    public function submitAnswers(DiscoverySession $session, string $messageId, array $answers): DiscoverySession
    {
        return DB::transaction(function () use ($session, $messageId, $answers) {
            // Validate message belongs to session
            $questionMsg = DiscoveryMessage::where('id', $messageId)
                ->where('session_id', $session->id)
                ->where('message_type', 'follow_up_question')
                ->first();

            if (! $questionMsg) {
                throw new \InvalidArgumentException('Follow-up message not found in this session.');
            }

            // Store the user's answers
            DiscoveryMessage::create([
                'session_id'   => $session->id,
                'workspace_id' => $session->workspace_id,
                'role'         => 'user',
                'content'      => implode("\n", array_map(
                    fn($a) => "- " . $a['answer'],
                    $answers
                )),
                'message_type' => 'answer',
                'metadata'     => [
                    'in_reply_to' => $messageId,
                    'answers'     => $answers,
                ],
            ]);

            // Check if more questions are needed
            $allContext = $this->gatherContext($session);
            $moreQuestions = $this->blueprintGenerator->generateFollowUpQuestions(
                $session->business_description,
                $allContext
            );

            if (! empty($moreQuestions)) {
                DiscoveryMessage::create([
                    'session_id'   => $session->id,
                    'workspace_id' => $session->workspace_id,
                    'role'         => 'ai',
                    'content'      => implode("\n", array_map(
                        fn($q, $i) => ($i + 1) . ". " . $q['question'],
                        $moreQuestions, array_keys($moreQuestions)
                    )),
                    'message_type' => 'follow_up_question',
                    'metadata'     => ['questions' => $moreQuestions],
                ]);
            }

            return $session->load('messages');
        });
    }

    /**
     * Classify the business type based on all session context.
     */
    public function classify(DiscoverySession $session): DiscoverySession
    {
        $context = $this->gatherContext($session);
        $result  = $this->blueprintGenerator->classifyBusiness($session->business_description, $context);

        $session->update([
            'status'                    => 'classifying',
            'business_type'             => $result['business_type'],
            'classification_confidence' => $result['confidence'],
            'classification_method'     => $result['method'],
            'classification_version'    => $result['version'],
        ]);

        // Store classification as an AI message
        DiscoveryMessage::create([
            'session_id'   => $session->id,
            'workspace_id' => $session->workspace_id,
            'role'         => 'ai',
            'content'      => "Business classified as: {$result['business_type']} (confidence: {$result['confidence']}%)",
            'message_type' => 'classification',
            'metadata'     => $result,
        ]);

        $session->update(['status' => 'blueprint_ready']);

        return $session->fresh(['messages', 'blueprint']);
    }

    /**
     * Generate the ERP blueprint for a classified session.
     */
    public function generateBlueprint(DiscoverySession $session): DiscoveryBlueprint
    {
        if (! $session->business_type) {
            throw new \InvalidArgumentException('Session must be classified before generating a blueprint.');
        }

        $context   = $this->gatherContext($session);
        $blueprint = $this->blueprintGenerator->generateBlueprint(
            $session->business_type,
            $session->business_description,
            $context,
        );

        // Upsert blueprint (unique per session)
        $existing = DiscoveryBlueprint::where('session_id', $session->id)->first();
        if ($existing) {
            $existing->update([
                'blueprint'         => $blueprint,
                'version'           => $existing->version + 1,
                'generator_method'  => 'rule_based_v1',
                'generator_version' => '1.0.0',
            ]);
            $record = $existing;
        } else {
            $record = DiscoveryBlueprint::create([
                'session_id'        => $session->id,
                'workspace_id'      => $session->workspace_id,
                'business_type'     => $session->business_type,
                'blueprint'         => $blueprint,
                'version'           => 1,
                'generator_method'  => 'rule_based_v1',
                'generator_version' => '1.0.0',
            ]);
        }

        // Refresh to pick up DB defaults
        $record->refresh();

        // Store blueprint message
        DiscoveryMessage::create([
            'session_id'   => $session->id,
            'workspace_id' => $session->workspace_id,
            'role'         => 'ai',
            'content'      => 'ERP blueprint has been generated.',
            'message_type' => 'blueprint',
            'metadata'     => ['blueprint_id' => $record->id, 'version' => $record->version],
        ]);

        $session->update(['status' => 'completed']);

        return $record;
    }

    /**
     * Gather all user-provided context from session messages.
     */
    private function gatherContext(DiscoverySession $session): array
    {
        $messages = DiscoveryMessage::where('session_id', $session->id)
            ->whereIn('message_type', ['description', 'answer'])
            ->orderBy('created_at')
            ->get();

        $context = [];
        foreach ($messages as $msg) {
            $context[] = [
                'type'    => $msg->message_type,
                'content' => $msg->content,
                'meta'    => $msg->metadata ?? [],
            ];
        }
        return $context;
    }
}
