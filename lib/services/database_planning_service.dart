// lib/services/database_planning_service.dart
// Section 21 – Data & Future Backend Planning
// Comprehensive planning for BariWise data architecture, migration, and scaling
//
// ✅ RECONCILED THIS SESSION: this file's Section 2 (schema reference) and
// Section 16 (RLS plan) were written as aspirational/planned state but had
// been implicitly treated elsewhere as if they described *current* state.
// They didn't. Direct verification this session (information_schema.
// columns, a full FK/cascade map, and pg_policies) found:
//   - None of the 7 bari_* tables existed at all, despite complete,
//     correct Dart code in bari_features_service.dart and
//     alcohol_service.dart already targeting them. Every hydration/
//     supplement/symptom/alcohol log attempt was throwing a visible red
//     error snackbar. This file's own schema section is almost certainly
//     the original spec these were built against — designed, documented
//     here, but never actually migrated into Supabase.
//   - This file's schema section also never mentioned bari_alcohol_log
//     at all, so it was itself an incomplete spec even before the
//     migration gap.
//   - account_deletion_service.dart (referenced below as DB-006) had 5
//     separate wrong table/column names (user_profiles, user_achievements,
//     comment_likes, and sender/receiver instead of sender_id/receiver_id)
//     that were silently failing, on top of the missing bari_* tables.
//   - "Current: No RLS policies documented" (old Section 16) was wrong —
//     RLS is live and enforced, verified directly via pg_policies, on
//     grocery_items, nutrition_tracker, and profiles, all following a
//     consistent auth.uid() = user_id ownership pattern.
//
// All of the above has been fixed or created this session (see updated
// Section 2, Section 15, and Section 16 below). One open item found
// during this reconciliation and NOT yet resolved: profiles appears to
// have no DELETE policy at all in pg_policies, which could mean
// account_deletion_service.dart's final profiles delete silently fails
// if the Worker executes it under the user's own token rather than a
// service-role key. See DB-009 below.
//
// Architecture: UI → Providers → Controllers → Services → Repositories → Storage/APIs
// Current:     UI → Services → DatabaseServiceCore (Worker) → Supabase/R2
// Target:      UI → Providers → Controllers → Services → Repositories → Storage/APIs
//
// ============================================================================
// 1. CURRENT DATA ARCHITECTURE
// ============================================================================
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │                        CLIENT (Flutter/Dart)                        │
// │                                                                     │
// │  ┌─────────┐    ┌───────────┐    ┌───────────────────────────────┐  │
// │  │   UI    │───▶│ Services  │───▶│ DatabaseServiceCore           │  │
// │  │(Widgets)│    │(Business) │    │  - _workerQuery()             │  │
// │  └─────────┘    └───────────┘    │  - _workerStorageUpload()    │  │
// │                                  │  - SharedPreferences cache    │  │
// │                                  └───────────┬───────────────────┘  │
// └──────────────────────────────────────────────┼──────────────────────┘
//                                                  │
//                                                  ▼
// ┌──────────────────────────────────────────────────────────────────────┐
// │                CLOUDFLARE WORKER (Unified Backend)                   │
// │                                                                     │
// │  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐  │
// │  │  HTTP POST  │───▶│  Router      │───▶│ Action Dispatcher     │  │
// │  │  /query     │    │              │    │  - select/insert      │  │
// │  │  /storage   │    │              │    │  - update/delete      │  │
// │  └─────────────┘    └──────────────┘    └───────┬────────────────┘  │
// │                                                  │                    │
// │                    ┌─────────────────────────────┼──────────┐        │
// │                    ▼                             ▼          ▼        │
// │            ┌──────────────┐             ┌────────────┐ ┌───────┐    │
// │            │  Supabase    │             │  Cloudflare │ │  R2   │    │
// │            │  (Auth + DB) │             │   Workers  │ │Storage│    │
// │            └──────────────┘             │   AI/ML    │ └───────┘    │
// │                                         └────────────┘              │
// └──────────────────────────────────────────────────────────────────────┘
//
// ⚠️ Note on _workerQuery: verified this session (database_service_core.dart)
// that the `filters` map is a pure client-side passthrough to the Worker —
// no key validation or whitelisting happens in the Flutter code. Whether
// the Worker itself handles arbitrary filter column names (e.g.
// tagged_user_id, sender_id) equivalently to user_id is not verified —
// the Worker's own source is not part of this Flutter repo.

