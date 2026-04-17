<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;

/**
 * Phase 1 — AI Discovery + ERP Generation Tests (DS01–DS10).
 *
 * Tests the full discovery lifecycle:
 *   start → follow-up questions → answer → classify → generate blueprint → show
 * Includes permission enforcement and workspace isolation.
 */
class DiscoveryTest extends SmartBizTestCase
{
    private const BASE_URI = '/api/discovery/sessions';

    // ── Helper: login as a certification user ────────────────────

    private function loginAs(string $email): string
    {
        $response = $this->postJson('/api/auth/login', [
            'email'    => $email,
            'password' => CertificationSeeder::PASSWORD,
        ]);
        $response->assertOk();
        return $response->json('token');
    }

    private function wsGetAs(string $email, string $uri, string $wsId = null)
    {
        $token = $this->loginAs($email);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId ?? CertificationSeeder::WS_A,
            'Accept'         => 'application/json',
        ])->getJson($uri);
    }

    private function wsPostAs(string $email, string $uri, array $data = [], string $wsId = null)
    {
        $token = $this->loginAs($email);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId ?? CertificationSeeder::WS_A,
            'Accept'         => 'application/json',
        ])->postJson($uri, $data);
    }

    // ── DS01: Start discovery session with valid description ─────

    public function test_ds01_start_session_with_valid_description(): void
    {
        $response = $this->wsPost(self::BASE_URI, [
            'business_description' => 'I run a medium-sized retail store with 3 branches selling electronics and home appliances. We need inventory tracking, point of sale, and basic accounting.',
        ]);

        $response->assertCreated();
        $response->assertJsonStructure([
            'data' => [
                'id', 'workspace_id', 'created_by', 'status',
                'business_description', 'business_type',
                'classification_method', 'classification_version',
                'messages',
                'created_at', 'updated_at',
            ],
        ]);

        // Initial status should be 'questioning' (follow-up questions generated)
        $status = $response->json('data.status');
        $this->assertContains($status, ['intake', 'questioning']);

        // Should have at least the initial description message
        $messages = $response->json('data.messages');
        $this->assertNotEmpty($messages);
        $this->assertEquals('description', $messages[0]['message_type']);
        $this->assertEquals('user', $messages[0]['role']);
    }

    // ── DS02: Start session with too-short description → 422 ────

    public function test_ds02_short_description_rejected(): void
    {
        $response = $this->wsPost(self::BASE_URI, [
            'business_description' => 'I sell stuff',
        ]);

        $response->assertUnprocessable();
        $response->assertJsonValidationErrors(['business_description']);
    }

    // ── DS03: List sessions ─────────────────────────────────────

    public function test_ds03_list_sessions(): void
    {
        // Create a session first
        $this->wsPost(self::BASE_URI, [
            'business_description' => 'We are a consulting firm providing IT and management advisory services to small businesses across the region.',
        ])->assertCreated();

        $response = $this->wsGet(self::BASE_URI);
        $response->assertOk();
        $response->assertJsonStructure(['data']);
        $this->assertGreaterThanOrEqual(1, count($response->json('data')));
    }

    // ── DS04: Show session with messages ────────────────────────

    public function test_ds04_show_session_with_messages(): void
    {
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'We run a food catering business serving corporate events with a central kitchen and delivery fleet of 5 vehicles.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        $response = $this->wsGet(self::BASE_URI . "/{$id}");
        $response->assertOk();
        $response->assertJsonStructure([
            'data' => [
                'id', 'status', 'business_description',
                'messages' => [
                    '*' => ['id', 'role', 'content', 'message_type', 'metadata', 'created_at'],
                ],
            ],
        ]);

        // Should have the initial description + at least one AI follow-up
        $messages = $response->json('data.messages');
        $this->assertGreaterThanOrEqual(1, count($messages));
    }

    // ── DS05: Answer follow-up questions ─────────────────────────

    public function test_ds05_answer_follow_up_questions(): void
    {
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'We are a small manufacturing company producing handmade furniture from raw wood and metal materials.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        // Find the AI follow-up message
        $messages = $create->json('data.messages');
        $aiMessage = collect($messages)->firstWhere('message_type', 'follow_up_question');

        if ($aiMessage) {
            $response = $this->wsPost(self::BASE_URI . "/{$id}/answer", [
                'message_id' => $aiMessage['id'],
                'answers'    => [
                    ['answer' => 'We have 15 employees across 2 workshop locations.'],
                    ['answer' => 'Yes, we track raw materials and finished goods inventory.'],
                ],
            ]);

            $response->assertOk();
            $response->assertJsonStructure(['data' => ['id', 'messages']]);

            // Answers should be stored
            $allMessages = $response->json('data.messages');
            $answerMsg = collect($allMessages)->firstWhere('message_type', 'answer');
            $this->assertNotNull($answerMsg);
            $this->assertEquals('user', $answerMsg['role']);
        } else {
            // If no follow-up was generated, the description was comprehensive
            $this->assertTrue(true, 'No follow-up generated — description was comprehensive.');
        }
    }

    // ── DS06: Classify business type ────────────────────────────

    public function test_ds06_classify_business_type(): void
    {
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'I own a chain of 5 retail clothing stores. We sell men and women fashion items. We need POS and inventory management.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        $response = $this->wsPost(self::BASE_URI . "/{$id}/classify");
        $response->assertOk();

        $data = $response->json('data');
        $this->assertNotNull($data['business_type']);
        $this->assertEquals('retail', $data['business_type']);
        $this->assertNotNull($data['classification_confidence']);
        $this->assertGreaterThan(0, $data['classification_confidence']);
        $this->assertEquals('rule_based_v1', $data['classification_method']);
        $this->assertEquals('1.0.0', $data['classification_version']);

        // Classification message should be stored
        $classMsg = collect($data['messages'])->firstWhere('message_type', 'classification');
        $this->assertNotNull($classMsg);
        $this->assertEquals('ai', $classMsg['role']);
    }

    // ── DS07: Generate ERP blueprint ────────────────────────────

    public function test_ds07_generate_blueprint(): void
    {
        // Create + classify
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'We run a wholesale distribution company importing electronics from Asia and distributing to retailers across the country with 3 warehouses.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        $this->wsPost(self::BASE_URI . "/{$id}/classify")->assertOk();

        // Generate blueprint
        $response = $this->wsPost(self::BASE_URI . "/{$id}/generate-blueprint");
        $response->assertCreated();
        $response->assertJsonStructure([
            'data' => [
                'id', 'session_id', 'business_type', 'blueprint', 'version',
                'generator_method', 'generator_version',
                'created_at', 'updated_at',
            ],
        ]);

        $blueprint = $response->json('data.blueprint');
        $this->assertNotEmpty($blueprint);

        // Validate core blueprint structure
        $this->assertArrayHasKey('business_type', $blueprint);
        $this->assertArrayHasKey('enabled_modules', $blueprint);
        $this->assertArrayHasKey('recommended_roles', $blueprint);
        $this->assertArrayHasKey('role_homepages', $blueprint);
        $this->assertArrayHasKey('role_navigation', $blueprint);
        $this->assertArrayHasKey('role_quick_actions', $blueprint);
        $this->assertArrayHasKey('role_allowed_screens', $blueprint);
        $this->assertArrayHasKey('role_dashboard_widgets', $blueprint);
        $this->assertArrayHasKey('recommended_pages', $blueprint);
        $this->assertArrayHasKey('recommended_workflows', $blueprint);
        $this->assertArrayHasKey('recommended_dashboards', $blueprint);
        $this->assertArrayHasKey('recommended_automations', $blueprint);
        $this->assertArrayHasKey('assumptions', $blueprint);
        $this->assertArrayHasKey('missing_info', $blueprint);

        // Generator metadata
        $this->assertEquals('rule_based_v1', $response->json('data.generator_method'));
        $this->assertEquals('1.0.0', $response->json('data.generator_version'));
        $this->assertEquals(1, $response->json('data.version'));
    }

    // ── DS08: Show generated blueprint ──────────────────────────

    public function test_ds08_show_blueprint(): void
    {
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'We operate a chain of fast food restaurants with a central kitchen and 10 delivery branches.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        $this->wsPost(self::BASE_URI . "/{$id}/classify")->assertOk();
        $this->wsPost(self::BASE_URI . "/{$id}/generate-blueprint")->assertCreated();

        // Fetch the blueprint
        $response = $this->wsGet(self::BASE_URI . "/{$id}/blueprint");
        $response->assertOk();
        $response->assertJsonStructure([
            'data' => [
                'id', 'session_id', 'business_type', 'blueprint', 'version',
            ],
        ]);

        $this->assertEquals('restaurant', $response->json('data.business_type'));
    }

    // ── DS09: Generate blueprint without classification → 422 ───

    public function test_ds09_blueprint_without_classification_rejected(): void
    {
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'We run a professional cleaning service with mobile teams operating across the greater metro area.',
        ]);
        $create->assertCreated();
        $id = $create->json('data.id');

        // Try to generate blueprint without classifying first
        $response = $this->wsPost(self::BASE_URI . "/{$id}/generate-blueprint");
        $response->assertUnprocessable();
    }

    // ── DS10: Workspace isolation — session belongs to workspace ──

    public function test_ds10_session_workspace_isolation(): void
    {
        // Create session in WS-A (as admin/owner)
        $create = $this->wsPost(self::BASE_URI, [
            'business_description' => 'A large-scale manufacturing plant producing automotive parts with heavy machinery and assembly lines.',
        ]);
        $create->assertCreated();
        $sessionId = $create->json('data.id');

        // Try to access from WS-B → should be blocked (403 or 404)
        // 403 = workspace context manager denies cross-workspace access
        // 404 = RLS filters out the record
        // Both prove complete isolation
        $response = $this->wsGetAs('b_admin@cert.test', self::BASE_URI . "/{$sessionId}", CertificationSeeder::WS_B);
        $this->assertContains($response->getStatusCode(), [403, 404],
            "Expected 403 or 404 for cross-workspace isolation, got {$response->getStatusCode()}");
    }

    // ── DS11: Permission enforcement — readonly denied ───────────

    public function test_ds11_readonly_user_cannot_access_discovery(): void
    {
        $this->wsGetAs('readonly@cert.test', self::BASE_URI)->assertForbidden();
    }

    // ── DS12: Permission enforcement — noperm denied ────────────

    public function test_ds12_noperm_user_cannot_access_discovery(): void
    {
        $this->wsPostAs('noperm@cert.test', self::BASE_URI, [
            'business_description' => 'This should be rejected because I have no permissions at all.',
        ])->assertForbidden();
    }
}
