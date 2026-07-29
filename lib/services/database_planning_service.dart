// lib/services/database_planning_service.dart
// Section 21 – Data & Future Backend Planning
// Comprehensive planning for BariWise data architecture, migration, and scaling
//
// This file serves as both documentation and a planning reference.
// It defines the target data architecture, migration strategies,
// offline support patterns, and analytics infrastructure.
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

// ============================================================================
// 2. SUPABASE TABLE SCHEMA REFERENCE
// ============================================================================
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ PROFILES                                                           │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK, references auth.users)                │
// │ email               TEXT                                            │
// │ username            TEXT (UNIQUE)                                   │
// │ first_name          TEXT                                            │
// │ last_name           TEXT                                            │
// │ avatar_url          TEXT                                            │
// │ profile_picture_url TEXT                                            │
// │ profile_background  TEXT                                            │
// │ is_premium          BOOLEAN                                         │
// │ daily_scans_used    INTEGER                                         │
// │ last_scan_date      DATE                                            │
// │ xp                  INTEGER                                         │
// │ level               INTEGER                                         │
// │ friends_list_visible BOOLEAN                                        │
// │ created_at          TIMESTAMPTZ                                     │
// │ updated_at          TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_NUTRIENT_SNAPSHOTS (daily nutrition summary for dashboard)     │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ snapshot_date       DATE                                            │
// │ calories            DOUBLE PRECISION                                │
// │ protein_g           DOUBLE PRECISION                                │
// │ fat_g               DOUBLE PRECISION                                │
// │ saturated_fat_g     DOUBLE PRECISION                                │
// │ sugar_g             DOUBLE PRECISION                                │
// │ sodium_mg           DOUBLE PRECISION                                │
// │ fiber_g             DOUBLE PRECISION                                │
// │ water_cups          DOUBLE PRECISION                                │
// │ daily_score         INTEGER                                         │
// │ weight_kg           DOUBLE PRECISION                                │
// │ supplement_count    INTEGER                                         │
// │ UNIQUE(user_id, snapshot_date)                                      │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_WEEKLY_GOALS                                                   │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ week_start_date     DATE                                            │
// │ goal_protein_g      DOUBLE PRECISION                                │
// │ goal_sodium_mg      DOUBLE PRECISION                                │
// │ goal_sugar_g        DOUBLE PRECISION                                │
// │ goal_fat_g          DOUBLE PRECISION                                │
// │ goal_fiber_g        DOUBLE PRECISION                                │
// │ goal_water_cups     DOUBLE PRECISION                                │
// │ UNIQUE(user_id, week_start_date)                                    │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_HYDRATION_LOG                                                  │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ cups                DOUBLE PRECISION                                │
// │ logged_at           TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SUPPLEMENT_SCHEDULES                                           │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ name                TEXT                                            │
// │ dose                TEXT                                            │
// │ time_of_day         TEXT                                            │
// │ is_active           BOOLEAN                                         │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SUPPLEMENT_TAKEN_LOG                                           │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ name                TEXT                                            │
// │ dose                TEXT                                            │
// │ schedule_id         UUID (FK → bari_supplement_schedules.id)        │
// │ taken_at            TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BARI_SYMPTOM_LOG                                                    │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  UUID (PK)                                       │
// │ user_id             UUID (FK → profiles.id)                         │
// │ symptom_type        TEXT (enum: fatigue, nausea, etc.)              │
// │ severity            INTEGER (1-5)                                   │
// │ notes               TEXT                                            │
// │ logged_at           TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ SUBMITTED_RECIPES                                                   │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  SERIAL (PK)                                     │
// │ user_id             UUID (FK → profiles.id)                         │
// │ recipe_name         TEXT                                            │
// │ ingredients         TEXT                                            │
// │ directions          TEXT                                            │
// │ created_at          TIMESTAMPTZ                                     │
// │ updated_at          TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │ BADGES / USER_ACHIEVEMENTS                                          │
// ├──────────────────────────────────────────────────────────────────────┤
// │ id                  SERIAL (PK)                                     │
// │ user_id             UUID (FK → profiles.id)                         │
// │ badge_id            TEXT                                            │
// │ earned_at           TIMESTAMPTZ                                     │
// └──────────────────────────────────────────────────────────────────────┘

