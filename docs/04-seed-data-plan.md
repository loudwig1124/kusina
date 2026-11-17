# Seed Data Plan

**Status:** plan for Phase 2. This file specifies the fixed reference data and
the recipe set. Only `units` and `equipment` are seeded in
[`db/seed-reference.sql`](../db/seed-reference.sql); ingredient, recipe, and
demo-kitchen data are authored during Phase 2.

**Scope:** 9 units, 5 equipment types, 45 ingredients, 12 Filipino recipes.

> **Superseded for the MVP by docs/06 section 3 (amendments A1-A10);**
> **retained as the MySQL/React contingency record.**

## 1. Why a small, closed seed

The project starts with local dishes so the data stays reviewable. The catalog
is closed in v1: users stock and cook existing ingredients but cannot create
new ones. That keeps units, matching, and validation under control.

Each recipe is authored against the same ingredient catalog and the five
equipment types. A recipe can only use equipment that exists, and every
equipment type must be used by at least one recipe; validation queries enforce
both directions.

## 2. Reference data

### 2.1 Units (9)

All stock is stored in the ingredient’s canonical unit. These factors normalize
mass to grams and volume to millilitres.

| Code | Dimension | Factor to base | Typical use |
|---|---|---|---|
| `g` | mass | 1 | Meats, vegetables, dry goods, spices |
| `kg` | mass | 1000 | Bulk stock entry or large recipe quantities |
| `ml` | volume | 1 | Soy sauce, vinegar, oil, milk, coconut milk |
| `l` | volume | 1000 | Bulk liquids |
| `tsp` | volume | 5 | Small liquid seasoning amounts |
| `tbsp` | volume | 15 | Recipe liquid measurements |
| `cup` | volume | 240 | Larger liquid measures |
| `pc` | count | 1 | Onion, tomato, eggplant, corn, calamansi, eggs, bay leaf, packets/cubes |
| `clove` | count | 1 | Garlic only |

Rules:

- Mass converts only to mass; volume only to volume.
- Count units never convert. `pc` and `clove` are not interchangeable.
- Volume units are for liquids. Dry ingredients (flour, sugar, rice, spices)
  must be authored by mass.
- Canonical units in the catalog: garlic by clove; leafy vegetables and meats by
  gram; sauces and oils by millilitre; whole produce and eggs by piece.

### 2.2 Equipment (5)

Equipment is intentionally a **capability list**, not an inventory of every
kitchen object. An appliance is included only when a recipe would be impossible
or materially different without it. Gas, electric, and induction stoves are one
type because v1 recipes do not change between them.

| Code | Name | Covers | Seed dishes that require it |
|---|---|---|---|
| `stovetop` | Stovetop | Gas, electric, or induction stove | 10 dishes |
| `oven` | Oven | Conventional or toaster oven | Baked Macaroni |
| `air_fryer` | Air Fryer | Countertop air fryer | Crispy Pork Belly |
| `grill` | Grill | Charcoal, gas, or electric grill | Chicken Inasal |
| `pressure_cooker` | Pressure Cooker | Stovetop or electric pressure cooker | Bulalo |

Not tracked: knives, chopping boards, pots, pans, spatulas, mixing bowls,
measuring spoons, plates, and other replaceable basics. If a future recipe
genuinely requires a new major appliance (for example, a blender for a specific
sauce), add one equipment row and at least one recipe that uses it; do not grow
the list speculatively.

Why this answers the “there are too many equipment types” concern:

1. The list is bounded by recipes, not by a kitchen catalog.
2. It only includes appliances that gate recipe availability.
3. Functionally equivalent appliances are grouped.
4. Basic tools are assumed and never become onboarding checkboxes.

## 3. Ingredient catalog (45)

Categories are the fixed `ingredients.category` enum values. Names are common
English labels; Filipino names are in parentheses where helpful.

