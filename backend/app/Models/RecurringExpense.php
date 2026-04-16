<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $category
 * @property float $amount
 * @property string $frequency    daily|weekly|monthly|quarterly|semi_annual|annual
 * @property string $next_due_date
 * @property bool $is_active
 */
class RecurringExpense extends Model
{
    use HasUuids;

    protected $table = 'recurring_expenses';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'category',
        'amount',
        'frequency',
        'next_due_date',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'amount'        => 'decimal:2',
            'next_due_date' => 'date',
            'is_active'     => 'boolean',
        ];
    }
}
