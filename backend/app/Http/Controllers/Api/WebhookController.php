<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\StripeService;
use App\Services\WebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class WebhookController extends Controller
{
    public function __construct(
        private readonly WebhookService $webhooks,
        private readonly StripeService  $stripe,
    ) {}

    /**
     * POST /api/webhooks/stripe
     *
     * No auth — verified by Stripe signature.
     */
    public function handleStripe(Request $request): JsonResponse
    {
        abort_unless(config('services.stripe.enabled'), 404);

        $payload   = $request->getContent();
        $signature = $request->header('Stripe-Signature', '');

        try {
            $event = $this->stripe->constructWebhookEvent($payload, $signature);
        } catch (\UnexpectedValueException $e) {
            Log::warning('Invalid webhook payload: ' . $e->getMessage());
            return response()->json(['error' => 'Invalid payload'], 400);
        } catch (\Stripe\Exception\SignatureVerificationException $e) {
            Log::warning('Invalid webhook signature: ' . $e->getMessage());
            return response()->json(['error' => 'Invalid signature'], 400);
        }

        try {
            $this->webhooks->processEvent(
                $event->id,
                $event->type,
                $event->toArray(),
            );
        } catch (\Throwable $e) {
            Log::error('Webhook processing error: ' . $e->getMessage());
            // Return 200 anyway — Stripe will retry on 5xx
            return response()->json(['error' => 'Processing failed', 'event_id' => $event->id], 200);
        }

        return response()->json(['received' => true]);
    }
}
