# Step 59.1.1 — AI Consolidation Cleanup Report

## Date
2026-07-11

---

## Duplicate Pieces Found

| Piece | Location | Source | Status |
|-------|----------|--------|--------|
| AI chat screen | `features/ai/screens/ai_chat_screen.dart` | Step 59.1 | **Quarantined** (file left on disk, not routed) |
| AI state | `features/ai/ai_state.dart` | Step 59.1 | **Kept** (platform usage depends on it) |
| AI service | `core/api/ai_service.dart` | Step 59.1 | **Kept** (platform usage depends on it via AiState) |
| AI models | `core/api/ai_models.dart` | Step 59.1 | **Kept** (platform usage depends on it) |
| `/ai` route | `router.dart` | Step 59.1 | **Changed to redirect** → `/ai-chat` |
| `/api/ai/chat` duplicate | `AiFoundationController@chat` | Step 59.1 | **Removed** from routes |

---

## Final Official Routes

### Frontend
| Route | Screen | Source |
|-------|--------|--------|
| `/ai-chat` | `features/ai_chat/ai_chat_screen.dart` | Original (pre-59.1) |
| `/ai` | **Redirects to `/ai-chat`** | Consolidated |
| `/platform/usage` | `platform_usage_screen.dart` | Step 59.1 (real data) |

### Backend
| Method | Path | Controller | Notes |
|--------|------|-----------|-------|
| `POST` | `/api/ai/chat` | `AiChatController@chat` | **Canonical** — old controller, one route |
| `POST` | `/api/ai/test` | `AiFoundationController@test` | Kept (non-conflicting) |
| `GET` | `/api/ai/conversations` | `AiFoundationController@conversations` | Kept (non-conflicting) |
| `GET` | `/api/ai/conversations/{id}` | `AiFoundationController@showConversation` | Kept |
| `GET` | `/api/ai/history` | `AiChatController@history` | Old (kept) |
| `GET` | `/api/platform/ai-usage` | `PlatformAiUsageController@summary` | Step 59.1 (kept) |
| `GET` | `/api/platform/ai-usage/workspaces` | `PlatformAiUsageController@workspaces` | Step 59.1 (kept) |

---

## What Happened to `/ai`

`/ai` now **redirects to `/ai-chat`** via `GoRoute.redirect`. No separate page.

---

## Which Frontend AI Screen Is Used

The **original** `features/ai_chat/ai_chat_screen.dart` at `/ai-chat`.

This screen is currently **mock-only** (no backend calls). It uses:
- `AiChatState` from `features/ai_chat/ai_chat_state.dart`
- `ChatMessage` model from `features/ai_chat/models/chat_models.dart`
- `ChatBubble` / `TypingIndicator` widgets from `features/ai_chat/widgets/chat_widgets.dart`

---

## Which Backend Controller Handles `/api/ai/chat`

**`AiChatController@chat`** — the original controller that uses the old `AiGateway` service.

---

## Which AI Service Performs OpenAI Calls

- **`AiGateway`** (old) — used by `AiChatController` for the chat flow. Depends on `LlmService` → `OpenAiProvider`.
- **`AiGatewayService`** (Step 59.1) — used by `AiFoundationController` for `/api/ai/test`. Has its own OpenAI HTTP calls with usage logging.

Both exist. They serve different endpoints. No conflict.

---

## Usage Logging Status

✅ **Still works.** `AiGatewayService` logs to `ai_usage_logs` table via `AiUsageLogger` for `/api/ai/test`.

The old `AiGateway` writes to `ai_request_logs` (now a view on `ai_usage_logs`) and `ai_conversation_messages` (now a view on `ai_messages`). Note: The old gateway's `trackUsage()` may fail at runtime because the view column mapping doesn't match the old insert columns. This is a pre-existing issue — the old mock frontend never actually calls the backend.

---

## Platform Usage Status

✅ **Still works.** `platform_usage_screen.dart` → `AiState.loadPlatformUsage()` → `AiService.getPlatformAiUsage()` → `GET /api/platform/ai-usage`.

No changes were made to this flow.

---

## Targeted Analyze/Lint Results

### Backend PHP Lint
```
✅ routes/api.php — No syntax errors
✅ AiChatController.php — No syntax errors
✅ AiFoundationController.php — No syntax errors
✅ AiGatewayService.php — No syntax errors
✅ AiConversation.php — No syntax errors
✅ AiMessage.php — No syntax errors
✅ AiUsageLog.php — No syntax errors
```

### Backend Route List
```
/api/ai/chat → AiChatController@chat (ONE route, no duplicate)
/api/ai/test → AiFoundationController@test (kept)
/api/ai/conversations → AiFoundationController (kept)
/api/platform/ai-usage → PlatformAiUsageController (kept)
Total: 15 AI routes, 0 conflicts
```

### Frontend Flutter Analyze
```
✅ router.dart — No issues
✅ main.dart — No issues
✅ features/ai_chat/ — No issues
✅ platform_usage_screen.dart — No issues
```

---

## Changes Made

### `backend/routes/api.php`
- Removed `Route::post('/chat', [AiFoundationController::class, 'chat'])` from AI Foundation block
- Added comment explaining `/chat` is handled by `AiChatController` above

### `frontend/lib/app/router.dart`
- Changed `/ai` from `pageBuilder` (loading duplicate screen) to `redirect: (_, __) => '/ai-chat'`
- Removed unused `import '../features/ai/screens/ai_chat_screen.dart' deferred as ai_chat_59`

---

## Files Left On Disk (Quarantined)

These files are no longer routed/imported but not deleted:
- `frontend/lib/features/ai/screens/ai_chat_screen.dart`

These files are kept because platform_usage_screen depends on them:
- `frontend/lib/features/ai/ai_state.dart`
- `frontend/lib/core/api/ai_service.dart`
- `frontend/lib/core/api/ai_models.dart`

---

## What User Should Manually Test

1. **Navigate to `/ai-chat`** — should show the original AI chat screen with mock responses
2. **Navigate to `/ai`** — should automatically redirect to `/ai-chat`
3. **Open Super Admin → Usage tab** — should show real AI usage data (zeros if no usage yet)
4. **Verify no console errors** when switching between routes
5. **Optional:** Call `POST /api/ai/test` from curl — should still work if `AI_ENABLED=true`