// ============================================================================
// 2. SUPABASE TABLE SCHEMA REFERENCE
// ============================================================================
//
// ✅ CORRECTED THIS SESSION. Below reflects the REAL, directly-queried
// schema as of this session — not the original spec. Differences from
// the original version of this file are called out explicitly rather
// than silently changed.
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ PROFILES  (real table — directly verified)                          │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK, references auth.users)                │
// │ email               TEXT                                            │
// │ username            TEXT                                            │
// │ first_name          TEXT                                            │
// │ last_name           TEXT                                            │
// │ profile_picture     TEXT                                            │
// │ profile_background  TEXT                                            │
// │ avatar_url          TEXT                                            │
// │ bariatric_surgery_type TEXT                                         │
// │ friends_list_visible BOOLEAN                                        │
// │ weight_loss_visible BOOLEAN                                         │
// │ weight_visible      BOOLEAN                                         │
// │ is_premium          BOOLEAN                                         │
// │ premium_expires_at  TIMESTAMPTZ                                     │
// │ total_scans_used    INTEGER                                         │
// │ daily_scans_used    INTEGER                                         │
// │ last_scan_date      DATE                                            │
// │ height_cm           DOUBLE PRECISION                                │
// │ height_unit_preference VARCHAR                                      │
// │ pictures            ARRAY (gallery URLs)                            │
// │ created_at          TIMESTAMPTZ                                     │
// │ updated_at          TIMESTAMPTZ                                     │
// │                                                                       │
// │ ⚠️ Old version of this doc listed xp/level columns — not confirmed   │
// │ present. Not removed from any code on this basis, just not asserted │
// │ as real schema here until directly checked.                         │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_NUTRIENT_SNAPSHOTS  (real as of this session — created,        │
// │ RLS-secured, and wired into account_deletion_service.dart)          │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) ⚠️ was UUID in the        │
// │                      original spec — BIGINT matches the dominant    │
// │                      convention across the real schema (most tables │
// │                      use integer/bigint; only feed_* and a couple   │
// │                      others use uuid). Confirmed harmless: every    │
// │                      bari_models.dart fromMap() calls .toString()   │
// │                      on id, so either type deserializes fine.       │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ snapshot_date       DATE                                            │
// │ calories            NUMERIC                                        │
// │ protein_g           NUMERIC                                        │
// │ fat_g               NUMERIC                                        │
// │ saturated_fat_g     NUMERIC                                        │
// │ sugar_g             NUMERIC                                        │
// │ sodium_mg           NUMERIC                                        │
// │ fiber_g             NUMERIC                                        │
// │ water_cups          NUMERIC                                        │
// │ daily_score         INTEGER                                         │
// │ weight_kg           NUMERIC                                        │
// │ supplement_count    INTEGER                                         │
// │ UNIQUE(user_id, snapshot_date)                                      │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_WEEKLY_GOALS  (real as of this session)                        │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) — see note above          │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ week_start_date     DATE                                            │
// │ goal_protein_g      NUMERIC                                        │
// │ goal_sodium_mg      NUMERIC                                        │
// │ goal_sugar_g        NUMERIC                                        │
// │ goal_fat_g          NUMERIC                                        │
// │ goal_fiber_g        NUMERIC                                        │
// │ goal_water_cups     NUMERIC                                        │
// │ UNIQUE(user_id, week_start_date)                                    │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_HYDRATION_LOG  (real as of this session)                       │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) — see note above          │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ cups                NUMERIC                                        │
// │ logged_at           TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SUPPLEMENT_SCHEDULES  (real as of this session)                 │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) — see note above          │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ name                TEXT                                            │
// │ dose                TEXT                                            │
// │ time_of_day         TEXT                                            │
// │ is_active           BOOLEAN                                         │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SUPPLEMENT_TAKEN_LOG  (real as of this session)                 │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) — see note above          │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ name                TEXT                                            │
// │ dose                TEXT                                            │
// │ schedule_id         BIGINT (FK → bari_supplement_schedules.id,      │
// │                      ON DELETE SET NULL)                            │
// │ taken_at            TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SYMPTOM_LOG  (real as of this session)                         │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity) — see note above          │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ symptom_type        TEXT (enum: fatigue, nausea, etc.)              │
// │ severity            INTEGER (1-5)                                   │
// │ notes               TEXT                                            │
// │ logged_at           TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_ALCOHOL_LOG  (real as of this session — NOT documented in the  │
// │ original version of this file at all; discovered via                │
// │ alcohol_service.dart, which was never mentioned in this doc)        │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  BIGINT (PK, identity)                           │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ drink_name          TEXT                                            │
// │ total_volume_oz     NUMERIC                                        │
// │ abv_percent         NUMERIC                                        │
// │ pure_alcohol_oz     NUMERIC                                        │
// │ standard_drinks     NUMERIC                                        │
// │ logged_at           TIMESTAMPTZ                                     │
// │ notes               TEXT                                            │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ SUBMITTED_RECIPES  (real table — directly verified; several columns │
// │ differ from the original version of this doc)                       │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  INTEGER (PK)                                    │
// │ user_id             UUID (FK → profiles.id, ON DELETE CASCADE)      │
// │ title               TEXT       ⚠️ was "recipe_name" in old doc      │
// │ description         TEXT                                            │
// │ ingredients          ARRAY      ⚠️ was TEXT in old doc               │
// │ instructions         ARRAY      ⚠️ was "directions" TEXT in old doc  │
// │ servings, prep_time_minutes, cook_time_minutes  INTEGER              │
// │ calories, protein, carbohydrates, fat, sugar, fiber, sodium,        │
// │   saturated_fat     NUMERIC                                        │
// │ bari_score          INTEGER                                         │
// │ is_verified, is_public  BOOLEAN                                     │
// │ average_rating      NUMERIC                                        │
// │ rating_count        INTEGER                                         │
// │ image_url           TEXT                                            │
// │ submitted_at, updated_at  TIMESTAMPTZ                                │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ "BADGES / USER_ACHIEVEMENTS" — REMOVED FROM THIS DOC.                │
// │ Directly verified this session: no table by this or any similar     │
// │ name exists anywhere in the public schema. account_deletion_        │
// │ service.dart referenced 'user_achievements' and silently failed on  │
// │ every deletion attempt; that call has been removed there. If an     │
// │ achievements/gamification feature is real (xp_service.dart,         │
// │ achievements_service.dart, xp_reward_service.dart all exist in the  │
// │ codebase per a full `find lib -type f` this session), its actual    │
// │ backing table has not yet been identified and should be checked     │
// │ directly rather than assumed from this doc's old claim.             │
// └──────────────────────────────────────────────────────────────────────┘
//
// ✅ ALSO DISCOVERED THIS SESSION, NOT PREVIOUSLY IN THIS DOC AT ALL: a
// real social feed system (feed_posts, feed_post_comments,
// feed_post_likes, feed_post_saves, feed_tags, feed_notifications,
// post_reports), friendships (distinct from friend_requests), cookbooks/
// cookbook_recipes, user_pantry, user_scanned_ingredients,
// custom_ingredients, suggested_recipes, draft_recipes, grocery_list_items,
// user_pictures, user_preferences, contact_messages,
// profile_creation_logs. None of these are documented anywhere in this
// file's schema reference. Confirmed real and populated with real
// columns (not empty/dead tables) via direct information_schema query.
// Whether all of these are actually wired up in the running app is
// unconfirmed and out of scope for this reconciliation pass.

