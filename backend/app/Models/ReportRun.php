<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $report_template_id
 * @property string $data_source
 * @property string|null $run_by_membership_id
 * @property string $status  completed|failed
 * @property array|null $parameters
 * @property array|null $result_summary
 * @property int $row_count
 * @property string|null $error_message
 * @property \Carbon\Carbon|null $started_at
 * @property \Carbon\Carbon|null $finished_at
 */
class ReportRun extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'report_template_id', 'data_source',
        'run_by_membership_id', 'status', 'parameters',
        'result_summary', 'row_count', 'error_message',
        'started_at', 'finished_at',
    ];

    protected function casts(): array
    {
        return [
            'parameters'     => 'array',
            'result_summary' => 'array',
            'row_count'      => 'integer',
            'started_at'     => 'datetime',
            'finished_at'    => 'datetime',
        ];
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(ReportTemplate::class, 'report_template_id');
    }

    public function runByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'run_by_membership_id');
    }
}
