<?php

namespace App\Services\Discovery;

use App\Services\Ai\LlmService;
use Illuminate\Support\Facades\Log;

/**
 * Analyzes discovery conversation messages using a single intelligent LLM call.
 *
 * Each user message triggers exactly ONE LLM call that simultaneously:
 *  - extracts/updates structured business facts
 *  - produces a natural conversational response in the user's language
 *  - identifies the most valuable next question (or declares readiness)
 *  - adapts to user expertise and business complexity
 *
 * Readiness decisions are verified by DiscoveryReadinessEvaluator.
 * Deterministic fallback is used when LLM is unavailable.
 */
class DiscoveryAnalyzer
{
    private DiscoveryReadinessEvaluator $evaluator;

    public function __construct(
        private readonly ?LlmService $llm = null,
    ) {
        $this->evaluator = new DiscoveryReadinessEvaluator();
    }

    /**
     * Analyze the full conversation context and return structured analysis.
     *
     * @param string  $description      Initial business description
     * @param array   $messages         All conversation messages [{role, content, message_type, metadata}]
     * @param array   $currentState     Current discovery_state (or empty array for first analysis)
     * @param array   $askedCategories  Categories already asked about
     * @param string  $locale           User's locale ('ar'|'en')
     * @return array  Validated analysis result
     */
    public function analyze(
        string $description,
        array  $messages,
        array  $currentState,
        array  $askedCategories,
        string $locale = 'ar',
    ): array {
        $existingFacts = $currentState['known_facts'] ?? [];
        $existingContradictions = $currentState['contradictions'] ?? [];
        $existingAssumptions = $currentState['assumptions'] ?? [];
        $explicitlyUnknown = $currentState['explicitly_unknown'] ?? [];

        // Try single intelligent LLM call
        $rawAnalysis = null;
        if ($this->llm) {
            try {
                $rawAnalysis = $this->analyzeIntelligent(
                    $description, $messages, $existingFacts, $askedCategories, $locale,
                );
            } catch (\Throwable $e) {
                Log::warning('LLM analysis failed, using deterministic fallback', ['error' => $e->getMessage()]);
            }
        }

        // Deterministic fallback
        if (!$rawAnalysis) {
            $rawAnalysis = $this->analyzeDeterministic(
                $description, $messages, $existingFacts, $askedCategories, $locale,
            );
        }

        $mergedFacts = $rawAnalysis['known_facts'] ?? [];
        $typeHint = $rawAnalysis['business_type_hint'] ?? null;
        $analysisMethod = $rawAnalysis['analysis_method'] ?? 'unknown';
        $acknowledgement = $rawAnalysis['acknowledgement'] ?? null;
        $conversationStrategy = $rawAnalysis['conversation_strategy'] ?? [];

        // Detect latest user message for contradiction analysis
        $latestUserText = '';
        for ($i = count($messages) - 1; $i >= 0; $i--) {
            if (($messages[$i]['role'] ?? '') === 'user') {
                $latestUserText = $messages[$i]['content'] ?? '';
                break;
            }
        }

        // Contradiction detection
        $contradictions = $this->evaluator->detectContradictions(
            $existingFacts,
            $mergedFacts,
            $latestUserText,
            $existingContradictions,
        );

        // If explicit correction, apply the new values directly
        if ($this->evaluator->isExplicitCorrection($latestUserText)) {
            // New values win
        } else {
            // For unclear contradictions, keep the existing confirmed value
            foreach ($contradictions as $c) {
                if (($c['status'] ?? '') === 'needs_clarification') {
                    $field = $c['field'] ?? '';
                    if ($field && array_key_exists($field, $existingFacts) && $existingFacts[$field] !== null) {
                        $mergedFacts[$field] = $existingFacts[$field];
                    }
                }
            }
        }

        // Run readiness evaluation through the centralized evaluator
        $evaluation = $this->evaluator->evaluate(
            $mergedFacts,
            $typeHint,
            $contradictions,
            $existingAssumptions,
        );

        // ── Determine next question with critical-gap precedence ────
        $nextQuestion = null;
        $finalReady = $evaluation['ready_for_blueprint'];
        $criticalMissing = $evaluation['critical_missing'] ?? [];

        if (!$finalReady) {
            // Not ready — find the best next question
            $blockingContradictions = $evaluation['blocking_contradictions'] ?? [];
            if (!empty($blockingContradictions)) {
                $nextQuestion = $this->evaluator->contradictionQuestion($blockingContradictions[0]);
            } else {
                // Get the evaluator's critical-gap question (highest priority)
                $evaluatorQuestion = $this->evaluator->nextQuestionForGaps(
                    $evaluation, $askedCategories, $mergedFacts, $locale,
                );

                // Check if the AI provided a question
                $llmQuestion = $rawAnalysis['next_question'] ?? null;

                if (!empty($criticalMissing)) {
                    // Critical gaps exist — the question MUST target a critical gap
                    if ($llmQuestion && !empty($llmQuestion['question'])
                        && in_array($llmQuestion['category'] ?? 'general', $criticalMissing)) {
                        // AI question targets a critical gap — use it
                        $nextQuestion = $llmQuestion;
                    } elseif ($evaluatorQuestion
                        && in_array($evaluatorQuestion['category'] ?? '', $criticalMissing)) {
                        // Use evaluator's critical-gap question
                        $nextQuestion = $evaluatorQuestion;
                    } else {
                        // Fallback to any evaluator question
                        $nextQuestion = $evaluatorQuestion;
                    }
                } else {
                    // No critical gaps — prefer AI question, fallback to evaluator
                    if ($llmQuestion && !empty($llmQuestion['question'])) {
                        $nextQuestion = $llmQuestion;
                    } else {
                        $nextQuestion = $evaluatorQuestion;
                    }
                }
            }
        }

        // ── Final readiness invariant ────────────────────────────
        // Mutually exclusive: next_question and ready_for_blueprint
        if ($nextQuestion !== null) {
            $finalReady = false;
        }
        if ($finalReady && !empty($criticalMissing)) {
            // Safety: critical gaps still exist, cannot be ready
            $finalReady = false;
            $nextQuestion = $this->evaluator->nextQuestionForGaps(
                $evaluation, $askedCategories, $mergedFacts, $locale,
            );
        }
        if ($finalReady) {
            $nextQuestion = null;
        }

        // ── Compose the visible message (backend authority) ─────
        // The backend builds the final user-visible message, never
        // trusting the AI's combined free-text directly.
        $visibleMessage = $this->composeVisibleMessage(
            $acknowledgement, $nextQuestion, $finalReady, $locale,
        );

        return [
            'known_facts'            => $mergedFacts,
            'business_type_hint'     => $typeHint,
            'contradictions'         => $contradictions,
            'assumptions'            => $existingAssumptions,
            'explicitly_unknown'     => $explicitlyUnknown,
            'evaluation'             => $evaluation,
            'completeness'           => $evaluation['overall_completeness'],
            'ready_for_blueprint'    => $finalReady,
            'next_question'          => $nextQuestion,
            'visible_message'        => $visibleMessage,
            'conversation_strategy'  => $conversationStrategy,
            'analysis_method'        => $analysisMethod,
        ];
    }