### Produce (17)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Garlic | `clove` | Counted in cloves; a whole head is not a unit. |
| Onion | `pc` | Red or yellow; one medium onion. |
| Ginger | `g` | |
| Tomato | `pc` | |
| Eggplant | `pc` | For Tortang Talong. |
| Squash | `g` | Kalabasa. |
| String beans | `g` | Sitaw. |
| Kangkong | `g` | Water spinach. |
| Pechay | `g` | Bok choy. |
| Cabbage | `g` | |
| Carrot | `g` | |
| Radish | `g` | Labanos. |
| Calamansi | `pc` | |
| Spring onion | `g` | Garnish; often optional. |
| Sayote | `g` | Chayote. |
| Corn | `pc` | One cob. |
| Lemongrass | `g` | |

### Meat (6)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Chicken thighs | `g` | Bone-in or boneless; seed notes specify. |
| Chicken leg quarters | `g` | For inasal. |
| Pork belly | `g` | |
| Pork shoulder | `g` | |
| Ground pork | `g` | |
| Beef shank | `g` | For bulalo; includes bone-in cuts. |

### Seafood (1)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Shrimp | `g` | Optional enrichment in several dishes. |

### Dairy and eggs (4)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Eggs | `pc` | |
| Evaporated milk | `ml` | |
| Cheese | `g` | |
| Butter | `g` | |

### Pantry (9)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Rice | `g` | Raw rice. Sinangag includes a rice-cooking prep step. |
| Bihon noodles | `g` | |
| Macaroni | `g` | |
| All-purpose flour | `g` | |
| Tomato sauce | `ml` | |
| Coconut milk | `ml` | |
| Sugar | `g` | |
| Chicken bouillon | `pc` | One cube or packet. |
| Sinigang mix | `pc` | One packet. |

### Condiments (5)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Cooking oil | `ml` | |
| Soy sauce | `ml` | |
| Vinegar | `ml` | |
| Fish sauce | `ml` | |
| Banana ketchup | `ml` | |

### Spices (3)

| Ingredient | Canonical unit | Notes |
|---|---|---|
| Salt | `g` | |
| Black pepper | `g` | |
| Bay leaf | `pc` | |

No water, ice, or “to taste” items are stocked. Water may appear in step text
but is assumed available. Brand names are avoided; generic local products are
used.

## 4. Recipe lineup (12)

All recipes are Filipino, use the catalog above, and list only equipment that
is truly required. Quantities are for the base yield and are finalized during
Phase 2 using the recipe authoring rules in section 7.

| # | Dish | Base servings | Required equipment | Difficulty | Core required ingredients | Timer steps |
|---|---|---|---|---|---|---|
| 1 | Chicken Adobo | 4 | Stovetop | Easy | Chicken thighs, soy sauce, vinegar, garlic, bay leaf | 3 |
| 2 | Pork Sinigang | 4 | Stovetop | Medium | Pork shoulder, sinigang mix, radish, kangkong, tomato, onion, string beans | 2 |
| 3 | Chicken Tinola | 4 | Stovetop | Easy | Chicken thighs, ginger, garlic, onion, fish sauce, sayote, pechay | 1 |
| 4 | Pancit Bihon Guisado | 4 | Stovetop | Medium | Bihon noodles, pork shoulder, cabbage, carrot, soy sauce, garlic, onion | 2 |
| 5 | Garlic Fried Rice (Sinangag) | 2 | Stovetop | Easy | Rice, garlic | 3 |
| 6 | Tortang Talong | 2 | Stovetop | Easy | Eggplant, eggs | 2 |
| 7 | Ginataang Gulay | 4 | Stovetop | Easy | Coconut milk, squash, string beans, garlic, onion, ginger, fish sauce | 1 |
| 8 | Arroz Caldo | 4 | Stovetop | Easy | Rice, chicken thighs, ginger, garlic, onion, chicken bouillon | 2 |
| 9 | Chicken Inasal | 4 | Grill | Medium | Chicken leg quarters, calamansi, lemongrass, garlic, ginger, banana ketchup, vinegar | 2 |
| 10 | Baked Macaroni | 6 | Stovetop + Oven | Medium | Macaroni, ground pork, tomato sauce, onion, garlic, evaporated milk, cheese, butter, all-purpose flour | 2 |
| 11 | Air-Fried Crispy Pork Belly | 4 | Stovetop + Air Fryer | Medium | Pork belly | 2 |
| 12 | Beef Bulalo | 4 | Pressure Cooker | Medium | Beef shank, corn, cabbage, pechay, onion, garlic, black pepper, fish sauce | 2 |

