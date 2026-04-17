<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class PlatformPlan extends Model
{
    use HasUuids;

    protected $table = 'platform_plans';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'name', 'slug', 'description',
        'max_employees', 'max_workspaces',
        'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'max_employees' => 'integer',
            'max_workspaces' => 'integer',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function prices(): HasMany
    {
        return $this->hasMany(PlatformPlanPrice::class, 'plan_id');
    }

    public function activePrices(): HasMany
    {
        return $this->prices()->where('is_active', true);
    }

    public function features(): HasMany
    {
        return $this->hasMany(PlanFeature::class, 'plan_id');
    }
}
