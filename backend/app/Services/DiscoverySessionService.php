<?php

namespace App\Services;

use App\Models\DiscoveryBlueprint;
use App\Models\DiscoveryMessage;
use App\Models\DiscoverySession;
use App\Services\Ai\LlmService;
use App\Services\Blueprint\BlueprintGenerator;
use App\Services\Blueprint\BlueprintSchema;
use App\Services\Blueprint\BlueprintValidator;
use App\Services\Discovery\DiscoveryAnalyzer;
use App\Services\Discovery\DiscoveryInformationCatalog;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class DiscoverySessionService
{
    /**
     * Supported business types that the BlueprintGeneratorService has templates for.
     * LLM classification results are normalized to one of these.
     */
    private const SUPPORTED_TYPES = [
        'retail', 'restaurant', 'service', 'manufacturing', 'distribution', 'hybrid',
    ];

    private DiscoveryAnalyzer $analyzer;

    public function __construct(
        private readonly BlueprintGeneratorService $blueprintGenerator,
        private readonly BlueprintGenerator        $canonicalGenerator,
        private readonly BlueprintValidator         $canonicalValidator,
        private readonly ?LlmService              $llm = null,
    ) {
        $this->analyzer = new DiscoveryAnalyzer($this->llm);
    }

    // ═══════════════════════════════════════════════════════════════
    //  LLM-enhanced methods (with rule-based fallback)
    // ═══════════════════════════════════════════════════════════════

    /**
     * LLM-enhanced classification: uses LLM to classify business type.
     * Falls back to rule-based if LLM is unavailable or returns invalid data.
     *
     * The result is always normalized to a supported business type.
     */
    public function classifyWithLlm(DiscoverySession $session): array
    {
        if (! $this->llm) {
            return $this->blueprintGenerator->classifyBusiness($session->business_description, $this->gatherContext($session));
        }

        try {
            $context = $this->gatherContext($session);
            $contextStr = implode("\n", array_map(fn($c) => "- {$c['content']}", $context));

            $supportedList = implode(', ', self::SUPPORTED_TYPES);
            $response = $this->llm->chat([
                ['role' => 'system', 'content' => "You are a business classification expert. Classify the business type from the description. Return ONLY a JSON object with keys: business_type (string), confidence (int 0-100), reasoning (string). Valid types: {$supportedList}. You MUST choose from this exact list."],
                ['role' => 'user', 'content' => "Business description: {$session->business_description}\n\nAdditional context:\n{$contextStr}"],
            ], ['temperature' => 0.1, 'max_tokens' => 200]);

            $parsed = json_decode($response->content, true);
            if ($parsed && isset($parsed['business_type'])) {
                $normalizedType = $this->normalizeBusinessType($parsed['business_type']);

                return [
                    'business_type' => $normalizedType,
                    'confidence'    => max(0, min(100, (int) ($parsed['confidence'] ?? 80))),
                    'method'        => 'llm_classification',
                    'version'       => '1.0.0',
                    'provider'      => $response->provider,
                    'model'         => $response->model,
                    'reasoning'     => $parsed['reasoning'] ?? null,
                ];
            }

            Log::warning('LLM classification returned invalid JSON, falling back to rule-based', [
                'content' => $response->content,
            ]);
        } catch (\Throwable $e) {
            Log::warning('LLM classification failed, falling back to rule-based', ['error' => $e->getMessage()]);
        }

        return $this->blueprintGenerator->classifyBusiness($session->business_description, $this->gatherContext($session));
    }

    // ═══════════════════════════════════════════════════════════════
    //  Public API
    // ═══════════════════════════════════════════════════════════════

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
     *
     * Uses adaptive AI analysis to extract facts from the description and
     * generate only the most relevant follow-up question.
     *
     * If an active session already exists for this workspace (in intake or
     * questioning status), it is returned instead of creating a duplicate.
     */
    public function startSession(string $workspaceId, string $userId, string $description, string $locale = 'ar'): DiscoverySession
    {
        // Reuse an existing active session if one is in early stages
        // or awaiting blueprint generation (blueprint_ready without a blueprint)
        $existing = DiscoverySession::where('workspace_id', $workspaceId)
            ->whereIn('status', ['intake', 'questioning', 'blueprint_ready'])
            ->orderByDesc('created_at')
            ->first();

        if ($existing) {
            return $existing->load('messages');
        }

        return DB::transaction(function () use ($workspaceId, $userId, $description, $locale) {
            $session = DiscoverySession::create([
                'workspace_id'         => $workspaceId,
                'created_by'           => $userId,
                'status'               => 'intake',
                'business_description' => $description,
            ]);

            // Store the initial description as a user message
            $userMsg = DiscoveryMessage::create([
                'session_id'   => $session->id,
                'workspace_id' => $workspaceId,
                'role'         => 'user',
                'content'      => $description,
                'message_type' => 'description',
                'metadata'     => ['source' => 'initial_intake'],
            ]);
            $userMsgId = $userMsg->id;

            // Run adaptive analysis on the initial description
            $messages = [['role' => 'user', 'content' => $description, 'message_type' => 'description', 'metadata' => []]];
            $analysis = $this->analyzer->analyze($description, $messages, [], [], $locale);

            // Save discovery state (includes locale)
            $state = $this->buildState($analysis, [], $locale);
            $session->update(['discovery_state' => $state]);

            // ── One message per turn ─────────────────────────────
            // The analyzer returns visible_message (ack+question) OR null (ready).
            // Save exactly one assistant message, never both.
            // Idempotency is per user-message ID, not per session.
            if ($analysis['ready_for_blueprint']) {
                $session->update(['status' => 'questioning']);
                $this->saveReadyMessage($session, $locale, $userMsgId);
            } elseif (!empty($analysis['visible_message'])) {
                $this->saveVisibleMessage($session, $analysis, $userMsgId);
                $session->update(['status' => 'questioning']);
            } elseif (isset($analysis['next_question'])) {
                // Edge case: visible_message was empty but next_question exists
                $this->saveQuestionMessage($session, $analysis['next_question'], $userMsgId);
                $session->update(['status' => 'questioning']);
            }

            return $session->load('messages');
        });
    }

    /**
     * Process answers submitted by the user.
     * Answers reference the follow-up message by message_id.
     *
     * Uses adaptive analysis to update facts and determine the next action.
     *
     * @throws \InvalidArgumentException if the message is not found or session is in wrong state
     */
    public function submitAnswers(DiscoverySession $session, string $messageId, array $answers, string $locale = 'ar'): DiscoverySession
    {
        // Guard: cannot submit answers after classification or completion
        if (in_array($session->status, ['blueprint_ready', 'completed'])) {
            throw new \InvalidArgumentException('Cannot submit answers after session has been classified or completed.');
        }

        return DB::transaction(function () use ($session, $messageId, $answers, $locale) {
            // Validate message belongs to session
            $questionMsg = DiscoveryMessage::where('id', $messageId)
                ->where('session_id', $session->id)
                ->where('message_type', 'follow_up_question')
                ->first();

            if (! $questionMsg) {
                throw new \InvalidArgumentException('Follow-up message not found in this session.');
            }

            // Store the user's answers
            $userMsg = DiscoveryMessage::create([
                'session_id'   => $session->id,
                'workspace_id' => $session->workspace_id,
                'role'         => 'user',
                'content'      => implode("\n", array_map(
                    fn($a) => $a['answer'],
                    $answers
                )),
                'message_type' => 'answer',
                'metadata'     => [
                    'in_reply_to' => $messageId,
                    'answers'     => $answers,
                ],
            ]);
            $userMsgId = $userMsg->id;

            // Re-analyze the full conversation
            $allMessages = $this->loadMessagesForAnalysis($session);
            $currentState = $this->normalizeState($session->discovery_state ?? []);
            $askedCategories = $currentState['asked_categories'] ?? [];

            // Add the question category that was just answered
            $questionMeta = $questionMsg->metadata ?? [];
            if (isset($questionMeta['category'])) {
                $askedCategories[] = $questionMeta['category'];
                $askedCategories = array_values(array_unique($askedCategories));
            }

            // Restore locale from session state
            $sessionLocale = $currentState['locale'] ?? $locale;

            $analysis = $this->analyzer->analyze(
                $session->business_description,
                $allMessages,
                $currentState,
                $askedCategories,
                $sessionLocale,
            );

            // Update discovery state
            $state = $this->buildState($analysis, $askedCategories, $sessionLocale);
            $session->update(['discovery_state' => $state]);

            // ── One message per turn ─────────────────────────────
            // The analyzer returns visible_message (ack+question) OR null (ready).
            // Save exactly one assistant message, never both.
            // Idempotency is per user-message ID, not per session.
            if ($analysis['ready_for_blueprint']) {
                $this->saveReadyMessage($session, $sessionLocale, $userMsgId);
            } elseif (!empty($analysis['visible_message'])) {
                $this->saveVisibleMessage($session, $analysis, $userMsgId);
            } elseif (isset($analysis['next_question'])) {
                // Edge case: visible_message was empty but next_question exists
                $this->saveQuestionMessage($session, $analysis['next_question'], $userMsgId);
            }

            return $session->load('messages');
        });
    }

    /**
     * Classify the business type based on all session context.
     * Uses LLM-enhanced classification with rule-based fallback.
     *
     * If discovery_state has a business_type_hint, uses that as additional signal.
     *
     * @throws \InvalidArgumentException if the session is already completed
     */
    public function classify(DiscoverySession $session): DiscoverySession
    {
        // Guard: don't re-classify completed sessions
        if ($session->status === 'completed') {
            throw new \InvalidArgumentException('Cannot classify a completed session.');
        }

        // Use LLM-enhanced classification (with automatic fallback)
        $result = $this->classifyWithLlm($session);

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
     * Uses canonical BlueprintGenerator + BlueprintValidator.
     * Invalid regeneration does NOT overwrite a valid existing blueprint.
     *
     * @throws \InvalidArgumentException if the session hasn't been classified or status is wrong
     * @throws \App\Exceptions\BlueprintValidationException if the generated blueprint fails validation
     */
    public function generateBlueprint(DiscoverySession $session): DiscoveryBlueprint
    {
        if (! $session->business_type) {
            throw new \InvalidArgumentException('Session must be classified before generating a blueprint.');
        }

        if (! in_array($session->status, ['blueprint_ready', 'completed'])) {
            throw new \InvalidArgumentException('Session must be in blueprint_ready status. Current status: ' . $session->status);
        }

        // Extract discovery state
        $state = $this->normalizeState($session->discovery_state ?? []);
        $knownFacts = $state['known_facts'] ?? [];
        $assumptions = $state['assumptions'] ?? [];

        // Generate canonical blueprint
        $blueprint = $this->canonicalGenerator->generate($session->business_type, $knownFacts, $assumptions);

        // Validate
        $result = $this->canonicalValidator->validate($blueprint);

        $existing = DiscoveryBlueprint::where('session_id', $session->id)->first();

        if (!$result['valid']) {
            // Do NOT overwrite a valid existing blueprint with an invalid one
            if ($existing) {
                throw new \App\Exceptions\BlueprintValidationException(
                    'Blueprint validation failed. Previous valid blueprint preserved.',
                    $result['errors'],
                    $result['warnings'],
                );
            }
            throw new \App\Exceptions\BlueprintValidationException(
                'Blueprint validation failed.',
                $result['errors'],
                $result['warnings'],
            );
        }

        // Store warnings in blueprint metadata
        if (!empty($result['warnings'])) {
            $blueprint['metadata']['validation_warnings'] = $result['warnings'];
        }

        return DB::transaction(function () use ($session, $blueprint, $existing) {
            if ($existing) {
                $oldVersion = $existing->version;
                $oldGeneratedAt = ($existing->blueprint['metadata']['generated_at'] ?? null);

                // Store revision history in new Blueprint metadata
                $blueprint['metadata']['previous_version'] = $oldVersion;
                if ($oldGeneratedAt) {
                    $blueprint['metadata']['previous_generated_at'] = $oldGeneratedAt;
                }

                $existing->update([
                    'blueprint'         => $blueprint,
                    'version'           => $oldVersion + 1,
                    'generator_method'  => 'canonical_v1',
                    'generator_version' => BlueprintSchema::VERSION,
                ]);
                $record = $existing;
            } else {
                $record = DiscoveryBlueprint::create([
                    'session_id'        => $session->id,
                    'workspace_id'      => $session->workspace_id,
                    'business_type'     => $session->business_type,
                    'blueprint'         => $blueprint,
                    'version'           => 1,
                    'generator_method'  => 'canonical_v1',
                    'generator_version' => BlueprintSchema::VERSION,
                ]);
            }

            $record->refresh();

            DiscoveryMessage::create([
                'session_id'   => $session->id,
                'workspace_id' => $session->workspace_id,
                'role'         => 'ai',
                'content'      => 'ERP blueprint has been generated.',
                'message_type' => 'blueprint',
                'metadata'     => ['blueprint_id' => $record->id, 'version' => $record->version, 'schema_version' => BlueprintSchema::VERSION],
            ]);

            $session->update(['status' => 'completed']);

            return $record;
        });
    }

    /**
     * Validate a session's existing blueprint against the canonical schema.
     *
     * @return array{valid: bool, errors: array, warnings: array}
     */
    public function validateBlueprint(DiscoverySession $session): array
    {
        $bp = $session->blueprint;
        if (!$bp) {
            throw new \InvalidArgumentException('No blueprint exists for this session.');
        }

        $payload = $bp->blueprint ?? [];

        // Legacy format detection
        if (BlueprintSchema::isLegacyFormat($payload)) {
            return [
                'valid'    => false,
                'errors'   => ['schema_version' => ['Legacy blueprint format detected. Please regenerate.']],
                'warnings' => ['This blueprint was generated before schema v1.0.0 and must be regenerated.'],
                'is_legacy' => true,
            ];
        }

        $result = $this->canonicalValidator->validate($payload);

        return [
            'valid'    => $result['valid'],
            'errors'   => $result['errors'],
            'warnings' => $result['warnings'],
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════

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

    /**
     * Load all messages as simple arrays for the analyzer.
     */
    private function loadMessagesForAnalysis(DiscoverySession $session): array
    {
        $messages = DiscoveryMessage::where('session_id', $session->id)
            ->orderBy('created_at')
            ->get();

        $result = [];
        foreach ($messages as $msg) {
            $result[] = [
                'role'         => $msg->role,
                'content'      => $msg->content,
                'message_type' => $msg->message_type,
                'metadata'     => $msg->metadata ?? [],
            ];
        }
        return $result;
    }

    /**
     * Build the discovery_state JSON from analysis result.
     * Uses the 1.4.1 extended structure with backward compatibility.
     */
    private function buildState(array $analysis, array $askedCategories = [], string $locale = 'ar'): array
    {
        // Merge asked categories from analysis
        if (isset($analysis['next_question']['category'])) {
            $askedCategories[] = $analysis['next_question']['category'];
        }

        $evaluation = $analysis['evaluation'] ?? [];

        return [
            'known_facts'            => $analysis['known_facts'] ?? [],
            'business_type_hint'     => $analysis['business_type_hint'] ?? null,
            'contradictions'         => $analysis['contradictions'] ?? [],
            'assumptions'            => $analysis['assumptions'] ?? [],
            'explicitly_unknown'     => $analysis['explicitly_unknown'] ?? [],
            'critical_missing'       => $evaluation['critical_missing'] ?? [],
            'important_missing'      => $evaluation['important_missing'] ?? [],
            'optional_missing'       => $evaluation['optional_missing'] ?? [],
            'required_completeness'  => $evaluation['required_completeness'] ?? 0,
            'overall_completeness'   => $evaluation['overall_completeness'] ?? ($analysis['completeness'] ?? 0),
            // Keep 'completeness' for backward compatibility with resource
            'completeness'           => $evaluation['overall_completeness'] ?? ($analysis['completeness'] ?? 0),
            'ready_for_blueprint'    => $analysis['ready_for_blueprint'] ?? false,
            'asked_categories'       => array_values(array_unique($askedCategories)),
            'analysis_method'        => $analysis['analysis_method'] ?? 'unknown',
            'conversation_strategy'  => $analysis['conversation_strategy'] ?? [],
            'locale'                 => $locale,
            'version'                => '1.5.0',
        ];
    }

    /**
     * Normalize a discovery_state from any previous version to current structure.
     * Ensures backward compatibility with 1.4.0 states.
     */
    private function normalizeState(array $state): array
    {
        // Apply safe defaults for 1.4.1 fields missing in 1.4.0
        return array_merge([
            'known_facts'           => [],
            'business_type_hint'    => null,
            'contradictions'        => [],
            'assumptions'           => [],
            'explicitly_unknown'    => [],
            'critical_missing'      => [],
            'important_missing'     => [],
            'optional_missing'      => [],
            'required_completeness' => 0,
            'overall_completeness'  => 0,
            'completeness'          => 0,
            'ready_for_blueprint'   => false,
            'asked_categories'      => [],
            'analysis_method'       => 'unknown',
            'version'               => '1.4.0',
        ], $state);
    }

    /**
     * Save a follow-up question as an AI message.
     *
     * @param string|null $respondsToMessageId  The user message this responds to (idempotency key)
     */
    private function saveQuestionMessage(DiscoverySession $session, array $question, ?string $respondsToMessageId = null): void
    {
        if ($respondsToMessageId && $this->isResponseAlreadySaved($session, $respondsToMessageId)) {
            return;
        }

        $metadata = [
            'category'  => $question['category'] ?? 'general',
            'questions' => [$question],
        ];
        if ($respondsToMessageId) {
            $metadata['responds_to_message_id'] = $respondsToMessageId;
        }

        DiscoveryMessage::create([
            'session_id'   => $session->id,
            'workspace_id' => $session->workspace_id,
            'role'         => 'ai',
            'content'      => $question['question'],
            'message_type' => 'follow_up_question',
            'metadata'     => $metadata,
        ]);
    }

    /**
     * Save a "ready for blueprint" AI message.
     *
     * Idempotency: deduplicates by responds_to_message_id, NOT by session-wide
     * message_type. An old ready message from a previous turn does NOT suppress
     * the response to a new user message.
     *
     * @param string|null $respondsToMessageId  The user message this responds to (idempotency key)
     */
    private function saveReadyMessage(DiscoverySession $session, string $locale = 'ar', ?string $respondsToMessageId = null): void
    {
        if ($respondsToMessageId && $this->isResponseAlreadySaved($session, $respondsToMessageId)) {
            return;
        }

        $state = $session->discovery_state ?? [];
        $completeness = $state['overall_completeness'] ?? ($state['completeness'] ?? 0);

        $content = $locale === 'ar'
            ? 'لدي معلومات كافية لبناء النظام الخاص بشركتك. يمكنك الآن عرض المخطط ومراجعته.'
            : 'I have enough information to build your business system. You can now view and review the blueprint.';

        $metadata = [
            'completeness'        => $completeness,
            'ready_for_blueprint' => true,
        ];
        if ($respondsToMessageId) {
            $metadata['responds_to_message_id'] = $respondsToMessageId;
        }

        DiscoveryMessage::create([
            'session_id'   => $session->id,
            'workspace_id' => $session->workspace_id,
            'role'         => 'ai',
            'content'      => $content,
            'message_type' => 'ready',
            'metadata'     => $metadata,
        ]);
    }

    /**
     * Save the backend-composed visible assistant message.
     *
     * The visible_message is composed by DiscoveryAnalyzer from:
     *   acknowledgement (no questions) + next_question (standalone question)
     * This guarantees a clean, single-message response per turn.
     *
     * @param string|null $respondsToMessageId  The user message this responds to (idempotency key)
     */
    private function saveVisibleMessage(DiscoverySession $session, array $analysis, ?string $respondsToMessageId = null): void
    {
        $message = $analysis['visible_message'] ?? '';
        if (empty($message)) return;

        if ($respondsToMessageId && $this->isResponseAlreadySaved($session, $respondsToMessageId)) {
            return;
        }

        $metadata = [
            'analysis_method' => $analysis['analysis_method'] ?? 'unknown',
        ];
        if ($respondsToMessageId) {
            $metadata['responds_to_message_id'] = $respondsToMessageId;
        }

        // Include question category if available
        if (isset($analysis['next_question']['category'])) {
            $metadata['category'] = $analysis['next_question']['category'];
            $metadata['questions'] = [$analysis['next_question']];
        }

        // Include conversation strategy if available
        if (!empty($analysis['conversation_strategy'])) {
            $metadata['conversation_strategy'] = $analysis['conversation_strategy'];
        }

        DiscoveryMessage::create([
            'session_id'   => $session->id,
            'workspace_id' => $session->workspace_id,
            'role'         => 'ai',
            'content'      => $message,
            'message_type' => 'follow_up_question',
            'metadata'     => $metadata,
        ]);
    }

    /**
     * Check if an assistant response was already saved for a given user message.
     * Used for retry idempotency: prevents duplicate responses to the same user message.
     */
    private function isResponseAlreadySaved(DiscoverySession $session, string $respondsToMessageId): bool
    {
        return DiscoveryMessage::where('session_id', $session->id)
            ->where('role', 'ai')
            ->whereJsonContains('metadata->responds_to_message_id', $respondsToMessageId)
            ->exists();
    }

    /**
     * Check if a question has already been asked (duplicate protection).
     * Uses fact depth validation — a category with inadequate answers can be re-asked.
     */
    private function isQuestionDuplicate(DiscoverySession $session, array $question, array $state = []): bool
    {
        $category = $question['category'] ?? 'general';

        // Clarification questions are never duplicates
        if ($category === 'clarification') {
            return false;
        }

        // Check against existing AI messages in this session
        $existingQuestions = DiscoveryMessage::where('session_id', $session->id)
            ->where('role', 'ai')
            ->where('message_type', 'follow_up_question')
            ->get();

        $evaluator = new \App\Services\Discovery\DiscoveryReadinessEvaluator();
        $knownFacts = $state['known_facts'] ?? ($session->discovery_state['known_facts'] ?? []);

        foreach ($existingQuestions as $msg) {
            $meta = $msg->metadata ?? [];
            // Check category match — but only block if the category has meaningful coverage
            if (isset($meta['category']) && $meta['category'] === $category) {
                if ($evaluator->isGroupMeaningfullyCovered($category, $knownFacts)) {
                    return true;
                }
                // Category was asked but not meaningfully covered — allow re-asking
            }
            // Check exact text match
            $existingText = strtolower(trim($msg->content));
            $newText = strtolower(trim($question['question']));
            if ($existingText === $newText) {
                return true;
            }
        }

        return false;
    }

    /**
     * Normalize an LLM-returned business type to a supported value.
     *
     * Maps common synonyms/variations to the canonical supported types.
     * Falls back to 'service' if the type is completely unrecognized.
     */
    private function normalizeBusinessType(string $type): string
    {
        $type = strtolower(trim($type));

        // Direct match
        if (in_array($type, self::SUPPORTED_TYPES)) {
            return $type;
        }

        // Common synonym mapping
        $synonyms = [
            // Retail variants
            'shop'       => 'retail',
            'store'      => 'retail',
            'ecommerce'  => 'retail',
            'e-commerce' => 'retail',
            // Restaurant variants
            'food'        => 'restaurant',
            'cafe'        => 'restaurant',
            'catering'    => 'restaurant',
            'hospitality' => 'restaurant',
            'bakery'      => 'restaurant',
            // Service variants
            'services'    => 'service',
            'consulting'  => 'service',
            'professional'=> 'service',
            'agency'      => 'service',
            'general'     => 'service',
            'technology'  => 'service',
            'healthcare'  => 'service',
            'education'   => 'service',
            'real_estate' => 'service',
            'construction'=> 'service',
            'agriculture' => 'service',
            // Distribution variants
            'wholesale'   => 'distribution',
            'logistics'   => 'distribution',
        ];

        return $synonyms[$type] ?? 'service';
    }
}
