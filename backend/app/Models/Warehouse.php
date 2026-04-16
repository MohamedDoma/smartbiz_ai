<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $branch_id
 * @property string $name
 * @property string|null $location
 */
class Warehouse extends Model
{
    use HasUuids;

    protected $table = 'warehouses';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id',
        'branch_id',
        'name',
        'location',
    ];
}
