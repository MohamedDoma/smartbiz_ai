<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ManualPayment extends Model
{
    use HasUuids;

    protected $table = 'manual_payments';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id', 'amount', 'currency', 'method', 'reference',
        'status', 'plan_id', 'billing_cycle', 'notes',
        'submitted_by', 'confirmed_by', 'confirmed_at', 'rejected_reason',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'amount'       => 'decimal:2',
            'confirmed_at' => 'datetime',
            'created_at'   => 'datetime',
        ];
    }

    public function workspace(): BelongsTo { return $this->belongsTo(Workspace::class); }
    public function plan(): BelongsTo { return $this->belongsTo(PlatformPlan::class, 'plan_id'); }
    public function submittedBy(): BelongsTo { return $this->belongsTo(User::class, 'submitted_by'); }
    public function confirmedBy(): BelongsTo { return $this->belongsTo(User::class, 'confirmed_by'); }
}