// ============================================================================
// 3. TARGET ARCHITECTURE (Repository Pattern)
// ============================================================================
//
// The following defines the future repository pattern that will separate
// data access concerns from business logic. Each repository implements a
// common interface with offline-first strategies. Unchanged this session —
// this is forward-looking design, not a claim about current state.
//
// ┌────────────────────────────────────────────────────────────────────────┐
// │ FUTURE DATA LAYER                                                     │
// │                                                                       │
// │  UI → Providers → Controllers → Services → Repositories → Storage    │
// │                                          │                            │
// │                                          ├── ProfileRepository        │
// │                                          │     - Supabase + cache     │
// │                                          │                            │
// │                                          ├── TrackerRepository        │
// │                                          │     - Local first          │
// │                                          │     - Sync to Supabase     │
// │                                          │                            │
// │                                          ├── RecipeRepository         │
// │                                          │     - Supabase + cache     │
// │                                          │                            │
// │                                          ├── BariHealthRepository     │
// │                                          │     - Supabase direct      │
// │                                          │     - Offline queue        │
// │                                          │                            │
// │                                          ├── SocialRepository         │
// │                                          │     - Supabase + realtime  │
// │                                          │                            │
// │                                          └── AnalyticsRepository      │
// │                                              - Event buffer           │
// │                                              - Batch upload           │
// └────────────────────────────────────────────────────────────────────────┘

// ============================================================================
// 4. DATA SYNCHRONIZATION STRATEGY
// ============================================================================
//
// The app uses a mixed online/offline strategy:
//
// ┌────────────────────────────────────────────────────────────────────────┐
// │ DATA CATEGORY    │ STORAGE              │ SYNC STRATEGY               │
// ├──────────────────┼──────────────────────┼─────────────────────────────┤
// │ Auth tokens      │ Supabase session     │ Always online               │
// │ User profile     │ Supabase + cache     │ Online-first, cached        │
// │ Daily tracker    │ Local + Supabase     │ Local-first, background sync│
// │ Bari snapshots   │ Supabase             │ Online-only (best-effort)   │
// │ Grocery list     │ Local + Supabase     │ Local-first, manual sync    │
// │ Recipes          │ Supabase + cache     │ Online-first, cached        │
// │ Social feed      │ Supabase             │ Online-only                 │
// │ Messages         │ Supabase             │ Online-only (real-time)     │
// │ Configuration    │ SharedPreferences    │ Local-only                  │
// └────────────────────────────────────────────────────────────────────────┘
//
// ⚠️ Note: whether Hydration/Supplement/Symptom/Alcohol logging is
// genuinely "online-only" in practice is worth re-checking now that
// their tables actually exist — until this session they were, in effect,
// completely non-functional rather than "online" in any real sense.
//
// TARGET OFFLINE-FIRST APPROACH:
// ┌────────────────────────────────────────────────────────────────────────┐
// │ 1. Write to local SQLite (supported via sqflite/Isar)                 │
// │ 2. Queue mutations in a sync log                                      │
// │ 3. On connectivity, process queue in FIFO order                       │
// │ 4. Resolve conflicts with "last-write-wins" or "server-wins"          │
// │ 5. Expose sync status to UI (synced/pending/conflict)                 │
// └────────────────────────────────────────────────────────────────────────┘