    /**
     * Compose the final visible assistant message from strict components.
     *
     * When not ready: acknowledgement + next_question
     * When ready: null (session service saves a localized ready message)
     */
    private function composeVisibleMessage(
        ?string $acknowledgement,
        ?array  $nextQuestion,
        bool    $finalReady,
        string  $locale,
    ): ?string {
        if ($finalReady) {
            // Ready — session service will save its own ready message
            return null;
        }

        $parts = [];

        if ($acknowledgement) {
            $parts[] = trim($acknowledgement);
        }

        if ($nextQuestion && !empty($nextQuestion['question'])) {
            $parts[] = trim($nextQuestion['question']);
        }

        if (empty($parts)) {
            return null;
        }

        return implode("\n\n", $parts);
    }

    /**
     * Single intelligent LLM call — extracts facts AND generates the conversational response.
     *
     * Returns facts_update, assistant_message, next_question, strategy in ONE call.
     * Maximum OpenAI calls per user message: 1.
     */
    private function analyzeIntelligent(
        string $description,
        array  $messages,
        array  $existingFacts,
        array  $askedCategories,
        string $locale,
    ): ?array {
        $validKeys = DiscoveryInformationCatalog::allFactKeys();
        $validKeysList = implode(', ', $validKeys);

        // Build coverage summary for the AI
        $typeHint = $existingFacts['business_type_hint'] ?? null;
        $coverage = DiscoveryInformationCatalog::coverageSummary($typeHint, $existingFacts);
        $coverageJson = json_encode($coverage, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        // Build conversation transcript
        $transcript = '';
        foreach ($messages as $msg) {
            $role = $msg['role'] === 'user' ? 'User' : 'Assistant';
            $transcript .= "{$role}: {$msg['content']}\n";
        }

        $existingFactsJson = !empty($existingFacts) ? json_encode($existingFacts, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) : '{}';
        $askedStr = !empty($askedCategories) ? implode(', ', $askedCategories) : 'none';

        $languageInstruction = $locale === 'ar'
            ? 'LANGUAGE: Respond in Arabic. Use professional Arabic suitable for a business context. Preserve English business terms and proper nouns used by the user.'
            : 'LANGUAGE: Respond in English. Use clear, professional business English.';

        $systemPrompt = <<<PROMPT
You are a professional business consultant helping a client set up their business management system.
You are having a natural conversation to understand their business operations.

{$languageInstruction}

CONVERSATION PRINCIPLES:
- Never behave like a questionnaire or form.
- Never follow a fixed question sequence.
- Acknowledge the user's latest response naturally before asking anything new.
- Ask only ONE main question per response. Combine tightly related details when natural.
- Ask questions relevant to THIS specific business — not generic checklists.
- Never ask about information already provided.
- Adapt your vocabulary to the user's expertise level.
- Use simple language for non-technical users, precise business terms for experienced managers.
- Allow partial or conversational answers.
- Do not mention JSON, schemas, databases, APIs, completeness percentages, or technical system details.
- Sound like a professional advisor, not a data collector.

INFORMATION COVERAGE STATUS:
{$coverageJson}

VALID FACT KEYS (use ONLY these for facts_update):
{$validKeysList}

STRUCTURED EXTRACTION RULES:
- Extract facts from ALL messages in context, not just the latest.
- role_details: Array of {{name: string, headcount: int|null, department: string|null, responsibilities: string[]}}. Use the EXACT role names the user provides.
- warehouse_details: Array of {{name: string, purpose: string|null}}.
- pipeline_details: Array of {{name: string|null, stages: [{{name: string, order: int}}]}}.
- discount_approval_rules: Array of {{threshold_percent: number, operator: "greater_than", approver_role: string|null}}.
- approval_workflows: Array of {{type: string, entity_type: string|null, trigger: object|null, approver_role: string|null}}.
- commission_approval_required: boolean.
- For boolean facts use true/false. For counts use integers. For lists use arrays with specific values.
- NEVER invent business facts the user did not mention.
- Infer obvious facts when confidence is very high (e.g., a restaurant sells food).
- If the user corrects a previous answer, use the corrected value.

NEXT QUESTION INTELLIGENCE:
- Consider what information is most valuable for building a useful initial system.
- Different businesses need different information depth.
- A solo consultant does not need warehouses, departments, or approval workflows.
- A large organization needs deeper role, department, and approval details.
- A manufacturer needs production details; a service company may not need inventory.
- Do not ask about every possible feature — ask only what matters for this business.
- Stop asking when enough reliable information exists to create a useful initial system.
- Set ready_for_blueprint to true when you have sufficient understanding.
- Categories already covered (do not re-ask): {$askedStr}

Previously known facts:
{$existingFactsJson}

RESPONSE FORMAT RULES:
- "acknowledgement" is a SHORT natural response to what the user just said.
  It must NEVER contain a question. Maximum 2 sentences.
- "next_question" contains a standalone question as a separate field.
  It must be self-contained and not duplicate what is in the acknowledgement.
- If you believe enough information exists, set ready_for_blueprint to true
  and set next_question to null.

Return ONLY a JSON object with these exact keys:
{{
  "facts_update": {{ ... only valid fact keys with values extracted from the FULL conversation ... }},
  "business_type_hint": "retail|restaurant|service|manufacturing|distribution|hybrid|null",
  "acknowledgement": "A short acknowledgement of the user's response WITHOUT any question",
  "next_question": {{ "category": "category_key", "question": "One standalone follow-up question" }} or null,
  "ready_for_blueprint": true or false,
  "conversation_strategy": {{
    "user_expertise": "simple|standard|advanced",
    "business_complexity": "micro|small|medium|large|enterprise",
    "next_focus": "brief description of what to ask about next or null"
  }}
}}
PROMPT;

        $response = $this->llm->chat([
            ['role' => 'system', 'content' => $systemPrompt],
            ['role' => 'user', 'content' => $transcript],
        ], ['temperature' => 0.3, 'max_tokens' => 1500]);

        // Extract JSON from response (handle markdown code blocks)
        $content = $response->content;
        if (preg_match('/```(?:json)?\s*([\s\S]*?)```/', $content, $m)) {
            $content = $m[1];
        }
        $parsed = json_decode(trim($content), true);

        if (!$parsed || !isset($parsed['facts_update'])) {
            Log::warning('LLM intelligent analysis returned invalid JSON', ['content' => $response->content]);
            return null;
        }

        return $this->processIntelligentResult($parsed, $existingFacts, $askedCategories);
    }

    /**
     * Process and validate the intelligent LLM result.
     */
    private function processIntelligentResult(array $parsed, array $existingFacts, array $askedCategories): array
    {
        $validKeys = DiscoveryInformationCatalog::allFactKeys();

        // Merge facts: only accept valid keys
        $mergedFacts = $existingFacts;
        foreach (($parsed['facts_update'] ?? []) as $key => $value) {
            if (in_array($key, $validKeys) && $value !== null) {
                $mergedFacts[$key] = $value;
            }
        }

        // Validate business type hint
        $typeHint = $parsed['business_type_hint'] ?? ($mergedFacts['business_type_hint'] ?? null);
        if ($typeHint === 'null' || $typeHint === '') {
            $typeHint = null;
        }

        // Extract the AI's question as a standalone field
        $nextQuestion = null;
        if (isset($parsed['next_question']['question'])) {
            $nextQuestion = [
                'category' => $parsed['next_question']['category'] ?? 'general',
                'question' => $parsed['next_question']['question'],
            ];
        }

        // Normalize acknowledgement from strict or legacy format
        $acknowledgement = $parsed['acknowledgement'] ?? null;
        if (!$acknowledgement && isset($parsed['assistant_message'])) {
            // Legacy: assistant_message was a combined field.
            // Extract just the non-question part as acknowledgement.
            $legacy = $parsed['assistant_message'];
            if ($nextQuestion && !empty($nextQuestion['question'])) {
                // Try to separate acknowledgement from the embedded question
                $qText = $nextQuestion['question'];
                $pos = mb_strpos($legacy, $qText);
                if ($pos !== false) {
                    $acknowledgement = trim(mb_substr($legacy, 0, $pos));
                } else {
                    // Question not found in message — use first sentence as ack
                    $acknowledgement = $this->extractAcknowledgement($legacy);
                }
            } else {
                $acknowledgement = $legacy;
            }
        }

        // Clean acknowledgement: must not contain a question
        if ($acknowledgement) {
            $acknowledgement = $this->stripTrailingQuestions($acknowledgement);
        }

        // Extract conversation strategy
        $strategy = $parsed['conversation_strategy'] ?? [];

        return [
            'known_facts'           => $mergedFacts,
            'business_type_hint'    => $typeHint,
            'next_question'         => $nextQuestion,
            'acknowledgement'       => $acknowledgement,
            'conversation_strategy' => $strategy,
            'analysis_method'       => 'llm_intelligent',
        ];
    }

    /**
     * Deterministic analysis using keyword extraction.
     * Used when LLM is unavailable.
     */
    private function analyzeDeterministic(
        string $description,
        array  $messages,
        array  $existingFacts,
        array  $askedCategories,
        string $locale,
    ): array {
        $fullText = strtolower($description);
        foreach ($messages as $msg) {
            if ($msg['role'] === 'user') {
                $fullText .= ' ' . strtolower($msg['content']);
            }
        }

        $facts = $existingFacts;

        // Extract facts from text
        $facts = $this->extractKeywordFacts($fullText, $facts);

        // Infer business type
        $typeHint = $this->inferBusinessType($fullText);
        if ($typeHint) {
            $facts['business_type_hint'] = $typeHint;
        }

        // Find next question — use highest-value applicable missing category
        $nextCat = DiscoveryInformationCatalog::nextMissingCategory(
            $typeHint ?? ($facts['business_type_hint'] ?? null),
            $facts,
            $askedCategories
        );

        $nextQuestion = null;
        $acknowledgement = null;
        if ($nextCat) {
            // Generate a localized fallback question
            $hint = $nextCat['fallback_hint'] ?? $nextCat['label'];
            $nextQuestion = [
                'category' => $nextCat['key'],
                'question' => $locale === 'ar'
                    ? "أخبرني أكثر عن: {$hint}"
                    : "Please tell me more about: {$hint}",
            ];
            $acknowledgement = $locale === 'ar'
                ? 'شكرًا على المعلومات.'
                : 'Thank you for the information.';
        } else {
            $acknowledgement = $locale === 'ar'
                ? 'شكرًا، لدي معلومات كافية لبناء النظام.'
                : 'Thank you, I have enough information to build the system.';
        }

        return [
            'known_facts'           => $facts,
            'business_type_hint'    => $typeHint ?? ($facts['business_type_hint'] ?? null),
            'next_question'         => $nextQuestion,
            'acknowledgement'       => $acknowledgement,
            'conversation_strategy' => [
                'user_expertise'     => 'standard',
                'business_complexity'=> 'small',
                'next_focus'         => $nextCat['key'] ?? null,
            ],
            'analysis_method'       => 'deterministic',
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Acknowledgement / question separation helpers
    // ═══════════════════════════════════════════════════════════════

    /**
     * Extract the acknowledgement portion from a combined legacy message.
     * Takes the text up to and including the first sentence-ending punctuation.
     */
    private function extractAcknowledgement(string $text): string
    {
        // Match up to the first Arabic or English sentence ending
        if (preg_match('/^(.+?[.،:!؟\x{061F}])\s/u', $text, $m)) {
            return trim($m[1]);
        }
        // If no sentence boundary found, take first 200 chars
        return trim(mb_substr($text, 0, 200));
    }

    /**
     * Strip trailing questions from acknowledgement text.
     * Ensures the acknowledgement never ends with a question.
     */
    private function stripTrailingQuestions(string $text): string
    {
        $text = trim($text);
        if (empty($text)) return '';

        // Split into sentences (Arabic and English punctuation)
        $sentences = preg_split('/(?<=[.!؟\x{061F}،])\s+/u', $text);
        if (!$sentences) return $text;

        // Remove trailing sentences that are questions
        while (!empty($sentences)) {
            $last = trim(end($sentences));
            if ($this->isQuestion($last)) {
                array_pop($sentences);
            } else {
                break;
            }
        }

        $result = implode(' ', $sentences);
        return trim($result) ?: trim($text);
    }

    /**
     * Check if a sentence is a question (Arabic or English).
     */
    private function isQuestion(string $sentence): bool
    {
        $sentence = trim($sentence);
        if (empty($sentence)) return false;

        // Ends with question mark
        if (preg_match('/[?\x{061F}]\s*$/u', $sentence)) {
            return true;
        }

        // Common Arabic question starters
        $arabicStarters = ['هل ', 'ما ', 'ماذا ', 'كيف ', 'أين ', 'متى ', 'لماذا ', 'كم ', 'من '];
        foreach ($arabicStarters as $starter) {
            if (mb_strpos($sentence, $starter) === 0) {
                return true;
            }
        }

        // Common English question starters (case-insensitive)
        $lower = strtolower($sentence);
        $englishStarters = ['how ', 'what ', 'where ', 'when ', 'why ', 'who ', 'which ', 'do ', 'does ', 'is ', 'are ', 'can ', 'could ', 'would '];
        foreach ($englishStarters as $starter) {
            if (str_starts_with($lower, $starter)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Extract facts from text using keyword matching (deterministic fallback).
     */
    private function extractKeywordFacts(string $text, array $existing): array
    {
        $facts = $existing;

        // Scale
        if (preg_match('/(\d+)\s*(?:employee|staff|worker|team member|موظف)/i', $text, $m)) {
            $facts['employee_count'] = (int) $m[1];
        }
        if (preg_match('/(\d+)\s*(?:branch|location|office|store|outlet|فرع)/i', $text, $m)) {
            $facts['branch_count'] = (int) $m[1];
        }

        // Products & Services
        if (str_contains($text, 'product') || str_contains($text, 'sell') || str_contains($text, 'spare part') || str_contains($text, 'goods') || str_contains($text, 'منتج') || str_contains($text, 'بيع')) {
            $facts['sells_products'] = true;
        }
        if (str_contains($text, 'service') || str_contains($text, 'consulting') || str_contains($text, 'maintenance') || str_contains($text, 'repair') || str_contains($text, 'خدم') || str_contains($text, 'صيانة')) {
            $facts['sells_services'] = true;
        }

        // Sales channels
        $channels = [];
        if (str_contains($text, 'wholesale') || str_contains($text, 'جملة')) $channels[] = 'wholesale';
        if (str_contains($text, 'retail') || str_contains($text, 'walk-in') || str_contains($text, 'counter') || str_contains($text, 'معرض') || str_contains($text, 'متجر')) $channels[] = 'retail';
        if (str_contains($text, 'online') || str_contains($text, 'ecommerce') || str_contains($text, 'e-commerce') || str_contains($text, 'إلكتروني')) $channels[] = 'online';
        if (str_contains($text, 'pos') || str_contains($text, 'point of sale') || str_contains($text, 'نقطة بيع') || str_contains($text, 'كاشير')) {
            $facts['uses_pos'] = true;
            if (!in_array('retail', $channels)) $channels[] = 'retail';
        }
        if (!empty($channels)) $facts['sales_channels'] = $channels;

        // Inventory
        if (str_contains($text, 'inventory') || str_contains($text, 'stock') || str_contains($text, 'warehouse') || str_contains($text, 'مخزون') || str_contains($text, 'مستودع')) {
            $facts['uses_inventory'] = true;
        }
        if (preg_match('/(\d+)\s*(?:warehouse|مستودع)/i', $text, $m)) {
            $facts['warehouse_count'] = (int) $m[1];
        }

        // Finance
        if (str_contains($text, 'invoice') || str_contains($text, 'invoicing') || str_contains($text, 'فاتور')) {
            $facts['uses_invoicing'] = true;
        }
        if (str_contains($text, 'accounting') || str_contains($text, 'journal') || str_contains($text, 'ledger') || str_contains($text, 'محاسب')) {
            $facts['uses_accounting'] = true;
        }

        // Manufacturing
        if (str_contains($text, 'manufactur') || str_contains($text, 'assembl') || str_contains($text, 'factory') || str_contains($text, 'production line') || str_contains($text, 'مصنع') || str_contains($text, 'تصنيع')) {
            $facts['uses_manufacturing'] = true;
        }

        // Delivery
        if (str_contains($text, 'deliver') || str_contains($text, 'shipping') || str_contains($text, 'fleet') || str_contains($text, 'توصيل') || str_contains($text, 'شحن')) {
            $facts['uses_delivery'] = true;
        }

        // Restaurant-specific channels
        if (str_contains($text, 'dine-in') || str_contains($text, 'dine in') || str_contains($text, 'takeaway') || str_contains($text, 'take-away')) {
            $channels = $facts['sales_channels'] ?? [];
            if (str_contains($text, 'dine-in') || str_contains($text, 'dine in')) $channels[] = 'dine-in';
            if (str_contains($text, 'takeaway') || str_contains($text, 'take-away')) $channels[] = 'takeaway';
            $facts['sales_channels'] = array_values(array_unique($channels));
        }

        // Commissions
        if (str_contains($text, 'commission') || str_contains($text, 'عمول')) {
            $facts['uses_commissions'] = true;
        }

        // Approvals
        if (str_contains($text, 'approval') || str_contains($text, 'approve') || str_contains($text, 'موافق')) {
            $facts['needs_approvals'] = true;
        }

        // Customers
        if (str_contains($text, 'customer') || str_contains($text, 'client') || str_contains($text, 'buyer') || str_contains($text, 'عميل') || str_contains($text, 'زبون')) {
            $facts['customer_types'] = $facts['customer_types'] ?? ['general'];
        }

        // Suppliers
        if (str_contains($text, 'supplier') || str_contains($text, 'vendor') || str_contains($text, 'import') || str_contains($text, 'مورد') || str_contains($text, 'استيراد')) {
            $facts['has_suppliers'] = true;
        }

        // Tax
        if (str_contains($text, 'tax') || str_contains($text, 'vat') || str_contains($text, 'gst') || str_contains($text, 'ضريب')) {
            $facts['tax_requirements'] = 'mentioned';
        }

        // Payment methods
        $payments = [];
        if (str_contains($text, 'cash') || str_contains($text, 'نقد')) $payments[] = 'cash';
        if (str_contains($text, 'card') || str_contains($text, 'credit') || str_contains($text, 'بطاق')) $payments[] = 'card';
        if (str_contains($text, 'transfer') || str_contains($text, 'bank') || str_contains($text, 'تحويل')) $payments[] = 'bank_transfer';
        if (!empty($payments)) $facts['payment_methods'] = $payments;

        // Roles
        if (str_contains($text, 'role') || str_contains($text, 'permission') || str_contains($text, 'access') || str_contains($text, 'صلاحي') || str_contains($text, 'دور')) {
            $facts['needs_permissions'] = true;
        }

        return $facts;
    }

    /**
     * Infer business type from full text using keyword scoring.
     */
    private function inferBusinessType(string $text): ?string
    {
        $scores = [
            'retail' => 0,
            'restaurant' => 0,
            'service' => 0,
            'manufacturing' => 0,
            'distribution' => 0,
        ];

        $keywords = [
            'retail' => ['shop', 'store', 'retail', 'pos', 'point of sale', 'cashier', 'boutique', 'supermarket', 'grocery', 'ecommerce', 'متجر', 'معرض', 'محل'],
            'restaurant' => ['restaurant', 'cafe', 'food', 'kitchen', 'menu', 'dining', 'catering', 'bakery', 'dine-in', 'takeaway', 'مطعم', 'مقهى', 'مطبخ'],
            'service' => ['service', 'consulting', 'agency', 'freelance', 'professional', 'law firm', 'marketing', 'design', 'salon', 'clinic', 'coaching', 'خدم', 'استشار'],
            'manufacturing' => ['manufacturing', 'factory', 'production', 'assembly', 'fabrication', 'plant', 'raw material', 'bom', 'industrial', 'مصنع', 'تصنيع', 'إنتاج'],
            'distribution' => ['distribution', 'wholesale', 'distributor', 'logistics', 'supply chain', 'warehousing', 'shipping', 'import', 'export',
                              'spare parts', 'auto parts', 'automotive parts', 'dealer', 'importer', 'fulfillment', 'توزيع', 'جملة', 'استيراد'],
        ];

        foreach ($keywords as $type => $kws) {
            foreach ($kws as $kw) {
                if (str_contains($text, $kw)) {
                    $scores[$type] += 10;
                }
            }
        }

        $maxScore = max($scores);
        if ($maxScore === 0) return null;

        // Check for hybrid
        $topTypes = array_filter($scores, fn($s) => $s >= $maxScore * 0.7 && $s > 0);
        if (count($topTypes) > 1) return 'hybrid';

        return array_search($maxScore, $scores);
    }
}