// ============================================================================
// 3. TARGET ARCHITECTURE (Repository Pattern)
// ============================================================================
//
// The following defines the future repository pattern that will separate
// data access concerns from business logic. Each repository implements a
// common interface with offline-first strategies.
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
// They should be implemented during Phase 2 migration.

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
// Packages to add for Phase 2-4 migrations:
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
// Target: Versioned endpoints
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
// Event categories to track:
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
//   □ Document existing schema and architecture ✓
//   □ Identify technical debt (duplicate weight/supplement/grocery systems)
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
//   □ Delete Account implementation

// ============================================================================
// 15. TECHNICAL DEBT REGISTER
// ============================================================================
//
// Known issues to address during migration:
//
// DB-001: Duplicate weight tracking
//   - tracker_page.dart has local weight entry
//   - extended_tracker_page.dart has separate weight tracking
//   - Plan: Consolidate into TrackerRepository
//
// DB-002: Duplicate supplement tracking
//   - tracker_page.dart supplements (local)
//   - BariFeaturesService supplement log (Supabase)
//   - Plan: Queue local entries, sync to Supabase
//
// DB-003: Duplicate grocery list systems
//   - grocery_list.dart (local SharedPreferences)
//   - list_generator_page.dart (separate implementation)
//   - Plan: Merge into single GroceryRepository
//
// DB-004: Tracker Landing not connected
//   - tracker_landing_page.dart exists but navigation not wired
//   - Plan: Route to landing, consolidate navigation
//
// DB-005: Notification toggles not wired
//   - UI toggles exist but may not persist
//   - Plan: Wire to SharedPreferences + settings repository
//
// DB-006: Delete Account not implemented
//   - account_deletion_service.dart exists as stub
//   - Plan: Implement full deletion pipeline
//
// DB-007: Some tracker data is local only
//   - Hydration, supplements, symptoms → Supabase
//   - Daily meals, weight, score → local only
//   - Plan: Backup sync to bari_nutrient_snapshots
//
// DB-008: Placeholder support email/version
//   - Contact screen uses placeholder values
//   - Plan: Migrate to AppConfig constants

// ============================================================================
// 16. SUPABASE ROW-LEVEL SECURITY (RLS) POLICY PLAN
// ============================================================================
//
// Current: No RLS policies documented
// Target: Implement RLS for all tables
//
// Profiles:
//   SELECT: Authenticated users can read public profiles
//   INSERT: Users can create their own profile only
//   UPDATE: Users can update their own profile only
//   DELETE: Users can delete their own profile (service role only)
//
// Bari health tables:
//   SELECT: Users can read their own data only
//   INSERT: Users can insert their own data only
//   UPDATE: Users can update their own data only
//   DELETE: Users can delete their own data only
//
// Social tables:
//   SELECT: Friends can read each other's public posts
//   INSERT: Users can create their own posts
//   DELETE: Users can delete their own posts
//
// Admin functions:
//   Service role key for admin operations
//   Admin guard already implemented in app

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
  static int get technicalDebtCount => 8;

  /// Returns the list of known technical debt items.
  static List<String> get technicalDebtItems => [
        'DB-001: Duplicate weight tracking',
        'DB-002: Duplicate supplement tracking',
        'DB-003: Duplicate grocery list systems',
        'DB-004: Tracker Landing not connected',
        'DB-005: Notification toggles not wired',
        'DB-006: Delete Account not implemented',
        'DB-007: Some tracker data is local only',
        'DB-008: Placeholder support email/version',
      ];
}