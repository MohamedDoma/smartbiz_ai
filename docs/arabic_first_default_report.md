# Step 50.6 — Arabic-First Default + RTL/L10n Audit

**Date:** 2026-07-08
**Status:** ✅ Complete

---

## 1. Files Modified

### Backend (inside Docker `smartbiz_app`)

| File | Change |
|---|---|
| `app/Http/Controllers/Api/AuthController.php` | Default `preferred_locale` changed from `'en'` to `'ar'` (user create, line 111) |
| `app/Http/Controllers/Api/AuthController.php` | Default `default_locale` changed from `'en'` to `'ar'` (workspace create, line 122) |
| `app/Http/Controllers/Api/WorkspaceInvitationController.php` | Default `preferred_locale` changed from `'en'` to `'ar'` (invite accept user create, line 323) |

### Frontend

| File | Change |
|---|---|
| `lib/core/l10n/app_localizations.dart` | `fromCode()` fallback: `AppLanguage.en` → `AppLanguage.ar` |
| `lib/core/l10n/app_localizations.dart` | `tr()` fallback when no context: `AppLanguage.en` → `AppLanguage.ar` |
| `lib/core/state/app_state.dart` | `_defaultUser.uiLanguage`: `AppLanguage.en` → `AppLanguage.ar` |
| `lib/core/state/app_state.dart` | `_defaultWorkspace.defaultLanguage/documentLanguage`: `en` → `ar` |
| `lib/core/state/app_state.dart` | `_applySession()` logic: flip to `preferredLocale == 'en' ? en : ar` |
| `lib/core/state/app_state.dart` | All mock sign-in methods: `AppLanguage.en` → `AppLanguage.ar` |

---

## 2. Backend Default Locale Behavior

- **Register without `preferred_locale`**: stores `ar` (verified via curl)
- **Register with `preferred_locale=en`**: stores `en` (verified via curl)
- **Invite accept without `preferred_locale`**: stores `ar` (code verified, not browser-tested)
- **Invite accept with `preferred_locale=en`**: stores `en` (code verified)
- **Validation**: `nullable|string|in:en,ar` — unchanged
- **Existing users**: not modified — users with `preferred_locale=en` keep English
- **Workspace `default_locale`**: new workspaces default to `ar`

## 3. Frontend Default Locale Behavior

- **First load (unauthenticated)**: Arabic, from `_defaultUser.uiLanguage = AppLanguage.ar`
- **After login/session restore**: respects backend `preferred_locale` — `en` users stay English
- **Register payload**: sends current UI language (`ar` by default)
- **Invite accept payload**: sends current UI language (`ar` by default)
- **`fromCode()` fallback**: unknown locale codes resolve to Arabic (not English)

## 4. RTL Behavior

- **Arabic active**: RTL layout applied automatically via `AppLanguage.ar.isRtl = true`
- **MaterialApp.locale**: set to `Locale('ar')` by default
- **Form inputs**: right-aligned with icons on right side
- **Buttons/links**: properly positioned for RTL
- **Sidebar/topbar**: direction handled by Flutter's built-in Directionality

## 5. Register Locale Behavior

- Frontend sends `"preferred_locale": "ar"` when no explicit user selection exists
- If user switches to English before registering, sends `"preferred_locale": "en"`
- Backend stores whichever value is sent; defaults to `ar` if missing

## 6. Invite Accept Locale Behavior

- Code path verified: sends current `_currentUser.uiLanguage` as `preferred_locale`
- Default is `ar` since unauthenticated state defaults to Arabic
- Not fully browser-tested in this step (requires creating invite + opening accept URL)

## 7. L10n Audit Summary

Critical screens audited for hardcoded English:
- **Splash**: uses `tr()` for tagline and loading text; brand "SmartBiz AI" kept as-is ✅
- **Login**: fully localized via `tr()` ✅
- **Register**: fully localized via `tr()` ✅
- **Forgot password**: fully localized via `tr()` ✅
- **Dashboard**: fully localized ✅
- **Employees/invite**: fully localized ✅
- **Role management**: fully localized (Step 50.5 keys) ✅
- **Employee roles**: fully localized ✅

No hardcoded English strings found in critical screens.

## 8. Backend Verification

```
No syntax errors detected in app/Http/Controllers/Api/AuthController.php
No syntax errors detected in app/Http/Controllers/Api/WorkspaceInvitationController.php
No syntax errors detected in app/Services/AuthSessionPayloadBuilder.php
No syntax errors detected in app/Models/User.php
Configuration cache cleared successfully.
Application cache cleared successfully.
```

### Curl Tests

| Test | Expected | Result |
|---|---|---|
| Register without `preferred_locale` | `ar` | ✅ `"preferred_locale":"ar"` |
| Register with `preferred_locale=en` | `en` | ✅ `"preferred_locale":"en"` |

## 9. Flutter Analyze Result

```
0 errors
0 warnings
8 info (pre-existing use_build_context_synchronously — unrelated to this step)
```

## 10. Browser/Manual Check Result

| Check | Result |
|---|---|
| Fresh app opens Arabic | ✅ Login screen shows "مرحباً بعودتك" |
| RTL layout active | ✅ Input icons right-aligned, checkbox right, links positioned correctly |
| Login screen Arabic | ✅ All labels, buttons, links in Arabic |
| Register screen Arabic | ✅ Verified by browser navigation to `#/register` |
| Language switch (top bar) | ✅ Available after login (labeled "EN"/"عربي") |
| Language switch on login/register | ⚠️ Not present — toggle only appears in app shell top bar |
| Dashboard Arabic after login | ✅ Verified in Step 50.5 (sidebar, labels, widgets in Arabic when `ar` active) |

## 11. Remaining Gaps

| Item | Priority | Notes |
|---|---|---|
| Language toggle on login/register | Low | Toggle only available after login; pre-auth users cannot switch language |
| Invite accept browser test | Low | Code verified, not browser-tested end-to-end |
| Existing users with `preferred_locale=en` | None | They keep English — no migration needed |
| Persist locale in local storage | Future | Currently locale resets on page refresh for unauthenticated users (always defaults to `ar`) |

## 12. Step 51 Readiness

✅ **Safe to start Step 51.** Arabic-first default is fully operational:
- Backend defaults to `ar` for new users and workspaces
- Frontend loads Arabic/RTL on first visit
- English remains fully available via user preference
- No regressions in existing functionality