“Timer steps” is the expected number of steps with a duration. A step can have
one countdown; split a step if it contains two separately timed waits.

**Planned slugs** (stable API/seed identifiers):

```text
chicken-adobo
pork-sinigang
chicken-tinola
pancit-bihon-guisado
sinangag
tortang-talong
ginataang-gulay
arroz-caldo
chicken-inasal
baked-macaroni
air-fried-crispy-pork-belly
beef-bulalo
```

### Equipment coverage

| Equipment | Recipes requiring it |
|---|---|
| Stovetop | 1, 2, 3, 4, 5, 6, 7, 8, 10, 11 (10) |
| Oven | 10 (1) |
| Air Fryer | 11 (1) |
| Grill | 9 (1) |
| Pressure Cooker | 12 (1) |

Every equipment type is used. The four dishes that require a non-stovetop
appliance intentionally show the difference between a fully equipped kitchen
and a basic one. Baked Macaroni
and Crispy Pork Belly also require a stovetop, demonstrating multi-equipment
requirements.

### Recipe selection rationale

- Familiar everyday dishes (adobo, sinigang, tinola, pancit, arroz caldo) keep
  the catalog small and realistic.
- Quick dishes (sinangag, tortang talong, ginataang gulay) give the “cook now”
  list reachable variety.
- One dish per non-stovetop appliance demonstrates the equipment filter without
  bloating the equipment list.
- Optional ingredients (oil, salt, pepper, sugar, garnishes) let the
  minimum-sufficiency rule work without requiring an exhaustively stocked
  pantry.

### Required vs. optional policy

**Required** ingredients define the dish. If one is missing, the recipe is not
available. **Optional** ingredients are seasonings, cooking oil, garnishes, or
enrichments that can be omitted without making the dish impossible.

Guidelines:

- Main protein, defining vegetables, and defining sauces/aromatics are required.
- Cooking oil, salt, pepper, sugar, and garnishes are usually optional.
- Optional ingredients still appear in the consumption review so a cook can
  record their use; they just never block availability.
- Do not mark a structurally necessary ingredient optional just to make a
  recipe appear available.

## 5. Worked example: Chicken Adobo

This is the one fully specified recipe in the design package. It doubles as the
reference format for the other eleven.

**Metadata**

| Field | Value |
|---|---|
| Name | Chicken Adobo |
| Slug | `chicken-adobo` |
| Cuisine | Filipino |
| Base servings | 4 |
| Prep time | 10 minutes |
| Cook time | 35 minutes |
| Difficulty | Easy |
| Required equipment | Stovetop |

**Ingredients**

| Ingredient | Quantity | Unit | Required? | Preparation note |
|---|---:|---|---|---|
| Chicken thighs | 1.000 | kg | Yes | Bone-in, cut into serving pieces |
| Soy sauce | 60 | ml | Yes | |
| Vinegar | 60 | ml | Yes | |
| Garlic | 6 | clove | Yes | Crushed |
| Bay leaf | 3 | pc | Yes | |
| Cooking oil | 30 | ml | No | |
| Black pepper | 2 | g | No | Cracked |
| Sugar | 10 | g | No | |

Water (about 120 ml) is used in step 3 but is not a stocked ingredient.

**Steps**

| # | Instruction | Duration | Equipment hint |
|---|---|---|---|
| 1 | Pat the chicken dry and season with black pepper. | — | — |
| 2 | Heat the cooking oil in a wide pan over medium heat. Brown the chicken on all sides in batches. | 8 min (480 s) | Stovetop |
| 3 | Add the garlic and cook until fragrant. Pour in the soy sauce, vinegar, sugar, and 120 ml water. | — | Stovetop |
| 4 | Add the bay leaves, cover, and simmer until the chicken is tender. | 25 min (1500 s) | Stovetop |
| 5 | Uncover and reduce the sauce, spooning it over the chicken. | 5 min (300 s) | Stovetop |
| 6 | Serve hot with rice. | — | — |

