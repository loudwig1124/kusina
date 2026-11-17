-- =============================================================================
-- Kusina - reference seed data
-- MySQL 8.0.16+
--
-- Import after db/schema.sql:
--   mysql -u your_user -p < db/seed-reference.sql
--
-- This file is idempotent and safe to run more than once. Existing reference
-- rows are left unchanged, which is intentional for this fixed data. It seeds
-- only units and the closed equipment list. Ingredient and recipe seed data
-- belongs to Phase 2; see docs/04-seed-data-plan.md.
-- =============================================================================

USE kusina;

-- Base factors: mass -> grams, volume -> millilitres, count -> whole units.
-- Volume units are for liquids only. Count units are not interchangeable
-- (pc != clove), so recipe count units must match the ingredient exactly.
INSERT IGNORE INTO units (code, name, dimension, factor_to_base) VALUES
  ('g',     'gram',       'mass',   1.000000),
  ('kg',    'kilogram',   'mass',   1000.000000),
  ('ml',    'millilitre', 'volume', 1.000000),
  ('l',     'litre',      'volume', 1000.000000),
  ('tsp',   'teaspoon',   'volume', 5.000000),
  ('tbsp',  'tablespoon', 'volume', 15.000000),
  ('cup',   'cup',        'volume', 240.000000),
  ('pc',    'piece',      'count',  1.000000),
  ('clove', 'clove',      'count',  1.000000);

-- Closed, recipe-driven equipment list. Every item is required by at least one
-- seeded recipe. Gas, electric, and induction stoves are grouped as "stovetop"
-- because v1 recipes do not behave differently on them.
INSERT IGNORE INTO equipment (code, name, description) VALUES
  ('stovetop', 'Stovetop',
   'Gas, electric, or induction stove used for pan- and pot-based cooking.'),
  ('oven', 'Oven',
   'Conventional oven or toaster oven used for baking and roasting.'),
  ('air_fryer', 'Air Fryer',
   'Countertop air fryer used for quick, high-heat cooking.'),
  ('grill', 'Grill',
   'Charcoal, gas, or electric grill used for grilling.'),
  ('pressure_cooker', 'Pressure Cooker',
   'Stovetop or electric pressure cooker used for faster boiling and braising.');
