# CLINE OPERATING CHECKLIST
## BariWise + BBRS Mobile Platform — AI Session Protocol

> **Purpose:** A condensed, actionable step-by-step guide for any AI entering this project. Derived from the Grand Master Operating Manual (25 sections) and verified against actual code state.
>
> **Package:** `bari_wise` · **Primary theme:** `Colors.orange` · **Framework:** Flutter + Dart 3 + Material 3

---

## PHASE 0: SESSION STARTUP (Before touching any files)

1. **Read the Grand Master Operating Manual** — Sections 1–25, especially Rules 1.1–1.5 (authority, verification, separation, no architecture replacement, additive only).
2. **Confirm project identity:** Package `bari_wise`, primary theme `Colors.orange`. Never introduce `liver_wise` or liver-named artifacts.
3. **Read current project state:** Sections 17 (Architecture), 18 (Checklist Tracker), 19 (Feature Registry), 21 (Technical Debt), 23 (Session History), 25 (Next Task).
4. **Output a PROJECT STATE CONFIRMATION:**
   - Current app status (completed sections, active section)
   - Architecture summary (Screens → Providers → Controllers → Services → Repositories → Storage)
   - Known risks (from Section 21)
   - Next task (from Section 25, corrected if stale)
5. **Wait for user direction.** Do not modify files until instructed.

---

## PHASE 1: TASK IDENTIFICATION

1. **Identify the checklist section** from Section 25 (Next Task Rule). If stale, cross-reference with Section 18 (Living Checklist Tracker) to find the highest-numbered `⬜ NOT STARTED` or `🔄 IN PROGRESS` section.
2. **Identify required files** — listed in Section 25's "Required files" or inferred from the checklist sub-bullets.
3. **Identify dependencies** — check Section 17.4 (data sources), Section 17.5 (storage keys), Section 17.6 (routing), and Section 19 (Feature Registry) for existing services/models/providers the new work must integrate with.
4. **Identify verification plan** — what does "complete" look like for this section? Cross-reference Section 14 (Regression Protection): ✅ Implemented ✅ Integrated ✅ Compiles ✅ Matches architecture ✅ Matches UI system ✅ No regression.

---

## PHASE 2: FEATURE VERIFICATION (Before writing any code)

1. **Read the real requirement** — identify checklist section, title, sub-bullets, required behavior.
2. **Inspect existing implementation** — read actual files; never assume based on filenames. Distinguish Verified vs. Reported vs. Unknown (Rule 1.2).
3. **Output a FEATURE VERIFICATION block:**
   - Checklist Section
   - Current File(s)
   - Already Implemented (verified)
   - Missing (not yet done)
   - Potential Risks
   - Recommended Action
4. **Output a DECISION REQUIRED block:**
   - Recommended plan
   - What it preserves
   - What it adds
   - What it modifies
5. **Await approval** — unless the user has established a continuing execution workflow ("keep going," "continue through the checklist").

---

## PHASE 3: DEPENDENCY CHECK (Before writing each file)

1. **Verify imports exist** — every `import` statement must resolve to a real file.
2. **Verify models exist** — every model class referenced must be defined in `lib/models/`.
3. **Verify services exist** — every service called must be defined in `lib/services/`.
4. **Verify providers exist** — every provider referenced must be defined and registered.
5. **Verify routes exist** — every route name must be in `main.dart`'s `routes` table (lines 565–604).
6. **If anything is missing:** STOP and output a `DEPENDENCY BLOCK` naming the missing file, expected location, and reason needed. Do not proceed.

---

## PHASE 4: IMPLEMENTATION

1. **Follow the architecture chain:** UI → Providers → Controllers → Services → Repositories → Storage. Never bypass layers.
2. **Use full file rewrites** (Rule 6.1) — complete files with complete imports, classes, and methods. No patches, no diffs, no partial files.
3. **Check file size before rewriting:**
   - Over 5,000 lines → output `LARGE FILE WARNING`
   - Over 7,000 lines → output `EXTREME FILE WARNING` with options (reduce scope / split file / user-approved patch mode)
4. **Additive only** (Rule 1.5): Preserve → Add missing capability → Integrate minimally → Verify no regression. Prefer adding methods/widgets/screens/services over rewriting.
5. **No gratuitous cleanup** (Rule 4.2) — don't rename, reorganize imports, reformat, or modernize unrelated code.
6. **Dart 3 + null safety + Material 3** — new code must compile cleanly with no analyzer warnings.
7. **Theme consistency** (Rule 13) — use `Colors.orange`. If a UI mismatch is found, add to Technical Debt and notify the user. Do not silently fix or ignore.

---

## PHASE 5: INTEGRATION

