<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class InvoiceCreated
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $invoiceId,
        public string $invoiceNumber,
        public string $contactId,
        public float  $totalAmount,
        public string $dueDate,
        public ?string $actorUserId = null,
    ) {}
}