**Availability expectations**

At 4 servings, the required amounts are: 1,000 g chicken thighs, 60 ml soy
sauce, 60 ml vinegar, 6 cloves garlic, and 3 bay leaves. The optional oil,
pepper, and sugar are ignored for availability. The recipe is available when
all five are at or above those amounts; 999.999 g chicken is not enough.

At 2 servings, the requirements halve: 500 g chicken, 30 ml soy sauce, 30 ml
vinegar, 3 cloves garlic, and 1.5 bay leaves.

**Consumption review defaults at 4 servings**

All ingredient lines are prefilled with the scaled estimates, including the
optional items. If an optional ingredient is not stocked, its default is 0.
The cook can edit every line. Examples:

| Ingredient | Default | If zero |
|---|---:|---|
| Chicken thighs | 1,000 g | No chicken transaction |
| Soy sauce | 60 ml | No transaction |
| Cooking oil | 30 ml | No transaction |
| Black pepper | 2 g | No transaction |

Any non-zero actual amount is written as a `consume` transaction linked to the
session. The balance cannot be driven below zero.

## 6. Demo kitchen

The class demo uses a deliberately limited kitchen so availability differences
are visible.

**Equipment:** stovetop, air fryer (no oven, no grill, no pressure cooker)

**Stock** (all with matching `initial` ledger transactions):

| Ingredient | Quantity |
|---|---:|
| Chicken thighs | 1,200 g |
| Pork belly | 1,200 g |
| Rice | 2,000 g |
| Garlic | 12 cloves |
| Onion | 3 pc |
| Soy sauce | 300 ml |
| Vinegar | 300 ml |
| Bay leaf | 5 pc |
| Cooking oil | 500 ml |
| Salt | 500 g |
| Black pepper | 50 g |
| Sugar | 250 g |
| Eggs | 6 pc |
| Eggplant | 2 pc |
| Tomato | 2 pc |
| Ginger | 100 g |
| Fish sauce | 250 ml |
| Calamansi | 6 pc |
| Pechay | 300 g |

**Expected available at base servings:** Chicken Adobo, Sinangag, Tortang
Talong, and Air-Fried Crispy Pork Belly.

**Expected not available:**

| Dish | Reason |
|---|---|
| Baked Macaroni | No oven |
| Chicken Inasal | No grill |
| Beef Bulalo | No pressure cooker |
| Pork Sinigang | No sinigang mix, radish, kangkong, or string beans |
| Chicken Tinola | No sayote |
| Pancit Bihon | No bihon noodles, cabbage, or carrot |
| Ginataang Gulay | No coconut milk, squash, or string beans |
| Arroz Caldo | No chicken bouillon |

**After cooking Chicken Adobo with default amounts:** chicken 200 g, soy sauce
240 ml, vinegar 240 ml, garlic 6 cloves, bay leaf 2 pc. The exact numbers depend
on what the cook edits in the review.

This scenario is also the acceptance test for Phase 2 and Phase 3.

## 7. Recipe authoring rules

1. Author quantities for the recipe’s base yield.
2. Use a compatible mass/volume unit, or the exact count unit. Dry ingredients
   by mass; liquids by volume.
3. At least one required ingredient and at least one step per recipe.
4. At least one equipment row per recipe; every step equipment hint must be in
   that set.
5. Steps are imperative, specific, and ordered. Put one timed wait per step.
6. Duration is in seconds and matches the instruction. A null duration means a
   manual step with no timer.
7. Keep preparation notes short (“minced,” “cut into pieces”); do not hide
   requirements in them.
8. Mark optional only as defined in section 4. Seasonings, oil, and garnishes
   are the normal optional items.
