<?php

namespace App\Listeners;

use App\Events\AiActionConfirmed;
use App\Events\InvoiceCreated;
use App\Events\PaymentRecorded;
use App\Events\SubscriptionActivated;
use App\Events\SubscriptionExpired;
use App\Events\TrialStarted;
use App\Mail\AiActionConfirmationMail;
use App\Mail\InvoiceCreatedMail;
use App\Mail\PaymentReceivedMail;
use App\Mail\SubscriptionActivatedMail;
use App\Mail\SubscriptionExpiredMail;
use App\Mail\TrialStartedMail;
use App\Services\Email\EmailService;
use Illuminate\Events\Dispatcher;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Subscribes to domain events and dispatches emails through EmailService.
 *
 * Deduplication is handled by EmailService's dedup_key mechanism.
 */
class EmailEventSubscriber
{
    public function __construct(
        private readonly EmailService $email,
    ) {}

    /**
     * Register the listeners.
     */
    public function subscribe(Dispatcher $events): array
    {
        return [
            InvoiceCreated::class        => 'handleInvoiceCreated',
            PaymentRecorded::class       => 'handlePaymentRecorded',
            TrialStarted::class          => 'handleTrialStarted',
            SubscriptionActivated::class => 'handleSubscriptionActivated',
            SubscriptionExpired::class   => 'handleSubscriptionExpired',
            AiActionConfirmed::class     => 'handleAiActionConfirmed',
        ];
    }

    public function handleInvoiceCreated(InvoiceCreated $event): void
    {
        $contact = DB::table('contacts')->where('id', $event->contactId)->first();
        if (! $contact?->email) {
            Log::info("InvoiceCreated: no email for contact {$event->contactId}");
            return;
        }

        $this->email->send(
            $event->workspaceId,
            $contact->email,
            $contact->name,
            new InvoiceCreatedMail(
                $contact->name,
                $event->invoiceNumber,
                $event->totalAmount,
                $event->dueDate,
            ),
            'invoice_created',
            [
                'event_name'          => 'InvoiceCreated',
                'actor_user_id'       => $event->actorUserId,
                'related_entity_type' => 'invoice',
                'related_entity_id'   => $event->invoiceId,
            ],
        );
    }

    public function handlePaymentRecorded(PaymentRecorded $event): void
    {
        $contact = DB::table('contacts')->where('id', $event->contactId)->first();
        if (! $contact?->email) return;

        $this->email->send(
            $event->workspaceId,
            $contact->email,
            $contact->name,
            new PaymentReceivedMail(
                $contact->name,
                $event->amount,
                $event->invoiceNumber,
                $event->method,
            ),
            'payment_received',
            [
                'event_name'          => 'PaymentRecorded',
                'actor_user_id'       => $event->actorUserId,
                'related_entity_type' => 'payment',
                'related_entity_id'   => $event->paymentId,
            ],
        );
    }

    public function handleTrialStarted(TrialStarted $event): void
    {
        $email = $event->ownerEmail ?? $this->getWorkspaceOwnerEmail($event->workspaceId);
        if (! $email) return;

        $this->email->send(
            $event->workspaceId,
            $email,
            $event->workspaceName,
            new TrialStartedMail($event->workspaceName, $event->trialEndDate),
            'trial_started',
            [
                'event_name'          => 'TrialStarted',
                'related_entity_type' => 'subscription',
                'related_entity_id'   => $event->workspaceId,
            ],
        );
    }

    public function handleSubscriptionActivated(SubscriptionActivated $event): void
    {
        $email = $event->ownerEmail ?? $this->getWorkspaceOwnerEmail($event->workspaceId);
        if (! $email) return;

        $this->email->send(
            $event->workspaceId,
            $email,
            $event->workspaceName,
            new SubscriptionActivatedMail($event->workspaceName, $event->planName),
            'subscription_activated',
            [
                'event_name'          => 'SubscriptionActivated',
                'related_entity_type' => 'subscription',
                'related_entity_id'   => $event->workspaceId,
            ],
        );
    }

    public function handleSubscriptionExpired(SubscriptionExpired $event): void
    {
        $email = $event->ownerEmail ?? $this->getWorkspaceOwnerEmail($event->workspaceId);
        if (! $email) return;

        $this->email->send(
            $event->workspaceId,
            $email,
            $event->workspaceName,
            new SubscriptionExpiredMail($event->workspaceName),
            'subscription_expired',
            [
                'event_name'          => 'SubscriptionExpired',
                'related_entity_type' => 'subscription',
                'related_entity_id'   => $event->workspaceId,
            ],
        );
    }

    public function handleAiActionConfirmed(AiActionConfirmed $event): void
    {
        $user = DB::table('users')->where('id', $event->userId)->first();
        if (! $user?->email) return;

        $this->email->send(
            $event->workspaceId,
            $user->email,
            $user->full_name ?? 'User',
            new AiActionConfirmationMail(
                $user->full_name ?? 'User',
                $event->changeType,
                $event->summary,
            ),
            'ai_action_confirmed',
            [
                'event_name'          => 'AiActionConfirmed',
                'actor_user_id'       => $event->userId,
                'related_entity_type' => 'ai_change_request',
                'related_entity_id'   => $event->actionId,
            ],
        );
    }

    private function getWorkspaceOwnerEmail(string $workspaceId): ?string
    {
        $owner = DB::table('workspace_memberships')
            ->join('users', 'users.id', '=', 'workspace_memberships.user_id')
            ->where('workspace_memberships.workspace_id', $workspaceId)
            ->where('workspace_memberships.status', 'active')
            ->orderBy('workspace_memberships.created_at')
            ->select('users.email')
            ->first();

        return $owner?->email;
    }
}
