# SmartBiz AI — Registration Contract Hardening Report

> **Date:** 2026-07-06 | **Step:** 42.5  
> **Scope:** Make phone_number required for registration, remove empty-string workaround

---

## Files Changed

| File | Change |
|---|---|
| `app/Http/Controllers/Api/AuthController.php` | phone_number validation: `nullable` → `required` with regex; removed `?? ''` fallback |

---

## Final Register Required Fields

| Field | Required | Validation |
|---|---|---|
| `full_name` | ✅ | string, max 255 |
| `email` | ✅ | email, unique, max 255 |
| `password` | ✅ | string, min 8, confirmed |
| `phone_number` | ✅ | string, min 7, max 30, regex: digits/+/-/spaces/parens/dot |
| `workspace_name` or `business_name` | ✅ (one of) | string, max 255 |
| `business_type` | optional | string, max 100 |
| `business_size` | optional | string, max 50 |
| `preferred_locale` | optional | `en` or `ar` |

---

## Phone Number Validation Rule

```php
'phone_number' => ['required', 'string', 'min:7', 'max:30', 'regex:/^[0-9+\-\s().]+$/'],
```

**Accepts:** `+218 91-234-5678`, `(091) 234.5678`, `0912345678`  
**Rejects:** `abc-phone`, `hello`, empty string

---

## Removed Workaround

```diff
- 'phone_number' => $validated['phone_number'] ?? '',
+ 'phone_number' => trim($validated['phone_number']),
```

No empty strings are stored. Phone number is validated and trimmed before storage.

---

## Curl Test Summary

| Test | Expected | Result |
|---|---|---|
| A. Register with valid phone `+218 91-234-5678` | 201 | ✅ token + session + phone stored correctly |
| B. Missing phone number | 422 | ✅ |
| C. Invalid phone `abc-phone` | 422 | ✅ |
| D. Duplicate email (with phone) | 422 | ✅ |
| E. Login with new user | 200 | ✅ |
| F. `/auth/me` with token | 200 | ✅ |
| G. `GET /api/products` with workspace | 200 | ✅ |

---

## Remaining Gaps

| # | Gap | When |
|---|---|---|
| 1 | Frontend register screen needs phone_number field + real API wiring | Step 43 |
| 2 | Phone number verification (SMS/OTP) | Future |
| 3 | Country code normalization / E.164 format | Future |

---

## Step 43 Readiness: ✅ SAFE TO START

Registration contract is now product-grade:
- ✅ Phone number required with format validation
- ✅ No empty-string workarounds
- ✅ All validation errors return proper 422
- ✅ Session payload unchanged
- ✅ Login/me/workspace routes verified
