<?php

namespace App\Services;

use App\Models\DiscoveryBlueprint;
use App\Models\DiscoveryMessage;
use App\Models\DiscoverySession;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class DiscoverySessionService
{
    public function __construct(
        private readonly BlueprintGeneratorService $blueprintGenerator,
    ) {}

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