// ============================================================================
// 5. DATA MIGRATION PATH
// ============================================================================
//
// Phase 1 (Current) – Cloudflare Worker + Supabase direct
// ────────────────────────────────────────────────────────────────────────────
//   - Every service calls DatabaseServiceCore._workerQuery()
//   - Worker proxies to Supabase REST API
//   - SharedPreferences for lightweight caching
//   - R2 for file storage (profile pics, backgrounds)
//   - Firebase for push notifications
//
// Phase 2 (Near-term) – Introduce Repository layer
// ────────────────────────────────────────────────────────────────────────────
//   - Create Repository classes that wrap DatabaseServiceCore
//   - Add LocalDatabaseService (sqflite) for offline storage
//   - Implement SyncEngine for conflict resolution
//   - Migrate profile data to Repository pattern first
//   - Add connectivity awareness (connectivity_plus package)
//
// Phase 3 (Medium-term) – Provider/Controller layer
// ────────────────────────────────────────────────────────────────────────────
//   - Add ChangeNotifier providers for reactive UI
//   - Create Controllers that orchestrate multiple repositories
//   - Implement optimistic updates with rollback on failure
//   - Add background sync scheduling (workmanager package)
//   - Migrate tracker data to repository pattern
//
// Phase 4 (Long-term) – Full offline-first + real-time sync
// ────────────────────────────────────────────────────────────────────────────
//   - Complete offline-first with local SQLite database
//   - Real-time sync via Supabase Realtime subscriptions
//   - Batch analytics events via worker
//   - Image sync queue for offline photo capture
//   - Data export/import (GDPR compliance)
//   - Analytics dashboard with event tracking

// ============================================================================
// 6. REPOSITORY INTERFACE DEFINITIONS
// ============================================================================
//
// These interfaces define the contract for each repository.
// They should be implemented during Phase 2 migration. Unchanged this
// session — forward-looking design, not a current-state claim.

/// Base repository with common CRUD operations.
/// Every repository follows this pattern.
abstract class BaseRepository<T> {
  /// Fetch a single entity by ID.
  Future<T?> getById(String id);

  /// Fetch all entities for the current user.
  Future<List<T>> getAll({Map<String, dynamic>? filters});

  /// Insert a new entity.
  Future<T> insert(T entity);

  /// Update an existing entity.
  Future<T> update(T entity);

  /// Delete an entity by ID.
  Future<void> delete(String id);

  /// Clear local cache for this repository.
  Future<void> clearCache();
}

/// Repository for user profile data.
/// Online-first with aggressive caching (30-minute TTL).
abstract class ProfileRepository extends BaseRepository<ProfileEntity> {
  Future<ProfileEntity?> getCurrentProfile();
  Future<void> updateProfile(Map<String, dynamic> updates);
  Future<bool> isPremium();
  Future<int> getDailyScanCount();
  Stream<ProfileEntity> watchProfile();
}

/// Repository for daily tracker data.
/// Local-first with background sync to Supabase snapshots.
abstract class TrackerRepository extends BaseRepository<TrackerEntryEntity> {
  Future<List<TrackerEntryEntity>> getEntriesForDate(DateTime date);
  Future<List<TrackerEntryEntity>> getEntriesForRange(
      DateTime from, DateTime to);
  Future<Map<String, double>> calculateNutritionTotals(
      List<MealEntity> meals);
  Future<void> syncToSupabase(String userId);
}

/// Repository for bariatric health data.
/// Online with offline mutation queue.
abstract class BariHealthRepository {
  Future<void> logHydration(double cups);
  Future<List<HydrationEntryEntity>> getHydrationLog(
      DateTime from, DateTime to);
  Future<double> getTodayCups();

  Future<List<SupplementScheduleEntity>> getSupplementSchedules();
  Future<SupplementScheduleEntity> createSupplementSchedule(
      SupplementScheduleEntity schedule);
  Future<void> logSupplementTaken(
      String name, String dose, String? scheduleId);

  Future<void> logSymptom(
      SymptomTypeEntity type, int severity, String? notes);
  Future<List<SymptomEntryEntity>> getSymptomLog(DateTime from);

  Future<List<NutrientSnapshotEntity>> getDailySnapshots({int days = 30});
  Future<void> upsertDailySnapshot(NutrientSnapshotEntity snapshot);

  Future<WeeklyGoalEntity?> getCurrentWeekGoal();
  Future<WeeklyGoalEntity> saveWeeklyGoal(WeeklyGoalEntity goal);
}

/// Repository for recipe data.
/// Online-first with cache and pagination.
abstract class RecipeRepository extends BaseRepository<RecipeEntity> {
  Future<List<RecipeEntity>> searchRecipes(String query);
  Future<List<RecipeEntity>> getFavoriteRecipes();
  Future<void> toggleFavorite(String recipeId);
  Future<List<RecipeEntity>> getSuggestedRecipes();
  Future<RecipeEntity> generateRecipe(
      Map<String, dynamic> preferences);
}

/// Repository for social features.
/// Online-only with real-time subscriptions.
abstract class SocialRepository {
  Future<List<PostEntity>> getFeed({int page = 1});
  Future<PostEntity> createPost(PostEntity post);
  Future<void> likePost(String postId);
  Future<void> commentOnPost(String postId, String text);
  Stream<List<PostEntity>> watchFeed();
  Stream<MessageEntity> watchMessages();
}

