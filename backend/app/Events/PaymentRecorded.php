<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class PaymentRecorded
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $paymentId,
        public string $invoiceId,
        public string $invoiceNumber,
        public string $contactId,
        public float  $amount,
        public string $method,
        public ?string $actorUserId = null,
    ) {}
}
