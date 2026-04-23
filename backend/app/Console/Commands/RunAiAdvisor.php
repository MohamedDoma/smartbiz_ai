<?php

namespace App\Console\Commands;

use App\Services\Ai\AiAdvisorService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class RunAiAdvisor extends Command
{
    protected $signature = 'ai:run-advisor';
    protected $description = 'Run AI advisor analysis for all active workspaces';

    public function handle(AiAdvisorService $advisor): int
    {
        $workspaces = DB::table('workspace_subscriptions')
            ->whereIn('status', ['active', 'trial'])
            ->pluck('workspace_id')
            ->unique();

        $totalRecs = 0;
        foreach ($workspaces as $wsId) {
            try {
                $recs = $advisor->runAnalysis($wsId);
                $totalRecs += count($recs);
                $this->info("Workspace {$wsId}: " . count($recs) . " recommendation(s)");
            } catch (\Throwable $e) {
                $this->error("Workspace {$wsId} failed: {$e->getMessage()}");
            }
        }

        $this->info("Total recommendations generated: {$totalRecs}");
        return self::SUCCESS;
    }
}
