<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Step 59.2 — AI Tool Call audit log.
 *
 * @property string $id
 * @property string|null $workspace_id
 * @property string|null $user_id
 * @property string|null $conversation_id
 * @property string|null $message_id
 * @property string $tool_name
 * @property string $status        // success, denied, failed
 * @property string|null $required_permission
 * @property string|null $denial_reason
 * @property array|null $input_payload
 * @property array|null $output_summary
 * @property int $duration_ms
 * @property string|null $error_message
 */
class AiToolCall extends Model
{
    use HasUuids;

    protected $table = 'ai_tool_calls';

    protected $guarded = [];

    protected $casts = [
        'input_payload'  => 'array',
        'output_summary' => 'array',
        'duration_ms'    => 'integer',
    ];
}