1. **Register routes** in `main.dart` if the new page needs navigation (lines 565–604).
2. **Wire into navigation** — check `app_drawer.dart`, `home_screen.dart`, `main_navigation.dart` (if in scope) for drawer/rail entries.
3. **Connect to existing services** — use existing service classes, don't create parallel implementations.
4. **Share storage keys** — if reading/writing `SharedPreferences` keys owned by another file, duplicate the key string literal (per Section 17.5 convention) rather than modifying the source file. Flag this as intentional.
5. **Admin pages** — use `AdminGuard` wrapping the page in the route definition, not inside the page itself (Section 17.7).

---

## PHASE 6: VERIFICATION (Before declaring complete)

1. **Compile check** — run `flutter analyze` or `flutter build` to verify no errors.
2. **Regression check** — verify existing features still compile, routes still exist, shared data contracts remain unchanged, previous checklist items were not damaged (Section 14).
3. **Architecture check** — confirm the new code follows the layer chain and doesn't bypass repositories or manipulate UI state from services.
4. **UI check** — confirm theme consistency, no silent color/font/spacing changes.
5. **Feature completeness** — confirm all checklist sub-bullets are addressed.

---

## PHASE 7: DELIVERY

1. **Output a FILE DELIVERY block** before every file:
   - Path
   - Purpose
   - Dependencies verified
   - Current line count
   - New line count
   - Changes
2. **Output a COMPLETION CHECK block** after writing:
   - Compile impact
   - Architecture impact
   - Regression risks
3. **Update the Grand Master Operating Manual** — append a session log entry to Section 23, update Sections 18/19/21/23 as needed.

---

## PHASE 8: END OF SESSION

1. **Update all tracking documents** — Current Project State (Section 17), Checklist Tracker (Section 18), Feature Registry (Section 19), Protected Files (Section 20), Technical Debt (Section 21), Session History (Section 23).
2. **Append a Session Log entry** to Section 23 with:
   - Completed items
   - Files modified
   - Decisions made
   - New technical debt
   - Next recommended task
3. **Check context window** — if approaching ~75% capacity, prepare a `SESSION HANDOFF` block (Rule 15.1).

---

## QUICK REFERENCE: CURRENT PROJECT STATE

### Completed Sections (✅)
- Sections 1–5: Product Foundation, Mobile Architecture, Design System, Navigation System, Home Workspace
- Section 6: User Intake Workspace (`onboarding_page.dart`)
- Section 7: Profile Workspace (`profile_screen.dart`)
- Section 8: Recipe Generator Workspace (`recipe_generator_page.dart`)
- Section 9: Meal Planner Workspace (`meal_planner_page.dart`)
- Section 10: Grocery List Workspace (`grocery_list.dart`, `grocery_service.dart`, `grocery_item.dart`)
- Section 11: List Generator Workspace (`list_generator_page.dart`)
- Section 12: Tracker Workspace (`tracker_landing_page.dart`, `tracker_page.dart`, `extended_tracker_page.dart`)
- Section 13: Dashboard Workspace (`bari_dashboard_page.dart`)
- Section 14: Settings Workspace (`settings_page.dart`)
- Section 15: Account Preferences Workspace (`account_preferences_page.dart`)
- Section 16: AI Personalization Engine Planning (`ai_personalization_plan.md`, `ai_personalization_page.dart`)
- Section 17: Nutrition and Recipe Compliance (`recipe_compliance_service.dart`, `admin_recipe_review_page.dart`)
- Section 22: QA and Testing

### Deferred Sections (⏸️)
- Section 18: Mobile Accessibility
- Section 19: Apple Tasks
- Section 20: Android Tasks

### Not Started Sections (⬜)
- Section 21: Data and Future Backend Planning
- Section 23: Release Readiness
- Section 24: Project Protection Rules

### Current Next Task (Section 25 — corrected)
**Section 21 — Data and Future Backend Planning**
- Planning/documentation deliverable (no single file to verify)
- Synthesize from Technical Debt already logged rather than starting fresh
- Overlaps with Section 14's Data Controls work

### Key Data Sources
| Table | Backs | Storage Type |
|---|---|---|
| `bari_hydration_log` | `hydration_log_page.dart` | Supabase |
| `bari_supplement_schedules` / `bari_supplement_taken_log` | `supplement_schedule_page.dart` | Supabase |
| `bari_symptom_log` | `symptom_log_page.dart` | Supabase |
| `bari_alcohol_log` | `alcohol_log_page.dart` | Supabase |
| `bari_nutrient_snapshots` | `bari_dashboard_page.dart` | Supabase |
| `bari_weekly_goals` | `bari_dashboard_page.dart` | Supabase |
| `grocery_items` | `grocery_list.dart` | Supabase |
| `user_profiles` | `profile_screen.dart` | Supabase |
| `draft_recipes` | `recipe_generator_page.dart` | Supabase |
| `recipe_submissions` | `submit_recipe.dart` | Supabase |