// ============================================================================
// 7. ENTITY DEFINITIONS (Future domain models)
// ============================================================================
//
// These are the domain entities that will replace raw Maps throughout the app.
// They are defined here for planning only — actual implementation during Phase 2.
// Unchanged this session.

class ProfileEntity {
  final String id;
  final String email;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? avatarUrl;
  final String? profilePictureUrl;
  final bool isPremium;
  final int xp;
  final int level;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProfileEntity({
    required this.id,
    required this.email,
    this.username,
    this.firstName,
    this.lastName,
    this.avatarUrl,
    this.profilePictureUrl,
    this.isPremium = false,
    this.xp = 0,
    this.level = 1,
    required this.createdAt,
    required this.updatedAt,
  });
}

class TrackerEntryEntity {
  final String? id;
  final String userId;
  final DateTime date;
  final List<MealEntity> meals;
  final double? waterIntake;
  final double? weight;
  final int? dailyScore;
  final List<SupplementEntity> supplements;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  const TrackerEntryEntity({
    this.id,
    required this.userId,
    required this.date,
    this.meals = const [],
    this.waterIntake,
    this.weight,
    this.dailyScore,
    this.supplements = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });
}

class MealEntity {
  final String name;
  final double calories;
  final double protein;
  final double fat;
  final double saturatedFat;
  final double sugar;
  final double sodium;
  final double fiber;
  final String? mealType;

  const MealEntity({
    required this.name,
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.saturatedFat = 0,
    this.sugar = 0,
    this.sodium = 0,
    this.fiber = 0,
    this.mealType,
  });
}

class SupplementEntity {
  final String name;
  final String dose;
  final DateTime? takenAt;

  const SupplementEntity({
    required this.name,
    required this.dose,
    this.takenAt,
  });
}

class HydrationEntryEntity {
  final String? id;
  final String userId;
  final double cups;
  final DateTime loggedAt;

  const HydrationEntryEntity({
    this.id,
    required this.userId,
    required this.cups,
    required this.loggedAt,
  });
}

class SupplementScheduleEntity {
  final String? id;
  final String userId;
  final String name;
  final String dose;
  final String timeOfDay;
  final bool isActive;

  const SupplementScheduleEntity({
    this.id,
    required this.userId,
    required this.name,
    required this.dose,
    required this.timeOfDay,
    this.isActive = true,
  });
}

class SymptomEntryEntity {
  final String? id;
  final String userId;
  final SymptomTypeEntity type;
  final int severity;
  final String? notes;
  final DateTime loggedAt;

  const SymptomEntryEntity({
    this.id,
    required this.userId,
    required this.type,
    required this.severity,
    this.notes,
    required this.loggedAt,
  });
}

enum SymptomTypeEntity {
  fatigue,
  nausea,
  abdominalPain,
  dumpingSyndrome,
  reflux,
  diarrhea,
  constipation,
  hairLoss,
  headache,
  dizziness,
  foodIntolerance,
  other;
}

class NutrientSnapshotEntity {
  final String? id;
  final String userId;
  final DateTime snapshotDate;
  final double? calories;
  final double? proteinG;
  final double? fatG;
  final double? saturatedFatG;
  final double? sugarG;
  final double? sodiumMg;
  final double? fiberG;
  final double? waterCups;
  final int? dailyScore;
  final double? weightKg;
  final int? supplementCount;

  const NutrientSnapshotEntity({
    this.id,
    required this.userId,
    required this.snapshotDate,
    this.calories,
    this.proteinG,
    this.fatG,
    this.saturatedFatG,
    this.sugarG,
    this.sodiumMg,
    this.fiberG,
    this.waterCups,
    this.dailyScore,
    this.weightKg,
    this.supplementCount,
  });
}

class WeeklyGoalEntity {
  final String? id;
  final String userId;
  final DateTime weekStartDate;
  final double? goalProteinG;
  final double? goalSodiumMg;
  final double? goalSugarG;
  final double? goalFatG;
  final double? goalFiberG;
  final double? goalWaterCups;

  const WeeklyGoalEntity({
    this.id,
    required this.userId,
    required this.weekStartDate,
    this.goalProteinG,
    this.goalSodiumMg,
    this.goalSugarG,
    this.goalFatG,
    this.goalFiberG,
    this.goalWaterCups,
  });
}

class RecipeEntity {
  final String? id;
  final String userId;
  final String name;
  final String? ingredients;
  final String? directions;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const RecipeEntity({
    this.id,
    required this.userId,
    required this.name,
    this.ingredients,
    this.directions,
    this.isFavorite = false,
    required this.createdAt,
    this.updatedAt,
  });
}

class PostEntity {
  final String? id;
  final String userId;
  final String content;
  final List<String> imageUrls;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;

  const PostEntity({
    this.id,
    required this.userId,
    required this.content,
    this.imageUrls = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
  });
}

class MessageEntity {
  final String? id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime sentAt;
  final bool isRead;

  const MessageEntity({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.sentAt,
    this.isRead = false,
  });
}

