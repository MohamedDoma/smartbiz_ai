# Step 59.2 — AI Tool Registry + Permission Guard Report

## Date
2026-07-11

---

## Summary

Implemented 6 read-only AI tools with permission-guarded execution, deterministic keyword routing, and full audit logging. AI can now answer business questions using real SmartBiz data, but only when the current user has the required permission.

---

## Files Created

| File | Purpose |
|------|---------|
| `backend/app/Services/Ai/AiToolRegistry.php` | Tool definitions, permission-guarded execution, DB queries, audit logging |
| `backend/app/Services/Ai/AiToolPermissionGuard.php` | Permission check using existing `PermissionResolver` |
| `backend/app/Models/AiToolCall.php` | Model for `ai_tool_calls` audit table |
| `backend/database/migrations/036_ai_tool_calls.php` | Migration for tool call audit table |

## Files Modified

| File | Change |
|------|--------|
| `backend/app/Services/Ai/AiGatewayService.php` | Added `AiToolRegistry` dependency, `membership` param to `chat()`, deterministic keyword pre-router, tool result injection into system prompt |
| `backend/app/Http/Controllers/Api/AiChatController.php` | Pass `membership` from `WorkspaceContextManager` to gateway |

## Frontend Files: No Changes Needed
The existing `/ai-chat` UI already renders AI responses as text. Tool results and permission denials come through as normal assistant messages.

---

## Tools Added

| # | Tool Name | Permission | Description |
|---|-----------|------------|-------------|
| 1 | `get_current_user_context` | none (authenticated) | User name, email, workspace, roles |
| 2 | `get_allowed_ai_tools` | none (authenticated) | List of tools the user can use |
| 3 | `get_workspace_basic_summary` | none (workspace member) | Workspace name, member count, departments, teams |
| 4 | `get_finance_summary` | `reports.view` | Invoice totals, payments, account balances |
| 5 | `get_inventory_summary` | `products.list` | Product count, active products, warehouses, low stock alerts |
| 6 | `get_pipeline_summary` | `contacts.list` | Pipeline count, deal records, won/lost/open, values |

---

## Permission Mapping

| Permission Key | Source | Used By |
|----------------|--------|---------|
| `reports.view` | `routes/api.php` L277-281 (ReportingController) | `get_finance_summary` |
| `products.list` | `routes/api.php` L162 (ProductController@index) | `get_inventory_summary` |
| `contacts.list` | `routes/api.php` L144 (ContactController@index) | `get_pipeline_summary` |

These are the exact permission keys already used by existing API route middleware.

---

## Approach: Deterministic Pre-Router (Not LLM Function Calling)

The tool routing uses keyword matching, not OpenAI function calling:

```
User message → mb_strtolower → keyword scan
  "مالية" or "finance" → get_finance_summary
  "مخزون" or "inventory" → get_inventory_summary
  "مبيعات" or "pipeline" → get_pipeline_summary
  "أدوات" or "tools" → get_current_user_context + get_allowed_ai_tools
  "مساحة العمل" or "workspace" → get_workspace_basic_summary
```

Each matched tool is:
1. Permission-checked via `AiToolPermissionGuard` → `PermissionResolver.can()`
2. Executed via direct DB query (read-only)
3. Result injected into system prompt as structured data
4. Logged to `ai_tool_calls` table

**Why not OpenAI function calling?** The current `callOpenAiChat()` uses standard Chat Completions API. Adding proper function calling requires provider changes (tool definitions in API request, tool_choice handling, multi-turn tool execution). This can be upgraded later — the deterministic approach is more predictable and secure for this initial step.

---

## Tool Call Logging

Table: `ai_tool_calls` (Migration 036)

Every tool invocation is logged with:
- `tool_name`, `status` (success/denied/failed)
- `workspace_id`, `user_id`, `conversation_id`
- `required_permission`, `denial_reason`
- `output_summary` (compact JSON)
- `duration_ms`, `error_message`
- `created_at`

---

## Security Enforcement

```
User asks "كم مدخول الشركة؟"
  → Keyword match: "مدخول" → get_finance_summary
  → AiToolPermissionGuard.check(membership, 'reports.view')
    → PermissionResolver.can(membership, 'reports.view')
      → denied? → Return denial message in Arabic
      → allowed? → Execute query, inject result
  → AI responds with real data OR permission denial
  → Tool call logged to ai_tool_calls
```

The LLM prompt is **never trusted** for authorization. Permission checks happen at the backend service layer before any data is queried.

---

## Allowed vs Denied Behavior

### Allowed (user has `reports.view`):
```
User: "كم ملخص المالية؟"
AI: "ملخص المالية الحالي:
- عدد الفواتير: 32
- إجمالي الإيرادات: 34,519.99 ريال سعودي
- المبلغ المدفوع: 1,150 ريال
..."
```

### Denied (user lacks permission):
```
User: "كم مدخول الشركة؟"
AI: "لا أستطيع عرض هذه المعلومة لأنها خارج صلاحياتك."
```

---

## Targeted Lint/Analyze Results

### Backend
```
✅ app/Services/Ai/AiToolRegistry.php — No syntax errors
✅ app/Services/Ai/AiToolPermissionGuard.php — No syntax errors
✅ app/Services/Ai/AiGatewayService.php — No syntax errors
✅ app/Models/AiToolCall.php — No syntax errors
✅ app/Http/Controllers/Api/AiChatController.php — No syntax errors
✅ database/migrations/036_ai_tool_calls.php — No syntax errors
✅ Migration 036 ran successfully
✅ Routes unchanged (POST /api/ai/chat → AiChatController@chat)
```

### Frontend
```
✅ lib/features/ai_chat/ — No issues
✅ lib/core/api/ai_service.dart — No issues
✅ lib/core/api/ai_models.dart — No issues
```

---

## Manual Test Steps

### A. Owner/Admin asks finance question:
```
كم ملخص المالية؟
```
Expected: Real finance data with invoice counts, revenue, payments.

### B. Ask about inventory:
```
اعطني ملخص المخزون
```
Expected: Product count, warehouses, active products.

### C. Ask about available tools:
```
ما الأدوات المتاحة لي؟
```
Expected: List of 6 tools with descriptions.

### D. Ask about workspace:
```
كم عدد أعضاء الفريق؟
```
Expected: Workspace name, member count, departments, teams.

### E. Normal chat (no tool trigger):
```
مرحبا كيف حالك
```
Expected: Normal AI response, no tools invoked.

### F. Super Admin → `/platform/usage`:
Expected: AI usage still works, tool calls visible in DB.

### G. Permission denial test:
Create a user with limited permissions, ask finance question.
Expected: "لا أستطيع عرض هذه المعلومة لأنها خارج صلاحياتك."

---

## Remaining Gaps

| Gap | Status |
|-----|--------|
| Full OpenAI function calling | Deferred — deterministic pre-router used instead |
| Write actions (create/update/delete) | Explicitly excluded per requirements |
| Tool call dashboard in frontend | Not implemented — data logged in DB |
| Pipeline permission enforcement | Using `contacts.list` as conservative proxy (pipelines lack own middleware) |
| AI onboarding | Not in scope |
| ERP blueprint | Not in scope |
