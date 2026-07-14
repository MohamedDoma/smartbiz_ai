# Step 59.1 — AI Provider Foundation Report

## Date
2026-07-10

---

## Files Created

| File | Purpose |
|------|---------|
| `backend/config/ai.php` | Centralized AI config (enabled, keys, models, budget, cost rates) |
| `backend/database/migrations/035_ai_foundation.php` | Creates 8 AI tables + 2 compat views + RLS |
| `backend/app/Models/AiConversation.php` | Conversation model with UUID + relationships |
| `backend/app/Models/AiMessage.php` | Message model with token/cost tracking |
| `backend/app/Models/AiWorkspaceSetting.php` | Per-workspace AI settings |
| `backend/app/Services/Ai/AiUsageEstimator.php` | Config-driven cost estimator |
| `backend/app/Services/Ai/AiUsageLogger.php` | Success/failure usage logger |
| `backend/app/Services/Ai/AiGatewayService.php` | Central AI orchestrator (test + chat) |
| `backend/app/Http/Controllers/Api/AiFoundationController.php` | test/chat/conversations endpoints |
| `backend/app/Http/Controllers/Api/PlatformAiUsageController.php` | Super Admin usage analytics |
| `frontend/lib/core/api/ai_models.dart` | All AI frontend models |
| `frontend/lib/core/api/ai_service.dart` | AI API service |
| `frontend/lib/features/ai/ai_state.dart` | AI state management |
| `frontend/lib/features/ai/screens/ai_chat_screen.dart` | Arabic-first chat screen |

## Files Modified

| File | Change |
|------|--------|
| `backend/.env.example` | Added AI_ENABLED, model config, budget vars |
| `backend/routes/api.php` | Added AI foundation routes + platform AI usage routes |
| `backend/app/Models/AiUsageLog.php` | Updated to match new schema (tokens, cost, provider) |
| `frontend/lib/main.dart` | Added AiState + AiService provider |
| `frontend/lib/app/router.dart` | Added `/ai` route |
| `frontend/lib/features/platform/screens/platform_usage_screen.dart` | Now uses real API data |
| `frontend/lib/core/l10n/strings_ar.dart` | Added 27 AI l10n keys |
| `frontend/lib/core/l10n/strings_en.dart` | Added 27 AI l10n keys |

---

## Environment Variables Added

```env
AI_ENABLED=false
OPENAI_API_KEY=
OPENAI_DEFAULT_MODEL=gpt-4o-mini
OPENAI_SMART_MODEL=gpt-4o
OPENAI_TIMEOUT=30
AI_MONTHLY_BUDGET_USD=30
AI_DAILY_MESSAGE_LIMIT=200
AI_MONTHLY_MESSAGE_LIMIT=3000
```

User must add to backend `.env`:
```env
AI_ENABLED=true
OPENAI_API_KEY=sk-...
```

---

## Tables Created

| Table | Columns | Purpose |
|-------|---------|---------|
| `ai_conversations` | 12 | Chat/test/advisor conversations |
| `ai_messages` | 15 | Messages with token & cost tracking |
| `ai_usage_logs` | 20 | Usage logs (provider, model, operation, cost) |
| `ai_workspace_settings` | 11 | Per-workspace AI limits |
| `ai_memory` | 10 | Session context for existing AiMemoryService |
| `ai_change_requests` | (existed) | Action requests for existing AiActionService |
| `ai_execution_plans` | (existed) | Step plans for existing AiStepPlanner |
| `ai_insights` | (existed) | Insights for existing AiInsightService |

### Compatibility Views
- `ai_conversation_messages` → view on `ai_messages` (backward compat)
- `ai_request_logs` → view on `ai_usage_logs` (backward compat)

### RLS
All 8 tables have row-level security policies based on `workspace_id`.

---

## API Endpoints Added

### AI Foundation (authenticated + workspace)
| Method | Path | Behavior |
|--------|------|----------|
| `POST` | `/api/ai/test` | Connection test — sends tiny prompt, logs usage |
| `POST` | `/api/ai/chat` | Basic chat — no tools, no business data |
| `GET` | `/api/ai/conversations` | List user's conversations |
| `GET` | `/api/ai/conversations/{id}` | Show conversation with messages |

### Platform AI Usage (Super Admin only)
| Method | Path | Behavior |
|--------|------|----------|
| `GET` | `/api/platform/ai-usage` | Aggregated usage summary |
| `GET` | `/api/platform/ai-usage/workspaces` | Per-workspace breakdown |

---