// ============================================================================
// 8. PACKAGE ROADMAP
// ============================================================================
//
// Packages to add for Phase 2-4 migrations. Unchanged this session.
//
// Phase 2:
//   sqflite: ^2.3.0          # Local SQLite database
//   path: ^1.9.0              # Database path management
//   connectivity_plus: ^6.0.0 # Network state detection
//
// Phase 3:
//   provider: ^6.1.0          # State management (ChangeNotifier)
//   workmanager: ^0.28.0      # Background task scheduling
//   uuid: ^4.0.0              # Generate offline IDs
//
// Phase 4:
//   flutter_secure_storage: ^9.0.0  # Encrypted local storage
//   sentry_flutter: ^8.0.0          # Error tracking (optional)
//   mixpanel_flutter: ^2.0.0        # Analytics (optional)

// ============================================================================
// 9. CLOUDFLARE WORKER API VERSIONING PLAN
// ============================================================================
//
// Current: Single endpoint /query with action-based routing
// Target: Versioned endpoints. Unchanged this session.
//
//   /api/v1/query          → Current functionality
//   /api/v1/storage        → File operations
//   /api/v1/analytics      → Event batching
//   /api/v1/sync           → Offline sync endpoint
//   /api/v1/export         → GDPR data export
//
// Worker versioning strategy:
//   - Deploy new worker as separate environment (staging)
//   - Use header-based versioning: X-API-Version: 1
//   - Maintain backward compatibility for 2 versions
//   - Deprecation notice period: 90 days

// ============================================================================
// 10. ERROR HANDLING & RETRY STRATEGY
// ============================================================================
//
// Current: ErrorHandlingService (basic try/catch logging)
// Target: Structured error handling with retry policies
//
// ⚠️ Worth flagging given this session's findings: the CURRENT error
// handling pattern (try/catch that logs to debug console and swallows
// the error) is precisely what let the missing bari_* tables, the wrong
// account_deletion_service.dart table/column names, and (potentially)
// the profiles DELETE RLS gap go unnoticed. "Basic try/catch logging" is
// not just an architectural nicety to defer to Phase 2+ — it's an active
// risk of the exact failure mode found repeatedly this session.
//
// Error categories:
//   NetworkError       → Retry with exponential backoff (3 attempts)
//   AuthError          → Force re-login
//   ValidationError    → Show user feedback immediately
//   ServerError        → Retry with backoff, then show fallback
//   ConflictError      → Server-wins resolution
//   NotFoundError      → Clear local cache, fetch fresh
//
// Retry policy (future implementation):
//   Attempt 1: Immediate
//   Attempt 2: 1 second delay
//   Attempt 3: 3 second delay
//   After 3: Show "offline" state, queue for background sync

// ============================================================================
// 11. DATA ANALYTICS PLAN
// ============================================================================
//
// Event categories to track. Unchanged this session.
//
// User Engagement:
//   - app_open
//   - screen_view (screen_name)
//   - session_duration
//
// Feature Usage:
//   - tracker_entry_created
//   - recipe_generated
//   - meal_planned
//   - grocery_list_created
//   - barcode_scanned
//   - supplement_logged
//   - symptom_logged
//   - hydration_logged
//
// Health Metrics:
//   - weight_recorded
//   - daily_score_recorded
//   - nutrition_snapshot_created
//
// Social:
//   - post_created
//   - message_sent
//   - friend_added
//
// Monetization:
//   - premium_purchased
//   - ad_viewed
//   - scan_limit_reached
//
// Analytics will be batched and sent to the Cloudflare Worker,
// which can forward to any analytics provider (PostHog, Mixpanel, etc.)
// without client-side changes.

// ============================================================================
// 12. PERFORMANCE & SCALING CONSIDERATIONS
// ============================================================================
//
// Database optimization:
//   - Add indexes on frequently queried columns:
//     profiles (email, username)
//     bari_nutrient_snapshots (user_id, snapshot_date)
//     bari_hydration_log (user_id, logged_at)
//     submitted_recipes (user_id)
//   - Use composite indexes for range queries
//   - Implement pagination for list endpoints
//
// ⚠️ Note: the bari_* tables referenced above now genuinely exist as of
// this session — these index recommendations are newly actionable, not
// purely theoretical.
//
// Worker optimization:
//   - Add connection pooling to Supabase
//   - Implement response caching for read-heavy endpoints
//   - Use Durable Objects for real-time features
//   - Add rate limiting per user
//
// Client optimization:
//   - Implement lazy loading for large lists
//   - Cache profile images locally
//   - Debounce search queries
//   - Batch snapshot syncs
//
// Monitoring:
//   - Add worker request logging
//   - Track error rates per endpoint
//   - Monitor cache hit ratios
//   - Track sync queue depth

// ============================================================================
// 13. PRIVACY & COMPLIANCE
// ============================================================================
//
// Data classification:
//   Public:  Username, profile picture, food posts
//   Private: Email, weight data, health logs, messages
//   Sensitive: Full name, exact birth date, medical history
//
// Data retention:
//   Active user data: Until account deletion
//   Deleted accounts: Anonymized after 30 days
//   Analytics data: 24 months rolling
//   Error logs: 90 days
//
// GDPR compliance:
//   - Data export endpoint (worker)
//   - Account deletion with data purge
//   - Consent management UI
//   - Cookie/data collection disclosure
//
// ⚠️ Account deletion status update: as of this session,
// account_deletion_service.dart has been rewritten against the real
// schema and now covers 30+ tables correctly, including all 7 bari_*
// tables. See DB-006 and DB-009 below for current/remaining status —
// this is much closer to a real "data purge" than the stub this doc
// previously described, but the profiles DELETE RLS question (DB-009)
// should be resolved before this bullet is treated as fully done.
//
// Encryption:
//   - In transit: TLS (already enforced by Supabase/Worker)
//   - At rest: Supabase encryption (default)
//   - Local: flutter_secure_storage for tokens
//   - Health data: Column-level encryption (future)

