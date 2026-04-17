<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AiCreditTransaction extends Model
{
    use HasUuids;

    protected $table = 'ai_credit_transactions';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id', 'transaction_type', 'bucket',
        'credits', 'balance_after', 'description',
        'reference_type', 'reference_id', 'actor_id',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'credits' => 'integer',
            'balance_after' => 'integer',
            'created_at' => 'datetime',
        ];
    }
}
