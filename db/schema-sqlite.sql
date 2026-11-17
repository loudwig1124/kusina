-- =============================================================================
-- Kusina - SQLite schema for the offline Flutter app (DESIGN ARTIFACT)
--
-- Purpose : data-layer design for docs/08-flutter-architecture.md.
-- Source  : ported from the MySQL design in db/schema.sql. That file is
--           unchanged and remains the contingency design; this file is the
--           Flutter MVP target and is NOT imported into MySQL.
-- Load    : sqlite3 :memory: ".read db/schema-sqlite.sql"
-- App use : sqflite single-file database. Migrations are hand-written in
--           lib/data/db/migrations.dart; schema_meta mirrors PRAGMA user_version.
--
-- AUTHORITATIVE AMENDMENTS: docs/06 section 3.2-3.4 (captain correction)
--   - reason enum: initial | restock | used_some | used_up | waste | correction
--   - table names: stock_status (current state), stock_event (append-only)
--   - stock_event has no kitchen_id: there is exactly one local kitchen
--   - one session_step_choices row per step pins the equipment path
--
-- LOCKED MVP CHANGES
--   a. No users table. One local kitchen row (kitchens.id = 1).
--   b. TRI-STATE presence. stock_status.status only: unknown | have | low |
--      out. NO quantity column. 'low' is the warning face of "present";
--      presence is tri-state: unknown / present(have, low) / absent(out).
--      unknown is a stored value ("Not tracked"); a missing row also reads as
--      unknown defensively (docs/06 A2).
--   c. Signed-quantity ledger replaced by append-only stock_event.
--   d. Recipes kept. recipe_ingredients.quantity/unit_id are DISPLAY-ONLY.
--      recipe_step_variants + session_step_choices implement equipment paths.
--   e. schema_meta stores schema_version and seed_version.
--
-- P1 EXTENSION (not in this file): exact quantities return as
--   ALTER TABLE stock_status ADD COLUMN quantity NUMERIC NULL;
--   ALTER TABLE stock_status ADD COLUMN unit_id INTEGER NULL REFERENCES units(id);
--   ALTER TABLE ingredients ADD COLUMN canonical_unit_id INTEGER NULL REFERENCES units(id);
--   ALTER TABLE units ADD COLUMN factor_to_base NUMERIC NULL;
-- Availability then compares decimal quantities and unit conversion returns to
-- the MVP path; until then none of those columns exist and no arithmetic is
-- done on stock. Exact decimal storage must use integer minor units or TEXT
-- (SQLite NUMERIC affinity is not DECIMAL).
--
-- TIMESTAMPS: all TEXT, ISO-8601 UTC with milliseconds, e.g.
--   2026-11-16T13:45:12.123Z. SQLite has no ON UPDATE CURRENT_TIMESTAMP;
--   writers set updated_at explicitly.
-- =============================================================================

PRAGMA foreign_keys = ON;   -- per connection: sqflite onConfigure must set this
PRAGMA journal_mode = WAL;  -- file databases; :memory: reports "memory"
PRAGMA busy_timeout = 5000;