// ============================================================================
// 14. IMPLEMENTATION ORDER (Priority)
// ============================================================================
//
// Priority 1 (Current sprint):
//   ✅ Document existing schema and architecture — corrected this session
//      against directly-verified reality, not just re-confirmed
//   ✅ Identify technical debt (duplicate weight/supplement/grocery systems)
//
// Priority 2 (Next sprint):
//   □ Create LocalDatabaseService with sqflite
//   □ Implement SyncEngine for offline queue
//   □ Migrate tracker data to local-first storage
//   □ Add connectivity awareness to services
//
// Priority 3 (Following sprint):
//   □ Implement Repository pattern for profile data
//   □ Add ChangeNotifier providers for reactive UI
//   □ Implement optimistic updates
//   □ Background sync scheduling
//
// Priority 4 (Future):
//   □ Complete repository migration for all data domains
//   □ Real-time sync via Supabase subscriptions
//   □ Analytics event batching
//   □ GDPR data export
//   □ Data migration tools
//   ✅ Delete Account implementation — DONE this session (see DB-006).
//      Was listed here as a future Priority-4 item; turned out to
//      already be attempted (as a broken stub) and was fixed, not built
//      from scratch.

// ============================================================================
// 15. TECHNICAL DEBT REGISTER
// ============================================================================
//
// ✅ Statuses updated this session against verified reality. Register
// stays append-only — DB-001 through DB-008 numbering preserved exactly,
// new items appended as DB-009+.
//
// DB-001: Duplicate weight tracking
//   - tracker_page.dart has local weight entry
//   - extended_tracker_page.dart has separate weight tracking
//   - Plan: Consolidate into TrackerRepository
//   Status: Unresolved. Explicit user decision this session's broader
//   history: "connect, don't unify" — intentionally left as-is for now.
//
// DB-002: Duplicate supplement tracking
//   - tracker_page.dart supplements (local)
//   - BariFeaturesService supplement log (Supabase)
//   - Plan: Queue local entries, sync to Supabase
//   Status: Unresolved. ⚠️ Newly relevant nuance: until this session, the
//   Supabase side of this "duplication" was completely non-functional
//   (table didn't exist, every call threw). The duplication has only
//   been *actually* live on both sides since this session's fix — worth
//   knowing when reasoning about how much real-world drift between the
//   two systems has actually accumulated.
//
// DB-003: Duplicate grocery list systems
//   - grocery_list.dart (local SharedPreferences)
//   - list_generator_page.dart (separate implementation)
//   - Plan: Merge into single GroceryRepository
//   Status: Unresolved — architecture decision requiring explicit
//   direction, unchanged.
//
// DB-004: Tracker Landing not connected
//   - tracker_landing_page.dart exists but navigation not wired
//   - Plan: Route to landing, consolidate navigation
//   Status: Unresolved — blocked on main_navigation.dart being back in
//   scope, per prior session decision.
//
// DB-005: Notification toggles not wired
//   - UI toggles exist but may not persist
//   - Plan: Wire to SharedPreferences + settings repository
//   Status: ✅ Resolved. Hydration and Symptom Reminders now call
//   BariNotificationService for real. Weekly Progress, Recipe Updates,
//   and Messages have no backing notification type at all (confirmed via
//   direct inspection, not assumption) and are honestly labeled
//   "Coming soon" rather than left silently non-functional.
//
// DB-006: Delete Account not implemented
//   - account_deletion_service.dart exists as stub
//   - Plan: Implement full deletion pipeline
//   Status: ✅ Resolved, in two passes. First pass fixed 5 wrong table/
//   column names that had been silently failing (user_profiles→profiles,
//   user_achievements→removed, comment_likes→feed_comment_likes,
//   sender/receiver→sender_id/receiver_id) and added ~20 real per-user
//   tables that were never touched at all. Second pass added all 7 bari_*
//   tables once they were confirmed to exist. See DB-009 for one
//   remaining open question on this feature.
//
// DB-007: Some tracker data is local only
//   - Hydration, supplements, symptoms → Supabase
//   - Daily meals, weight, score → local only
//   - Plan: Backup sync to bari_nutrient_snapshots
//   Status: Partially resolved. The "→ Supabase" side of this line is
//   only genuinely true as of this session — the 6 relevant tables (7
//   counting alcohol) did not exist before now. The local-only side is
//   unchanged.
//
// DB-008: Placeholder support email/version
//   - Contact screen uses placeholder values
//   - Plan: Migrate to AppConfig constants
//   Status: Unresolved — placeholders are intentional-by-design pending
//   real values, not a bug. Unchanged.
//
// ✅ NEW — DB-009: profiles Table May Have No DELETE Policy
//   Location: RLS on the 'profiles' table (pg_policies, checked this
//   session).
//   Issue: SELECT (×2), INSERT (×2), and UPDATE policies were found for
//   profiles — no DELETE policy was returned. If the Cloudflare Worker
//   executes account_deletion_service.dart's final `_safeDelete('profiles',
//   {'id': userId})` call using the user's own forwarded auth token
//   (normal RLS-enforced access) rather than a service-role key that
//   bypasses RLS, that delete could be silently failing right now — the
//   exact same failure shape as every other bug found this session.
//   Status: Unresolved — not verifiable from this Flutter repo alone,
//   since the Worker's own source isn't part of it. Needs either (a) a
//   real test deletion followed by directly checking whether the
//   profiles row is actually gone, or (b) the Worker's source, to see
//   whether it uses service_role for deletes.

