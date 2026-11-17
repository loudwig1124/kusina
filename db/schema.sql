-- =============================================================================
-- Kusina - Kitchen Inventory & Guided Cooking
-- MySQL 8.0.16+ schema (CHECK constraints are enforced from 8.0.16 onward)
--
-- Import on a fresh database:
--   mysql -u your_user -p < db/schema.sql
--
-- This file is non-destructive: it creates the database if needed and then
-- creates the tables. It never drops existing data; if tables already exist,
-- the import stops rather than overwriting them. Run db/seed-reference.sql after it.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS kusina
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE kusina;

-- -----------------------------------------------------------------------------
-- Accounts and kitchens
-- -----------------------------------------------------------------------------

CREATE TABLE users (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(255)    NOT NULL,
  password_hash VARCHAR(255)    NOT NULL,
  display_name  VARCHAR(100)    NOT NULL,
  created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE = InnoDB;

-- One kitchen per user in v1. The UNIQUE key is the database-level enforcement
-- of that product rule; see docs/03-database-design.md for the future migration.
CREATE TABLE kitchens (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_user_id BIGINT UNSIGNED NOT NULL,
  name          VARCHAR(100)    NOT NULL DEFAULT 'My Kitchen',
  created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_kitchens_owner (owner_user_id),
  CONSTRAINT fk_kitchens_owner
    FOREIGN KEY (owner_user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Shared reference/catalog data
-- -----------------------------------------------------------------------------

-- Base factors: mass -> grams, volume -> millilitres, count -> whole units.
-- Mass and volume may be converted within their dimension. Count units are
-- only converted when the unit is identical (pc is not interchangeable with
-- clove), so "count" is a grouping label rather than a convertible dimension.
CREATE TABLE units (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code           VARCHAR(10)     NOT NULL,
  name           VARCHAR(30)     NOT NULL,
  dimension      ENUM('mass', 'volume', 'count') NOT NULL,
  factor_to_base DECIMAL(18, 6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_units_code (code),
  CONSTRAINT ck_units_factor CHECK (factor_to_base > 0)
) ENGINE = InnoDB;

-- Ingredients are shared catalog data. Each ingredient has exactly one
-- canonical unit; all stock quantities for it are stored in that unit.
CREATE TABLE ingredients (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name              VARCHAR(100)    NOT NULL,
  category          ENUM('produce', 'meat', 'seafood', 'dairy_eggs',
                         'pantry', 'condiments', 'spices') NOT NULL,
  canonical_unit_id BIGINT UNSIGNED NOT NULL,
  created_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ingredients_name (name),
  KEY idx_ingredients_category (category),
  KEY idx_ingredients_unit (canonical_unit_id),
  CONSTRAINT fk_ingredients_unit
    FOREIGN KEY (canonical_unit_id) REFERENCES units (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- A closed, recipe-driven list of major appliances. Basic tools (knives, pots,
-- pans, boards, spoons) are assumed available and are deliberately not tracked.
CREATE TABLE equipment (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code        VARCHAR(30)     NOT NULL,
  name        VARCHAR(60)     NOT NULL,
  description VARCHAR(255)    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_equipment_code (code),
  UNIQUE KEY uq_equipment_name (name)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Kitchen stock
-- -----------------------------------------------------------------------------

-- Current stock balance per kitchen/ingredient, stored in the ingredient's
-- canonical unit. This row and the matching ledger row are always written in
-- one transaction; quantity must never go below zero.
CREATE TABLE inventory_items (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  kitchen_id    BIGINT UNSIGNED NOT NULL,
  ingredient_id BIGINT UNSIGNED NOT NULL,
  quantity      DECIMAL(12, 3)  NOT NULL DEFAULT 0,
  created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_inventory_kitchen_ingredient (kitchen_id, ingredient_id),
  KEY idx_inventory_ingredient (ingredient_id),
  CONSTRAINT ck_inventory_quantity CHECK (quantity >= 0),
  CONSTRAINT fk_inventory_kitchen
    FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_inventory_ingredient
    FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

CREATE TABLE kitchen_equipment (
  kitchen_id   BIGINT UNSIGNED NOT NULL,
  equipment_id BIGINT UNSIGNED NOT NULL,
  created_at   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (kitchen_id, equipment_id),
  KEY idx_kitchen_equipment_equipment (equipment_id),
  CONSTRAINT fk_kitchen_equipment_kitchen
    FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_kitchen_equipment_equipment
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Recipes
-- -----------------------------------------------------------------------------

CREATE TABLE recipes (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name         VARCHAR(150)    NOT NULL,
  slug         VARCHAR(160)    NOT NULL,
  description  TEXT            NULL,
  cuisine      VARCHAR(50)     NOT NULL DEFAULT 'Filipino',
  servings     SMALLINT UNSIGNED NOT NULL,
  prep_minutes SMALLINT UNSIGNED NULL,
  cook_minutes SMALLINT UNSIGNED NULL,
  difficulty   ENUM('easy', 'medium', 'hard') NOT NULL DEFAULT 'easy',
  created_at   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipes_name (name),
  UNIQUE KEY uq_recipes_slug (slug),
  CONSTRAINT ck_recipes_servings CHECK (servings > 0)
) ENGINE = InnoDB;

-- Quantities are for the recipe's base yield (recipes.servings). The unit may
-- be a compatible mass or volume unit, or the ingredient's exact count unit.
-- A recipe ingredient appears at most once; preparation belongs in the note.
CREATE TABLE recipe_ingredients (
  recipe_id        BIGINT UNSIGNED NOT NULL,
  ingredient_id    BIGINT UNSIGNED NOT NULL,
  quantity         DECIMAL(12, 3)  NOT NULL,
  unit_id          BIGINT UNSIGNED NOT NULL,
  is_optional      BOOLEAN         NOT NULL DEFAULT FALSE,
  preparation_note VARCHAR(120)    NULL,
  PRIMARY KEY (recipe_id, ingredient_id),
  KEY idx_recipe_ingredients_ingredient (ingredient_id),
  KEY idx_recipe_ingredients_unit (unit_id),
  CONSTRAINT ck_recipe_ingredients_quantity CHECK (quantity > 0),
  CONSTRAINT ck_recipe_ingredients_optional CHECK (is_optional IN (0, 1)),
  CONSTRAINT fk_recipe_ingredients_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_recipe_ingredients_ingredient
    FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_recipe_ingredients_unit
    FOREIGN KEY (unit_id) REFERENCES units (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- Every listed appliance is required by the recipe and is used by availability
-- filtering. There is no "optional" equipment in v1: do not list conveniences.
CREATE TABLE recipe_equipment (
  recipe_id    BIGINT UNSIGNED NOT NULL,
  equipment_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (recipe_id, equipment_id),
  KEY idx_recipe_equipment_equipment (equipment_id),
  CONSTRAINT fk_recipe_equipment_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_recipe_equipment_equipment
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- Steps are linear. step_number must form 1..N; the contiguous range is checked
-- by the seed validation query because a CHECK constraint cannot span rows.
-- A non-null duration_seconds tells the UI to offer a countdown timer.
CREATE TABLE recipe_steps (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipe_id        BIGINT UNSIGNED NOT NULL,
  step_number      SMALLINT UNSIGNED NOT NULL,
  instruction      TEXT            NOT NULL,
  duration_seconds INT UNSIGNED    NULL,
  equipment_id     BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipe_steps_recipe_number (recipe_id, step_number),
  KEY idx_recipe_steps_equipment (equipment_id),
  CONSTRAINT ck_recipe_steps_number CHECK (step_number > 0),
  CONSTRAINT ck_recipe_steps_duration CHECK (
    duration_seconds IS NULL OR duration_seconds > 0
  ),
  CONSTRAINT fk_recipe_steps_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_recipe_steps_equipment
    FOREIGN KEY (equipment_id) REFERENCES equipment (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Guided cooking
-- -----------------------------------------------------------------------------

-- One active session per user is an application rule (not expressible as a
-- simple partial unique key here). current_step_number is 1-based and tracks
-- the step currently shown; recipes are treated as immutable during a session.
CREATE TABLE cooking_sessions (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id             BIGINT UNSIGNED NOT NULL,
  kitchen_id          BIGINT UNSIGNED NOT NULL,
  recipe_id           BIGINT UNSIGNED NOT NULL,
  servings            SMALLINT UNSIGNED NOT NULL,
  status              ENUM('in_progress', 'completed', 'abandoned')
                      NOT NULL DEFAULT 'in_progress',
  current_step_number SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  started_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at        TIMESTAMP       NULL,
  updated_at          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
                                      ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_sessions_user_status (user_id, status),
  KEY idx_sessions_kitchen (kitchen_id),
  KEY idx_sessions_recipe (recipe_id),
  CONSTRAINT ck_sessions_servings CHECK (servings > 0),
  CONSTRAINT ck_sessions_step CHECK (current_step_number >= 1),
  CONSTRAINT ck_sessions_completed CHECK (
    (status = 'completed' AND completed_at IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL)
  ),
  CONSTRAINT fk_sessions_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_sessions_kitchen
    FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_sessions_recipe
    FOREIGN KEY (recipe_id) REFERENCES recipes (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Append-only stock ledger
-- -----------------------------------------------------------------------------

-- Never update or delete rows in normal operation. quantity_delta is signed:
-- positive for stock in, negative for stock out. A session link is allowed only
-- for consumption entries. That rule and the session/kitchen ownership match are
-- app-validated: MySQL does not allow a CHECK on a column used by a SET NULL FK.
CREATE TABLE inventory_transactions (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  kitchen_id         BIGINT UNSIGNED NOT NULL,
  ingredient_id      BIGINT UNSIGNED NOT NULL,
  quantity_delta     DECIMAL(12, 3)  NOT NULL,
  reason             ENUM('initial', 'restock', 'consume', 'waste',
                           'adjustment') NOT NULL,
  cooking_session_id BIGINT UNSIGNED NULL,
  note               VARCHAR(255)    NULL,
  created_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_transactions_kitchen_created (kitchen_id, created_at),
  KEY idx_transactions_ingredient (ingredient_id),
  KEY idx_transactions_session (cooking_session_id),
  CONSTRAINT ck_transactions_delta CHECK (quantity_delta <> 0),
  CONSTRAINT ck_transactions_reason_sign CHECK (
    (reason IN ('initial', 'restock') AND quantity_delta > 0)
    OR (reason IN ('consume', 'waste') AND quantity_delta < 0)
    OR (reason = 'adjustment')
  ),
  CONSTRAINT fk_transactions_kitchen
    FOREIGN KEY (kitchen_id) REFERENCES kitchens (id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_transactions_ingredient
    FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_transactions_session
    FOREIGN KEY (cooking_session_id) REFERENCES cooking_sessions (id)
    ON DELETE SET NULL
    ON UPDATE RESTRICT
) ENGINE = InnoDB;