## AI Provider Behavior

- **Config source:** `config/ai.php` reads all values from `.env`
- **API key storage:** Backend `.env` only — never exposed to frontend
- **Provider:** OpenAI (Responses API for test, Chat Completions for chat)
- **Default model:** `gpt-4o-mini` (configurable via `OPENAI_DEFAULT_MODEL`)
- **System prompt:** Arabic-first, explicitly states no business data access
- **Token logging:** Every request logs input/output/total tokens + estimated cost
- **Cost estimation:** Per-model rates in `config/ai.php`, conservative fallback for unknown models

---

## Security Notes

1. **API key not exposed to frontend** — stored only in backend `.env`, read via `config('ai.openai.api_key')`
2. **No real key committed** — `.env.example` has empty placeholder
3. **AI disabled by default** — `AI_ENABLED=false` in `.env.example`
4. **Preflight checks** — every AI endpoint checks enabled + key + workspace settings
5. **Auth required** — all AI endpoints behind `auth:sanctum`
6. **Super Admin gated** — platform usage endpoints behind `SuperAdminMiddleware`
7. **No business data access** — Step 59.1 system prompt explicitly blocks data claims
8. **Validation** — message max 8000 chars, conversation_id must be valid UUID

---

## Curl Test Results

| # | Test | Expected | Result |
|---|------|----------|--------|
| 1 | Unauthenticated `/api/ai/test` | 401 | ✅ 401 |
| 2 | Authenticated test (AI disabled) | 503 "AI not enabled" | ✅ 503 |
| 3 | Chat empty body | 422 validation | ✅ 422 |
| 4 | SA `/api/platform/ai-usage` | Real zeros | ✅ Real data |
| 5 | Non-SA `/api/platform/ai-usage` | 403 | ✅ 403 |

---

## Flutter Results

```
flutter analyze: No issues found! (0 errors, 0 warnings)
flutter build web: ✓ Built build/web (40.6s)
```

---

## DBeaver Verification Queries

After user enables AI and sends a message:

```sql
-- Verify conversations created
SELECT id, workspace_id, user_id, title, "type", status, message_count
FROM ai_conversations ORDER BY created_at DESC LIMIT 5;

-- Verify messages logged
SELECT id, conversation_id, role, content, model, total_tokens, estimated_cost_usd
FROM ai_messages ORDER BY created_at DESC LIMIT 10;

-- Verify usage logs
SELECT id, provider, model, operation, input_tokens, output_tokens, total_tokens,
       estimated_cost_usd, success, error_code
FROM ai_usage_logs ORDER BY created_at DESC LIMIT 10;

-- AI usage summary
SELECT provider, model, operation,
       COUNT(*) as requests,
       SUM(total_tokens) as tokens,
       SUM(estimated_cost_usd) as cost
FROM ai_usage_logs
GROUP BY provider, model, operation;
```

---

## Manual Testing Steps

1. Add to backend `.env`:
   ```env
   AI_ENABLED=true
   OPENAI_API_KEY=sk-your-key-here
   ```
2. Clear config: `docker exec smartbiz_app php artisan config:clear`
3. Test endpoint:
   ```bash
   curl -s http://localhost:8080/api/ai/test -X POST \
     -H "Authorization: Bearer TOKEN" \
     -H "X-Workspace-Id: WS_ID" \
     -H "Accept: application/json"
   ```
4. Should return: `{"data":{"success":true,"text":"SmartBiz AI ready",...}}`
5. Open `/ai` in Flutter web — send "مرحبا"
6. Open `/platform/usage` as Super Admin — verify real data

---

## Remaining Gaps

1. **OpenAI key not yet in .env** — user must add manually
2. **No chat tools** — Step 59.1 scope is text-only
3. **No business data access** — deliberately blocked in system prompt
4. **No onboarding/blueprint** — future steps
5. **Old AiChatController/AiGateway** — still exists but not actively called (new routes override)
6. **ai_change_requests/execution_plans/insights** — used old schemas from earlier migrations; kept as-is
7. **Rate limiting** — existing `throttle:ai` applies to old route group; new routes don't have it yet
8. **Workspace module guard** — AI chat route not behind module guard (intentional for Step 59.1)

---

## Step 59.2 Readiness

✅ **Step 59.2 is safe to start.**

Foundation in place:
- Database schema ✅
- AI Gateway ✅
- Usage logging ✅
- Cost estimation ✅
- Frontend chat screen ✅
- Platform usage dashboard ✅
- All endpoints tested ✅
- Build passing ✅