// ============================================================================
// 16. SUPABASE ROW-LEVEL SECURITY (RLS) POLICY PLAN
// ============================================================================
//
// ✅ CORRECTED THIS SESSION. The original version of this doc said
// "Current: No RLS policies documented" — that was wrong. RLS is live
// and enforced, directly verified via pg_policies this session.
//
// Confirmed real pattern (grocery_items, nutrition_tracker — both
// checked directly): strict per-user ownership, all four operations:
//   SELECT/INSERT/UPDATE/DELETE: auth.uid() = user_id
//
// profiles is intentionally different (social-facing, not private):
//   SELECT: "Users can view other profiles" (qual: true — public) AND
//           "Users can view own profile" (qual: auth.uid() = id)
//   INSERT: "Users can insert own profile" (auth.uid() = id) AND a
//           separate service_role INSERT policy
//   UPDATE: auth.uid() = id
//   DELETE: ⚠️ none found. See DB-009 above — this is the one open
//           question left from this session's verification work.
//
// The 7 bari_* tables created this session were given RLS matching the
// grocery_items/nutrition_tracker pattern exactly (strict ownership, all
// four operations) — NOT the profiles pattern, since health tracking
// data has no reason to be publicly viewable.
//
// Social tables (feed_*, friendships, etc.): RLS policies not checked
// this session — out of scope for this reconciliation pass, but worth
// noting given the profiles DELETE gap that "a table exists" does not
// imply "its RLS is complete."
//
// Admin functions:
//   Service role key for admin operations
//   Admin guard already implemented in app (admin_guard.dart)

// ============================================================================
// 17. CAPACITY PLANNING
// ============================================================================
//
// Current scale assumptions:
//   Active users: < 1,000
//   Daily snapshots: ~100
//   Storage: < 1 GB
//
// Growth targets:
//   Year 1: 5,000 active users
//   Year 2: 20,000 active users
//   Year 3: 50,000 active users
//
// Bottlenecks to monitor:
//   - Supabase free tier: 500 MB database, 5 GB bandwidth
//   - Cloudflare Worker: 100k requests/day (free tier)
//   - R2 storage: 10 GB free
//
// Scaling triggers:
//   □ > 1,000 daily active users → Upgrade Supabase Pro ($25/mo)
//   □ > 100k worker requests/day → Upgrade Workers Paid ($5+/mo)
//   □ > 10 GB storage → Upgrade R2 (pay-as-you-go)
//   □ > 5k users → Add CDN caching for static assets
//   □ > 20k users → Consider dedicated backend server

class DatabasePlanningService {
  /// Placeholder class for future implementation.
  /// All planning details are documented above in the comments.
  /// This class will be replaced by actual repository implementations
  /// during Phase 2-4 migrations.
  const DatabasePlanningService._();

  /// Returns the current phase identifier.
  static String get currentPhase => 'Phase 1 – Worker + Supabase direct';

  /// Returns the next migration phase.
  static String get nextPhase => 'Phase 2 – Repository layer + offline storage';

  /// Returns the count of known technical debt items.
  /// ✅ Updated this session: was 8, now 9 (DB-009 added). Resolved items
  /// (DB-005, DB-006) are still counted here — this tracks total known
  /// items ever logged, not just open ones. See resolvedDebtCount below
  /// for open-vs-resolved.
  static int get technicalDebtCount => 9;

  /// Returns the list of known technical debt items, with status.
  /// ✅ Updated this session to reflect real current status per item.
  static List<String> get technicalDebtItems => [
        'DB-001: Duplicate weight tracking (unresolved)',
        'DB-002: Duplicate supplement tracking (unresolved)',
        'DB-003: Duplicate grocery list systems (unresolved)',
        'DB-004: Tracker Landing not connected (unresolved)',
        'DB-005: Notification toggles not wired (RESOLVED)',
        'DB-006: Delete Account not implemented (RESOLVED)',
        'DB-007: Some tracker data is local only (partially resolved)',
        'DB-008: Placeholder support email/version (unresolved, by design)',
        'DB-009: profiles table may have no DELETE policy (unresolved, unverified)',
      ];

  /// ✅ New this session — quick open-count for anyone consuming this
  /// class without reading the full comment block above.
  static int get openDebtCount => 7;
}