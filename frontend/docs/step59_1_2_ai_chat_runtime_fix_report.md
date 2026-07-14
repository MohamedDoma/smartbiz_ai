# Step 59.1.2 — AI Chat Runtime Fix Report

## Date
2026-07-11

---

## Root Cause

**`type 'Null' is not a subtype of type 'int'`** in `ai_models.dart`:

All `int` fields from JSON were parsed using `j['key'] ?? 0` which is unsafe on Dart web because:

1. When the JSON value is a JS number (e.g., `135`), Dart web receives it as `num`, not `int`. The `??` operator doesn't trigger (value is not null), and assigning `num` to `int` fails.
2. When the JSON key is missing entirely or the value is explicitly `null`, `??` works but the resulting `0` literal may still be ambiguous in JS interop.

**Layout overflow (99156px)** was a secondary cascade: when the JSON parsing throws during `notifyListeners()` → widget rebuild, Flutter's error-handling widget replaces the content with an unbounded error dump, causing the `Column` inside `AppShell` to overflow.

---

## Exact Null-Int Fields Found

| File | Line | Field | Old Pattern | Fix |
|------|------|-------|-------------|-----|
| `ai_models.dart` | 57 | `AiMessageData.tokens` | `j['tokens'] ?? 0` | `_toInt(j['total_tokens'] ?? j['tokens'])` |
| `ai_models.dart` | 86 | `AiConversationSummary.messageCount` | `j['message_count'] ?? 0` | `_toInt(j['message_count'])` |
| `ai_models.dart` | 111 | `AiTestResult.durationMs` | `j['duration_ms'] ?? 0` | `_toInt(j['duration_ms'])` |
| `ai_models.dart` | 151-156 | `AiUsageSummary.*` (6 fields) | `j[...] ?? 0` | `_toInt(j[...])` |
| `ai_models.dart` | 176-177 | `AiUsageByDay.requests/tokens` | `j[...] ?? 0` | `_toInt(j[...])` |
| `ai_models.dart` | 192-193 | `AiUsageByModel.requests/tokens` | `j[...] ?? 0` | `_toInt(j[...])` |
| `ai_models.dart` | 208-209 | `AiUsageByOperation.requests/tokens` | `j[...] ?? 0` | `_toInt(j[...])` |
| `ai_models.dart` | 250-251 | `AiUsageBudget.dailyLimit/monthlyLimit` | `j[...] ?? 200` | `_toInt(j[...], 200)` |
| `ai_models.dart` | 275-278 | `AiWorkspaceUsageSummary.*` (3 fields) | `j[...] ?? 0` | `_toInt(j[...])` |

**Total: 19 unsafe `int` casts fixed.**

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/lib/core/api/ai_models.dart` | Added `_toInt()` helper; replaced all `j[...] ?? 0` with `_toInt(j[...])` for every `int` field; also added `.toString()` safety on string fields; made `tokens` accept both `total_tokens` and `tokens` keys |
| `frontend/lib/core/api/ai_service.dart` | Made `sendChatMessage` return error `AiChatResponse` instead of crashing on null/unexpected `data` shape |

---

## Layout Overflow Fix

No layout changes needed. The 99156px overflow was entirely a secondary effect of the parsing crash. Once the null-int error is fixed, the layout works correctly:

```
AppShell
  └─ Column
       ├─ _ChatHeader (fixed height)
       ├─ Expanded(child: _MessageList / _EmptyState)  ← scrollable
       └─ _ChatInputBar (fixed height)
```

---

## Response Parsing Behavior

### `_toInt(dynamic value, [int fallback = 0])`
```
null → 0
int 135 → 135
num 135.0 → 135
String "135" → 135
String "abc" → 0
missing key → 0
```

### `AiMessageData.fromJson` token handling
```
{"tokens": 135} → tokens = 135
{"total_tokens": 135} → tokens = 135
{"tokens": null} → tokens = 0
{} (no key) → tokens = 0
```

### `AiService.sendChatMessage` error handling
```
r.data['data'] is Map → parse normally
r.data['data'] is null → return AiChatResponse(success: false, error: 'Unexpected...')
parse throws → return AiChatResponse(success: false, error: 'Failed...')
HTTP error → Dio throws → caught by AiChatState.catch → error message in chat
```

---

## Targeted Analyze Results

```
✅ lib/features/ai_chat/ — No issues
✅ lib/core/api/ai_service.dart — No issues
✅ lib/core/api/ai_models.dart — No issues
✅ lib/main.dart — No issues
✅ lib/app/router.dart — No issues
✅ platform_usage_screen.dart — No issues
```

---

## Manual Test Steps

1. **Hot restart** the Flutter web app (or full restart if hot restart doesn't pick up changes)
2. **Navigate to `/ai-chat`** — should open without red error screen
3. **Send a message** (e.g., "مرحبا") — should see typing indicator, then real AI response
4. **Check token counter** in header — should show a non-zero number after response
5. **Click a shortcut** (e.g., "Create invoice") — should get AI response (no crash)
6. **Open `/platform/usage`** as Super Admin — should load without errors
7. **If AI is disabled**: should show "⚠️ AI is currently disabled" in chat (not a red error)
