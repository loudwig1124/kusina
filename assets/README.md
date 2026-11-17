# Kusina content: fixtures (Phase A) and seed rows (Phase B)

This folder is the **single content source** for the app. Phase A reads the JSON under
`fixtures/` directly; the Phase B seed loader inserts the JSON under `seed/` into SQLite.
Nothing here is generated at runtime, and no screen or engine file owns content.

Both halves carry the same 3 dishes, 15 ingredients and 5 appliances. `tool/validate_content.py`
proves they are identical (parity), internally valid, and actually loadable: it inserts every seed
row into an in-memory SQLite database built from `db/schema-sqlite.sql`, so a FK, CHECK or UNIQUE
the rows cannot satisfy fails the run.

```bash
python3 tool/validate_content.py   # exit 0 = valid, 1 = errors on stderr
```

Register these paths in `pubspec.yaml` when the Flutter scaffold lands:

```yaml
flutter:
  assets:
    - assets/fixtures/
    - assets/fixtures/recipes/
    - assets/seed/
```

No calendar dates, quantities-as-numbers or serving scaling live in this content beyond the
display-only `quantity`/`unit` line labels (docs/06 A6). The user owns scheduling.

---

## 1. `fixtures/` — the Phase A shapes

| File | Contents |
|---|---|
| `ingredients.json` | 15 catalog ingredients: `id`, `name`, `filipinoGloss`, `category`, `displayUnit`, `defaultStatus`, `spriteKey` |
| `equipment.json` | 5 appliances: `id`, `name`, `description`, `shipped`, `pickerNote`, `spriteKey` |
| `recipes/chicken-adobo.json` | 7 steps, 4 servings, `stovetop`, 35 cook minutes |
| `recipes/sinangag.json` | 5 steps, 2 servings, `stovetop`, 20 cook minutes |
| `recipes/crispy-pork-belly.json` | 6 canonical steps, 2 explicit methods, 4 servings |
| `kitchen_demo.json` | `Maria's Kitchen`, `{stovetop, air_fryer}`, the docs/06 section 7 demo statuses |

Every file starts with `"seedVersion": 1`. A recipe file is `{"seedVersion": 1, "recipe": {...}}`;
the loader reads `recipes/*.json` (any order) and sorts by `recipe.sortOrder` (1 Adobo,
2 Sinangag, 3 Crispy Pork Belly).

### 1.1 Ingredient fields

| Field | Meaning |
|---|---|
| `id` | stable snake_case code; the seed's `ingredients.code`; also `ing_<id>` sprite |
| `name` | English label, exactly the docs/04 section 3 spelling |
| `filipinoGloss` | Filipino name for the "English (Filipino)" label, e.g. `Garlic (Bawang)` |
| `category` | `produce \| meat \| seafood \| dairy_eggs \| pantry \| condiments \| spices` |
| `displayUnit` | display vocabulary only: `g`, `ml`, `pc`, `clove` (never converted) |
| `defaultStatus` | `unknown` for every ingredient: the stock row a fresh kitchen gets (docs/09 section 3.5) |
| `spriteKey` | `ing_<id>`, always in the docs/07 section 11.3 manifest |

Natural English glosses, kept short and respectful (docs/07 section 12):

| Ingredient | Gloss | Ingredient | Gloss | Ingredient | Gloss |
|---|---|---|---|---|---|
| Chicken thighs | Hita ng manok | Soy sauce | Toyo | Sugar | Asukal |
| Pork belly | Liempo | Vinegar | Suka | Spring onion | Sibuyas dahon |
| Rice | Bigas (raw rice) | Bay leaf | Laurel | Calamansi | Kalamansi |
| Garlic | Bawang | Cooking oil | Mantika | Eggs | Itlog |
| | | Salt | Asin | Banana ketchup | Ketsap ng saging |
| | | Black pepper | Paminta | | |

### 1.2 Equipment

`shipped: true` means a shipped dish uses it (`stovetop`, `air_fryer`). The other three
(`oven`, `grill`, `pressure_cooker`) are seeded so the picker is future-proof and carry
`pickerNote: "No dishes yet"` (docs/06 Q3 default). `pickerNote` is null for shipped rows.