### Key SharedPreferences Keys
- `intake_dietary_restrictions_$userId` — onboarding/profile
- `intake_supplement_baseline_$userId` — onboarding/profile
- `ext_tracker_weight`, `ext_tracker_tolerance`, `ext_tracker_allergy`, `ext_tracker_glp1`, `ext_tracker_wellness` — extended tracker tabs
- `list_gen_grocery`, `list_gen_supplement`, `list_gen_meal_prep` (+ `_archive` variants) — list generator
- `meal_planner_data` — meal planner
- `grocery_list` — grocery list local cache (5-minute)

### Route Table (main.dart lines 565–604)
Key routes: `/login`, `/home`, `/onboarding`, `/profile`, `/grocery-list`, `/tracker`, `/bari-dashboard`, `/hydration-log`, `/supplement-schedule`, `/symptom-log`, `/alcohol-log`, `/recipe-generator`, `/meal-planner`, `/list-generator`, `/extended-tracker`, `/settings`, `/account-preferences`, `/reset-password`

### Active Technical Debt (Section 21 — key items)
1. **Duplicate Weight Tracking Systems** — `tracker_page.dart` vs `extended_tracker_page.dart` vs `ProfileService` (unresolved, user-decided "connect, don't unify")
2. **Duplicate Supplement Tracking Systems** — `tracker_page.dart` local list vs `supplement_schedule_page.dart` Supabase-backed (unresolved)
3. **Local-Only Trackers Without Supabase Backing** — Tolerance, Allergy, GLP-1, Wellness tabs (no DB tables)
4. **Tracker Landing Page Not Wired Into Navigation** — blocked on `main_navigation.dart` (out of scope)
5. **Suggestion Button Scope Excludes External Trackers** — deliberate scoping, not oversight
6. **Unverified Model Field Names in Dashboard** — `SupplementSchedule`, `SupplementTakenEntry`, `HydrationEntry` field names inferred from usage, not confirmed against `bari_models.dart`
7. **Dashboard Local-Fallback Ignores Date Range** — `TrackerService.getLastSevenDays()` hardcoded to 7 days
8. **Duplicate Grocery List Surfaces** — `grocery_list.dart` (Supabase) vs `list_generator_page.dart` Grocery tab (local-only)
9. **AI Personalization Theme Mismatch** — uses BBRS navy/gold instead of BariWise orange
10. **Notification Toggles May Not Control Anything** — 5 toggles in settings, unconfirmed if read elsewhere
11. **Delete Account Does Not Delete Anything** — only shows snackbar directing to support
12. **Settings Placeholders** — version `1.0.0`, email `support@bariwise.app`

---

## RULES SUMMARY

| Rule | Summary |
|---|---|
| 1.1 | Original BBRS Checklist is supreme — never trust old summaries |
| 1.2 | Distinguish Verified vs. Reported vs. Unknown — always inspect actual files |
| 1.3 | BariWise uses `Colors.orange`, package `bari_wise` — never introduce liver-named artifacts |
| 1.4 | No architecture replacement — preserve existing systems |
| 1.5 | Additive development only — Preserve → Add → Integrate → Verify |
| 4.1 | Working feature > cleaner theoretical implementation |
| 4.2 | No gratuitous cleanup |
| 6.1 | Full file rewrites — complete files, no patches |
| 6.2 | Dependency check before every file |
| 13 | Theme consistency — use `Colors.orange`, flag mismatches |
| 14 | Regression protection — verify before declaring complete |
| 15.1 | Begin handoff prep at ~75% context |
| 17.6 | Admin pages use `AdminGuard` in route definition, not inside page |
| 17.7 | `tracker_landing_page.dart` not wired into navigation (deferred) |

---

## FILE DELIVERY TEMPLATE

```
FILE DELIVERY
- Path: [absolute path]
- Purpose: [what this file does]
- Dependencies verified: [list of imports/models/services confirmed to exist]
- Current line count: [if modifying existing file]
- New line count: [expected]
- Changes: [what is being added/preserved/removed]

COMPLETION CHECK
- Compile impact: [what could break compilation]
- Architecture impact: [layer chain compliance]
- Regression risks: [what existing features could be affected]
```

---

## FEATURE VERIFICATION TEMPLATE

```
FEATURE VERIFICATION
- Checklist Section: [Section X — Title]
- Current File(s): [paths inspected]
- Already Implemented: [verified list]
- Missing: [not yet done]
- Potential Risks: [what could go wrong]
- Recommended Action: [what to do]

DECISION REQUIRED
- Recommended plan: [what to build]
- Preserves: [what stays unchanged]
- Adds: [new capability]
- Modifies: [what changes]
```

---

*Derived from the Grand Master Operating Manual (provided as project constitution). Last updated: This session. The full 25-section manual is maintained as the project's master document — consult it for complete rule definitions, session history, and feature registry.*