-- -----------------------------------------------------------------------------
-- 1. schema_meta - schema and seed versioning
-- -----------------------------------------------------------------------------
CREATE TABLE schema_meta (
  id             INTEGER PRIMARY KEY CHECK (id = 1),          -- single row
  schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
  seed_version   INTEGER NOT NULL CHECK (seed_version >= 0),  -- 0 = not seeded
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

INSERT INTO schema_meta (id, schema_version, seed_version) VALUES (1, 1, 0);

-- -----------------------------------------------------------------------------
-- 2. kitchens - exactly one local profile row in the MVP
-- kitchen_uid is the stable string id used by domain/engine models and by the
-- future account/sync tier; it is generated once on first run and never shown.
-- -----------------------------------------------------------------------------
CREATE TABLE kitchens (
  id         INTEGER PRIMARY KEY CHECK (id = 1),              -- single row
  kitchen_uid TEXT NOT NULL UNIQUE
             CHECK (length(kitchen_uid) BETWEEN 16 AND 64),
  name       TEXT NOT NULL DEFAULT 'My Kitchen'
             CHECK (length(trim(name)) BETWEEN 1 AND 100),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- -----------------------------------------------------------------------------
-- 3. units - DISPLAY vocabulary only in the MVP (no conversion factors)
-- -----------------------------------------------------------------------------
CREATE TABLE units (
  id        INTEGER PRIMARY KEY,
  code      TEXT NOT NULL COLLATE NOCASE UNIQUE
            CHECK (length(code) BETWEEN 1 AND 10),
  name      TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 30),
  dimension TEXT NOT NULL CHECK (dimension IN ('mass', 'volume', 'count'))
);

-- -----------------------------------------------------------------------------
-- 4. ingredients - closed shared catalog; code is the stable string id
-- -----------------------------------------------------------------------------
CREATE TABLE ingredients (
  id         INTEGER PRIMARY KEY,
  code       TEXT NOT NULL COLLATE NOCASE UNIQUE
             CHECK (length(code) BETWEEN 1 AND 60),
  name       TEXT NOT NULL COLLATE NOCASE UNIQUE
             CHECK (length(trim(name)) BETWEEN 1 AND 100),
  category   TEXT NOT NULL CHECK (category IN (
               'produce', 'meat', 'seafood', 'dairy_eggs',
               'pantry', 'condiments', 'spices')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX idx_ingredients_category ON ingredients(category);

-- -----------------------------------------------------------------------------
-- 5. equipment - closed, recipe-driven appliance list
-- -----------------------------------------------------------------------------
CREATE TABLE equipment (
  id          INTEGER PRIMARY KEY,
  code        TEXT NOT NULL COLLATE NOCASE UNIQUE
              CHECK (length(code) BETWEEN 1 AND 30),
  name        TEXT NOT NULL COLLATE NOCASE UNIQUE
              CHECK (length(trim(name)) BETWEEN 1 AND 60),
  description TEXT NULL
);

-- Which appliances the single kitchen owns. Ownership never changes stock.
CREATE TABLE kitchen_equipment (
  kitchen_id   INTEGER NOT NULL DEFAULT 1 CHECK (kitchen_id = 1),
  equipment_id INTEGER NOT NULL,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (kitchen_id, equipment_id),
  FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_kitchen_equipment_equipment ON kitchen_equipment(equipment_id);

-- -----------------------------------------------------------------------------
-- 6. stock_status - TRI-STATE current presence, one row per kitchen+ingredient
--
-- 'unknown' is a stored value: "Not tracked". A missing row also reads as
-- 'unknown' defensively (docs/06 A2). Every catalog ingredient seeded for a
-- shipped recipe MUST get a row here: completion updates `WHERE status = <from>`
-- and a missing row would abort the transaction (docs/09 section 3.5).
--
-- presence mapping (locked):
--   'have'    -> present
--   'low'     -> present, warning ("may run short")
--   'out'     -> absent; a required out ingredient is a missing requirement
--   'unknown' -> untracked: never blocks, shown as "Probably have - confirm"
--
-- There is NO quantity column in the MVP. Do not derive or store amounts here.
-- -----------------------------------------------------------------------------
CREATE TABLE stock_status (
  kitchen_id    INTEGER NOT NULL DEFAULT 1 CHECK (kitchen_id = 1),
  ingredient_id INTEGER NOT NULL,
  status        TEXT NOT NULL DEFAULT 'unknown'
                CHECK (status IN ('unknown', 'have', 'low', 'out')),
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (kitchen_id, ingredient_id),
  FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_stock_status_status ON stock_status(status);

-- -----------------------------------------------------------------------------
-- 7. recipes and their requirements
-- -----------------------------------------------------------------------------
CREATE TABLE recipes (
  id           INTEGER PRIMARY KEY,
  name         TEXT NOT NULL COLLATE NOCASE UNIQUE
               CHECK (length(trim(name)) BETWEEN 1 AND 150),
  slug         TEXT NOT NULL COLLATE NOCASE UNIQUE
               CHECK (length(trim(slug)) BETWEEN 1 AND 160),
  description  TEXT NULL,
  cuisine      TEXT NOT NULL DEFAULT 'Filipino',
  servings     INTEGER NOT NULL CHECK (servings > 0),  -- base yield, display only
  prep_minutes INTEGER NULL CHECK (prep_minutes IS NULL OR prep_minutes > 0),
  cook_minutes INTEGER NULL CHECK (cook_minutes IS NULL OR cook_minutes > 0),
  difficulty   TEXT NOT NULL DEFAULT 'easy'
               CHECK (difficulty IN ('easy', 'medium', 'hard')),
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- quantity/unit_id are DISPLAY-ONLY in the MVP: the recipe card prints
-- "1,000 g chicken thighs". They are NOT used for availability, compared, or
-- scaled. No unit conversion exists in the MVP (P1). is_optional = 1 means the
-- ingredient never blocks a recipe.
CREATE TABLE recipe_ingredients (
  recipe_id        INTEGER NOT NULL,
  ingredient_id    INTEGER NOT NULL,
  quantity         NUMERIC NOT NULL CHECK (quantity > 0),  -- display only
  unit_id          INTEGER NOT NULL,                       -- display only
  is_optional      INTEGER NOT NULL DEFAULT 0
                   CHECK (is_optional IN (0, 1)),
  preparation_note TEXT NULL
                   CHECK (preparation_note IS NULL
                          OR length(preparation_note) <= 120),
  PRIMARY KEY (recipe_id, ingredient_id),
  FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_recipe_ingredients_ingredient
  ON recipe_ingredients(ingredient_id);
CREATE INDEX idx_recipe_ingredients_unit ON recipe_ingredients(unit_id);

-- Hard equipment rows. NOTE (docs/09 Q1): for a recipe with a variant group,
-- equipment feasibility must come from planPath(), not from this table alone;
-- this table lists canonical non-group requirements plus the shared path.
CREATE TABLE recipe_equipment (
  recipe_id    INTEGER NOT NULL,
  equipment_id INTEGER NOT NULL,
  PRIMARY KEY (recipe_id, equipment_id),
  FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_recipe_equipment_equipment
  ON recipe_equipment(equipment_id);

-- Linear steps, authored never generated (docs/09 section 2). UNIQUE
-- (recipe_id, step_number) fixes the order; the contiguous 1..N rule and the
-- "exactly one finish at step N" rule are loader lint (L1, L8), not CHECKs.
-- duration_seconds: NULL = no timer; seed 0/negative is normalized to NULL and
-- warned by the loader. ingredient_refs_json is a JSON array of ingredient
-- codes ("[""chicken_thighs"",""bay_leaf""]"); display-only and validated by
-- loader lint L9 (no JSON1 dependency at the SQL layer).
CREATE TABLE recipe_steps (
  id                  INTEGER PRIMARY KEY,
  recipe_id           INTEGER NOT NULL,
  step_number         INTEGER NOT NULL CHECK (step_number > 0),
  kind                TEXT NOT NULL
                      CHECK (kind IN ('prep', 'heat', 'cook', 'wait', 'finish')),
  instruction         TEXT NOT NULL CHECK (length(trim(instruction)) > 0),
  detail              TEXT NULL CHECK (detail IS NULL OR length(detail) <= 120),
  duration_seconds    INTEGER NULL
                      CHECK (duration_seconds IS NULL OR duration_seconds > 0),
  equipment_id        INTEGER NULL,
  ingredient_refs_json TEXT NOT NULL DEFAULT '[]',
  caution             TEXT NULL CHECK (caution IS NULL OR length(caution) <= 90),
  sprite_key          TEXT NOT NULL
                      CHECK (length(trim(sprite_key)) BETWEEN 1 AND 80),
  variant_group       TEXT NULL
                      CHECK (variant_group IS NULL
                             OR length(trim(variant_group)) BETWEEN 1 AND 40),
  UNIQUE (recipe_id, step_number),
  -- docs/09 lint L6/L7 encoded as row constraints
  CHECK (
    (kind IN ('prep', 'finish') AND equipment_id IS NULL)
    OR (kind IN ('heat', 'cook') AND equipment_id IS NOT NULL)
    OR kind = 'wait'
  ),
  CHECK ((kind = 'wait') = (duration_seconds IS NOT NULL)
         OR kind IN ('heat', 'cook')),           -- only wait requires a timer
  CHECK (kind <> 'prep' OR duration_seconds IS NULL),
  CHECK (kind <> 'finish' OR duration_seconds IS NULL),
  FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_recipe_steps_equipment ON recipe_steps(equipment_id);

-- Equipment-dependent step deltas. Selection at runtime: the canonical path
-- wins when satisfiable; otherwise the highest-priority owned variant whose
-- variant_group resolves consistently (docs/09 section 4.2). Variants cannot
-- add/remove steps, change kind, or change ingredient_refs. A variant's
-- equipment must differ from the canonical step's equipment (loader lint L11),
-- and priority is >= 1 (canonical is implicitly 0).
CREATE TABLE recipe_step_variants (
  id                   INTEGER PRIMARY KEY,
  step_id              INTEGER NOT NULL,
  equipment_id         INTEGER NOT NULL,
  instruction_override TEXT NULL
                       CHECK (instruction_override IS NULL
                              OR length(trim(instruction_override)) > 0),
  duration_override    INTEGER NULL
                       CHECK (duration_override IS NULL
                              OR duration_override > 0),
  sprite_override      TEXT NULL
                       CHECK (sprite_override IS NULL
                              OR length(trim(sprite_override)) BETWEEN 1 AND 80),
  priority             INTEGER NOT NULL CHECK (priority >= 1),
  UNIQUE (step_id, equipment_id),
  CHECK (instruction_override IS NOT NULL
         OR duration_override IS NOT NULL
         OR sprite_override IS NOT NULL),
  FOREIGN KEY (step_id) REFERENCES recipe_steps (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_recipe_step_variants_equipment
  ON recipe_step_variants(equipment_id);

-- -----------------------------------------------------------------------------
-- 8. cooking_sessions - guided cook progress + persisted timer
--
-- current_step_number is 1..N+1. N+1 is the REVIEW SENTINEL: advancing from
-- step N enters review without completing the session (docs/09 section 7.3).
-- N is app-enforced, so only the lower bound is a CHECK.
--
-- One active session per kitchen is a PARTIAL UNIQUE INDEX (SQLite supports
-- partial indexes; MySQL could not express this). Completing or abandoning the
-- session frees the slot in the same UPDATE.
--
-- Timer model (docs/06 A5, docs/09 section 6): remaining time is DERIVED,
-- never a ticking counter. Only two fields persist:
--   timer_started_at       TEXT NULL  absolute UTC instant of the running timer
--   timer_duration_seconds INTEGER NULL snapshot of the effective duration
-- Both null = no timer. Both non-null = running. There is no paused state: you
-- cannot pause a pot. Cleared on advance, completion, and abandonment.
-- last_seen_at distinguishes "done" (deadline crossed in the foreground) from
-- "overrun" (crossed while away) without persisting an ended flag.
--
-- started_without_availability / missing_requirements_json record a guide-anyway
-- start. The JSON array holds stable code strings (docs/06 A2):
-- ["equipment:air_fryer","ingredient:bay_leaf","group:cook_method"].
-- servings is the base yield (never scaled in the MVP).
-- -----------------------------------------------------------------------------
CREATE TABLE cooking_sessions (
  id                           INTEGER PRIMARY KEY,
  kitchen_id                   INTEGER NOT NULL DEFAULT 1 CHECK (kitchen_id = 1),
  recipe_id                    INTEGER NOT NULL,
  servings                     INTEGER NOT NULL CHECK (servings > 0),
  status                       TEXT NOT NULL DEFAULT 'in_progress'
                               CHECK (status IN ('in_progress', 'completed',
                                                 'abandoned')),
  current_step_number          INTEGER NOT NULL DEFAULT 1
                               CHECK (current_step_number >= 1),
  started_at                   TEXT NOT NULL
                               DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  completed_at                 TEXT NULL,
  updated_at                   TEXT NOT NULL
                               DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  timer_started_at             TEXT NULL,
  timer_duration_seconds       INTEGER NULL
                               CHECK (timer_duration_seconds IS NULL
                                      OR timer_duration_seconds > 0),
  last_seen_at                 TEXT NULL,
  started_without_availability INTEGER NOT NULL DEFAULT 0
                               CHECK (started_without_availability IN (0, 1)),
  missing_requirements_json    TEXT NULL,
  CHECK (
    (status = 'completed' AND completed_at IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL)
  ),
  CHECK (
    (timer_started_at IS NULL) = (timer_duration_seconds IS NULL)
  ),
  CHECK (
    status = 'in_progress'
    OR (timer_started_at IS NULL AND timer_duration_seconds IS NULL)
  ),
  CHECK (
    (started_without_availability = 0 AND missing_requirements_json IS NULL)
    OR (started_without_availability = 1
        AND missing_requirements_json IS NOT NULL)
  ),
  FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE UNIQUE INDEX uq_cooking_sessions_one_active
  ON cooking_sessions(kitchen_id) WHERE status = 'in_progress';
CREATE INDEX idx_cooking_sessions_status_started
  ON cooking_sessions(status, started_at);
CREATE INDEX idx_cooking_sessions_recipe ON cooking_sessions(recipe_id);

-- -----------------------------------------------------------------------------
-- 9. session_step_choices - the path pinned at start (docs/09 section 3.2)
--
-- One row per step, written in the same transaction as the session. Later
-- equipment edits must never rewrite an active cook, so the engine reads this
-- table instead of recomputing. step_number (not step_id) is the contract key:
-- progress/resume are step-number based. variant_id is set iff is_variant = 1;
-- equipment_id is the appliance the chosen implementation needs, or NULL for an
-- equipment-neutral step.
-- -----------------------------------------------------------------------------
CREATE TABLE session_step_choices (
  session_id   INTEGER NOT NULL,
  step_number  INTEGER NOT NULL CHECK (step_number > 0),
  equipment_id INTEGER NULL,
  is_variant   INTEGER NOT NULL DEFAULT 0 CHECK (is_variant IN (0, 1)),
  variant_id   INTEGER NULL,
  PRIMARY KEY (session_id, step_number),
  CHECK (
    (is_variant = 0 AND variant_id IS NULL)
    OR (is_variant = 1 AND variant_id IS NOT NULL AND equipment_id IS NOT NULL)
  ),
  FOREIGN KEY (session_id) REFERENCES cooking_sessions (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (variant_id) REFERENCES recipe_step_variants (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE INDEX idx_session_step_choices_equipment
  ON session_step_choices(equipment_id);
CREATE INDEX idx_session_step_choices_variant
  ON session_step_choices(variant_id);

-- -----------------------------------------------------------------------------
-- 10. stock_event - append-only presence ledger (docs/06 section 3.3)
--
-- Every status change appends one row in the same transaction that updates
-- stock_status.status. No kitchen_id: there is exactly one local kitchen.
-- from_status <> to_status always; a no-op writes no event.
--
-- Valid reason / transition pairings (also enforced by CHECK):
--   initial    : unknown -> have | low | out          (first record)
--   restock    : unknown | out | low -> have          (obtained stock)
--   used_some  : have | unknown -> low                (cooked/used some)
--   used_up    : have | low | unknown -> out          (used the last of it)
--   waste      : have | low -> out                    (spoiled/discarded)
--   correction : any status -> any DIFFERENT status   (manual correction)
--
-- App-enforced inside one transaction: the event's from_status MUST equal the
-- current stock_status.status (conditional UPDATE ... WHERE status = :from
-- must affect 1 row), and the event insert happens with the status update.
-- cooking_session_id is allowed only for used_some / used_up (the engine's
-- completion writes); manual events leave it NULL.
-- -----------------------------------------------------------------------------
CREATE TABLE stock_event (
  id                 INTEGER PRIMARY KEY,
  ingredient_id      INTEGER NOT NULL,
  from_status        TEXT NOT NULL
                     CHECK (from_status IN ('unknown', 'have', 'low', 'out')),
  to_status          TEXT NOT NULL
                     CHECK (to_status IN ('unknown', 'have', 'low', 'out')),
  reason             TEXT NOT NULL
                     CHECK (reason IN ('initial', 'restock', 'used_some',
                                       'used_up', 'waste', 'correction')),
  cooking_session_id INTEGER NULL,
  note               TEXT NULL CHECK (note IS NULL OR length(note) <= 255),
  created_at         TEXT NOT NULL
                     DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (from_status <> to_status),
  CHECK (
    (reason = 'initial'
      AND from_status = 'unknown' AND to_status IN ('have', 'low', 'out'))
    OR (reason = 'restock'
      AND from_status IN ('unknown', 'out', 'low') AND to_status = 'have')
    OR (reason = 'used_some'
      AND from_status IN ('have', 'unknown') AND to_status = 'low')
    OR (reason = 'used_up'
      AND from_status IN ('have', 'low', 'unknown') AND to_status = 'out')
    OR (reason = 'waste'
      AND from_status IN ('have', 'low') AND to_status = 'out')
    OR (reason = 'correction')
  ),
  CHECK (cooking_session_id IS NULL
         OR reason IN ('used_some', 'used_up')),
  FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  FOREIGN KEY (cooking_session_id) REFERENCES cooking_sessions (id)
    ON DELETE SET NULL ON UPDATE RESTRICT
);

CREATE INDEX idx_stock_event_ingredient_created
  ON stock_event(ingredient_id, created_at);
CREATE INDEX idx_stock_event_session ON stock_event(cooking_session_id);
-- One usage event per ingredient per session: last-line double-completion guard.
CREATE UNIQUE INDEX uq_stock_event_session_ingredient
  ON stock_event(cooking_session_id, ingredient_id)
  WHERE cooking_session_id IS NOT NULL;
