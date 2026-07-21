<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * Seeds the complete deterministic fixture set required by the backend suite.
 *
 * This seeder is intentionally test-only. It combines the minimal workspace,
 * platform billing data, RBAC/isolation fixtures, and the demo workspace parent
 * record needed by configuration tests.
 */
class TestSuiteSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            FoundationSeeder::class,
            PlatformSeeder::class,
            CertificationSeeder::class,
        ]);

        // DemoWorkspaceConfigurationTest exercises only the configuration
        // seeding method, but the FK requires the parent workspace to exist.
        DB::table('workspaces')->insertOrIgnore([
            'id'                  => SmartBizDemoSeeder::WS,
            'name'                => 'SmartBiz Demo Test Workspace',
            'industry_type'       => 'automotive',
            'business_size'       => 'small',
            'subscription_status' => 'active',
            'default_locale'      => 'ar',
            'default_currency'    => SmartBizDemoSeeder::CUR,
            'timezone'            => 'Asia/Riyadh',
            'is_active'           => true,
            'created_at'          => now(),
            'updated_at'          => now(),
        ]);

        $this->command?->info('Complete backend test fixture set created.');
    }
}