9. Use the catalog’s canonical ingredient names exactly.
10. Keep Filipino dish names; use the common English label in `name` and the
    local name where useful.
11. No images, external URLs, or brand-specific products in v1.
12. Validate the data with section 8 before building the recipe UI.

## 8. Validation queries

Run these after loading the recipe seed. Each returns **no rows** unless stated.

### 8.1 Unit compatibility

```sql
SELECT
    ri.recipe_id,
    ri.ingredient_id,
    ru.code AS recipe_unit,
    cu.code AS canonical_unit
FROM recipe_ingredients ri
JOIN ingredients i ON i.id = ri.ingredient_id
JOIN units ru ON ru.id = ri.unit_id
JOIN units cu ON cu.id = i.canonical_unit_id
WHERE ru.dimension <> cu.dimension
   OR (ru.dimension = 'count' AND ru.id <> cu.id);
```

### 8.2 Step numbers are contiguous and every recipe has steps

```sql
WITH numbered AS (
    SELECT
        recipe_id,
        step_number,
        ROW_NUMBER() OVER (
            PARTITION BY recipe_id ORDER BY step_number
        ) AS expected_number
    FROM recipe_steps
)
SELECT recipe_id, step_number, expected_number
FROM numbered
WHERE step_number <> expected_number;

SELECT r.slug
FROM recipes r
LEFT JOIN recipe_steps s ON s.recipe_id = r.id
GROUP BY r.id, r.slug
HAVING COUNT(s.id) = 0;
```

### 8.3 Equipment coverage

Every equipment row must be used by at least one recipe:

```sql
SELECT e.code
FROM equipment e
LEFT JOIN recipe_equipment re ON re.equipment_id = e.id
WHERE re.equipment_id IS NULL;
```

Every recipe must require at least one appliance:

```sql
SELECT r.slug
FROM recipes r
LEFT JOIN recipe_equipment re ON re.recipe_id = r.id
GROUP BY r.id, r.slug
HAVING COUNT(re.equipment_id) = 0;
```

### 8.4 Step equipment hints are a subset of required equipment

```sql
SELECT DISTINCT s.recipe_id, s.equipment_id
FROM recipe_steps s
WHERE s.equipment_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM recipe_equipment re
      WHERE re.recipe_id = s.recipe_id
        AND re.equipment_id = s.equipment_id
  );
```

### 8.5 Every recipe has at least one required ingredient

```sql
SELECT r.slug
FROM recipes r
WHERE NOT EXISTS (
    SELECT 1
    FROM recipe_ingredients ri
    WHERE ri.recipe_id = r.id
      AND ri.is_optional = 0
);
```

### 8.6 Stock balances match the ledger

Use the reconciliation query in
[03-database-design.md](03-database-design.md#74-reconciliation-check). It should
return no rows, including for the demo kitchen.

### 8.7 Expected demo availability

After loading the demo kitchen, the availability query should return exactly:

```text
chicken-adobo
sinangag
tortang-talong
air-fried-crispy-pork-belly
```

Ordering may vary; compare as a set.

## 9. Data quality and safety

- Nutrition, allergens, and medical claims are out of scope. Add a short
  “cook thoroughly / use safe food handling” note in the UI instead of implying
  certified food safety.
- Quantities and timings are starting points. Review them during Phase 2; the
  schema and rules are the deliverable here, not a claim that every recipe has
  been kitchen-tested.
- No brand names, sponsored products, or external recipe copies.
- Use grams for meat and leafy vegetables so leftover amounts are trackable.
- Avoid “a pinch” and “to taste” as required quantities; move them to optional
  items or step text.

## 10. Phase 2 handoff checklist

- [ ] Add all 45 ingredients with the canonical units above.
- [ ] Add 12 recipes with unique names/slugs and base servings.
- [ ] Add required/optional ingredients, equipment, and ordered steps.
- [ ] Implement the demo kitchen with initial ledger transactions.
- [ ] Run all validation queries from section 8; all must pass.
- [ ] Confirm the expected available set from section 6.
- [ ] Only then wire the recipe UI to real seed data.