### 1.3 Recipe fields

`id`, `slug`, `name`, `description`, `cuisine`, `baseServings`, `prepMinutes`, `cookMinutes`,
`difficulty`, `sortOrder`, `dishStampKey`, `requiredEquipment`, `methods`, `ingredients`, `steps`.

- `prepMinutes`/`cookMinutes` are display metadata, not a sum of step timers (docs/04 section 5
  itself shows 35 cook minutes over 38 minutes of Adobo timers).
- `requiredEquipment` lists the **method-independent** appliances: `{stovetop}` for Adobo and
  Sinangag, `[]` for the method dish (see 1.5).
- `ingredients[]`: `ingredient`, `quantity`, `unit` (must equal the ingredient's `displayUnit`),
  `optional`, `preparationNote` (null or <= 120 characters). Quantity is a label: no rule reads it.

### 1.4 Steps

| Field | Rule |
|---|---|
| `stepNumber` | contiguous `1..N`; one `finish`, always step N |
| `kind` | `prep \| heat \| cook \| wait \| finish` |
| `instruction` | <= 180 characters, at most 2 sentences, no branching copy |
| `detail` | null or <= 120 characters; secondary technique line |
| `durationSeconds` | `> 0` only on `heat`/`cook`/`wait`; `wait` requires it; `prep`/`finish` must be null |
| `equipment` | null for `prep`/`finish`; required for `heat`/`cook`; optional for `wait` |
| `ingredientRefs` | catalog ids that also appear on the recipe's ingredient list (docs/09 lint L9) |
| `caution` | null or <= 90 characters, imperative, safety/irreversible-action only |
| `spriteKey` | explicit; one of the seven `step_<kind>_<equipment>` keys in the manifest |
| `variantGroup` | null, or the share group for method-dependent steps (`cook_method`) |
| `variants` | `[]`, or one override per method key (see 1.5) |

### 1.5 Methods: the cook's explicit choice (Crispy Pork Belly)

```json
"methods": [
  {"key": "pan_fry", "label": "Pan-fry", "equipment": "stovetop", "iconKey": "variant_panfry", "canonical": false},
  {"key": "air_fry", "label": "Air-fry", "equipment": "air_fryer", "iconKey": "variant_airfry", "canonical": true}
]
```

There is exactly **one** canonical step list. A step changes with the method only when it carries
`variants` (here step 5, the crisp step); every other step is shared and falls back to its
canonical text. A variant carries the delta the db schema allows (`recipe_step_variants`):
instruction, duration, sprite, priority — never an ingredient line, so ingredient requirements are
identical across methods (docs/06 C5 / F-03; cooking oil is statically optional).

**Resolution rule** (implemented by `tool/validate_content.py`, so the Dart side must match):

```
for each step:
  if step has no variants        -> canonical implementation, for every method
  else if a variant method==key  -> that variant (equipment, instruction, duration, sprite)
  else if method.canonical and step.equipment == method.equipment
                                 -> canonical implementation (the air-fry path)
  else                           -> the method cannot resolve (content error)
```

`canonical: true` marks the method implemented by the canonical step rows: the dish is named for
the air fryer (docs/09 section 4.3), so air-fry is canonical and pan-fry is a priority-10 stovetop
variant. **No auto-selection**: the recipe detail screen asks the cook to pick one; the chosen
method is pinned at start, per step, in the existing `session_step_choices` table
(`equipment_id`, `is_variant`, `variant_id`) — no schema change. `canonical` only tells the loader
which rows are variants; it is never used to pick a method for the cook.

`requiredEquipment` is empty for this dish: the method declares its appliance, so availability is
the union of the method-independent step appliances (`stovetop`, from the boil) and the chosen
method's appliance (`stovetop` for pan-fry, `air_fryer` for air-fry). `recipe_equipment` therefore
has no rows for this recipe in `seed/recipe_equipment.json`.

### 1.6 Kitchen demo

`kitchen_demo.json` is the docs/06 section 7 demo state: kitchen `Maria's Kitchen`, equipment
`{stovetop, air_fryer}`, and one status per ingredient (`have` 11, `low` 1, `out` 1, `unknown` 2).
With it: **Chicken Adobo is blocked on `ingredient:bay_leaf`**, **Sinangag is ready**, and the
**pork belly is ready** on both methods.

---

## 2. `seed/` — the Phase B row shapes

Each file is a JSON array of rows whose columns are exactly the columns of the matching table in
`db/schema-sqlite.sql` (validator-checked, so nothing is invented). Timestamp columns
(`created_at`, `updated_at`) are omitted on purpose: the DDL defaults fill them, so the seed carries
no dates at all.

| File | Table | Rows | Columns |
|---|---|---:|---|
| `units.json` | `units` | 9 | `id, code, name, dimension` |
| `ingredients.json` | `ingredients` | 15 | `id, code, name, category` |
| `equipment.json` | `equipment` | 5 | `id, code, name, description` |
| `kitchens.json` | `kitchens` | 1 | `id, kitchen_uid, name` |
| `kitchen_equipment.json` | `kitchen_equipment` | 2 | `kitchen_id, equipment_id` |
| `stock_status.json` | `stock_status` | 15 | `kitchen_id, ingredient_id, status` |
| `recipes.json` | `recipes` | 3 | `id, name, slug, description, cuisine, servings, prep_minutes, cook_minutes, difficulty` |
| `recipe_equipment.json` | `recipe_equipment` | 2 | `recipe_id, equipment_id` |
| `recipe_ingredients.json` | `recipe_ingredients` | 26 | `recipe_id, ingredient_id, quantity, unit_id, is_optional, preparation_note` |
| `recipe_steps.json` | `recipe_steps` | 18 | `id, recipe_id, step_number, kind, instruction, detail, duration_seconds, equipment_id, ingredient_refs_json, caution, sprite_key, variant_group` |
| `recipe_step_variants.json` | `recipe_step_variants` | 1 | `id, step_id, equipment_id, instruction_override, duration_override, sprite_override, priority` |

`units` and `kitchen_equipment` are the reference rows the foreign keys require
(`recipe_ingredients.unit_id`, `kitchen_equipment`), not extra content.

Stable ids, chosen once and never derived: recipes `1` Adobo, `2` Sinangag, `3` Air-Fried Crispy
Pork Belly; steps in that order (`1..7`, `8..12`, `13..18`, so the crisp step is `17`); the single
pan-fry variant is `1` on step `17`. `ingredient_refs_json` is a compact JSON array of ingredient
codes, e.g. `["garlic","soy_sauce"]`.

---

## 3. Decisions recorded here

1. **Adobo is 7 steps**, docs/09 section 2.5's split of docs/04's step 2 into `heat` + `cook`;
   durations 480 / 1500 / 300 seconds and the instruction/caution copy follow that worked example.
2. **Adobo step 7 carries no `ingredientRefs`.** docs/09 section 2.5 lists `rice`, but rice is not
   an Adobo ingredient line (docs/06 section 5) and docs/09 lint L9 rejects a step reference that is
   not on the recipe. The copy still reads "Serve hot with rice."
3. **Cooking oil is statically optional** on the pork belly for both methods; docs/06 section 5's
   "R for pan-fry / O for air-fry" split is superseded by docs/06 C5 / F-03, because a variant
   cannot change `is_optional`. The methods still differ in copy, duration (1200 s vs 720 s) and
   sprite (`step_cook_air_fryer` vs `step_cook_stovetop`).
4. **`recipe_equipment` is empty for the method dish** because the method declares its appliance
   (the task's variant of docs/09 Q1 / F-04). Equipment feasibility comes from 1.5, not from
   `recipe_equipment` alone; the validator checks it that way.
5. **`Kalamansi`** is the Filipino spelling of the gloss for `Calamansi`; the English label keeps the
   docs/04 spelling.
6. **Demo statuses from docs/06 section 7** are the seed's `stock_status` rows (resetting demo data
   restores exactly these), and every catalog ingredient has a row (docs/09 section 3.5).
