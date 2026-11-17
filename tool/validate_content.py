#!/usr/bin/env python3
"""Validate the Kusina fixture and seed content (pure Python 3, standard library only).

Checks the content contract shared by the Phase A fixture loaders and the Phase B
SQLite seed loader (docs/08 sections 4.4 and 6, docs/09 section 2 and 4):

  1. every JSON file parses;
  2. every referenced id exists (ingredient, equipment, unit, recipe, step, kitchen);
  3. step numbers are contiguous 1..N with exactly one finish at step N;
  4. a duration exists and is > 0 only on wait/heat/cook steps;
  5. every declared method resolves on every step (variant override or canonical
     fallback) and no variant changes an ingredient line;
  6. every sprite key used exists in the docs/07 section 11.3 asset manifest;
  7. the demo kitchen yields Adobo blocked on bay_leaf and Sinangag ready;
  8. the pork belly is ready when both appliances are owned and reports
     `equipment:stovetop` / `equipment:air_fryer` when the chosen appliance is not;
  9. fixture content equals the seed rows, and the seed rows mirror the columns of
     db/schema-sqlite.sql (no invented columns).

No third-party packages, no network, no clock, no randomness: two runs produce the
same output. Exit code 0 = valid, 1 = one or more errors (each printed to stderr).
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "assets" / "fixtures"
RECIPE_FIXTURES = FIXTURES / "recipes"
SEED = ROOT / "assets" / "seed"
PIXEL_SPEC = ROOT / "docs" / "07-pixel-ui-spec.md"
SCHEMA_SQL = ROOT / "db" / "schema-sqlite.sql"

# ---------------------------------------------------------------------------
# Locked vocabulary (docs/06 section 3.4, docs/09 sections 2.3, 8.1; db schema)
# ---------------------------------------------------------------------------
SEED_VERSION = 1
INGREDIENT_CATEGORIES = ("produce", "meat", "seafood", "dairy_eggs", "pantry", "condiments", "spices")
STOCK_STATUSES = ("unknown", "have", "low", "out")
STEP_KINDS = ("prep", "heat", "cook", "wait", "finish")
DIFFICULTIES = ("easy", "medium", "hard")
UNIT_DIMENSIONS = ("mass", "volume", "count")
UNIT_CODES = ("g", "kg", "ml", "l", "tsp", "tbsp", "cup", "pc", "clove")

LOCKED_DISHES = {
    "chicken-adobo": {"name": "Chicken Adobo", "servings": 4, "steps": 7, "equipment": ["stovetop"]},
    "sinangag": {"name": "Sinangag", "servings": 2, "steps": 5, "equipment": ["stovetop"]},
    "crispy-pork-belly": {
        "name": "Crispy Pork Belly",
        "servings": 4,
        "steps": None,
        "equipment": [],
    },
}
SHIPPED_EQUIPMENT = ("stovetop", "air_fryer")
UNUSED_EQUIPMENT = ("oven", "grill", "pressure_cooker")
UNUSED_NOTE = "No dishes yet"
DEMO_KITCHEN_NAME = "Maria's Kitchen"

EXPECTED_METHODS = {
    "pan_fry": {"label": "Pan-fry", "equipment": "stovetop"},
    "air_fry": {"label": "Air-fry", "equipment": "air_fryer"},
}

# Column sets the loader writes; each must also exist as a column in the DDL.
SEED_COLUMNS = {
    "units.json": {"id", "code", "name", "dimension"},
    "ingredients.json": {"id", "code", "name", "category"},
    "equipment.json": {"id", "code", "name", "description"},
    "kitchens.json": {"id", "kitchen_uid", "name"},
    "kitchen_equipment.json": {"kitchen_id", "equipment_id"},
    "stock_status.json": {"kitchen_id", "ingredient_id", "status"},
    "recipes.json": {
        "id", "name", "slug", "description", "cuisine",
        "servings", "prep_minutes", "cook_minutes", "difficulty",
    },
    "recipe_equipment.json": {"recipe_id", "equipment_id"},
    "recipe_ingredients.json": {
        "recipe_id", "ingredient_id", "quantity", "unit_id", "is_optional", "preparation_note",
    },
    "recipe_steps.json": {
        "id", "recipe_id", "step_number", "kind", "instruction", "detail",
        "duration_seconds", "equipment_id", "ingredient_refs_json", "caution",
        "sprite_key", "variant_group",
    },
    "recipe_step_variants.json": {
        "id", "step_id", "equipment_id", "instruction_override",
        "duration_override", "sprite_override", "priority",
    },
}
SEED_TABLES = {
    "units.json": "units",
    "ingredients.json": "ingredients",
    "equipment.json": "equipment",
    "kitchens.json": "kitchens",
    "kitchen_equipment.json": "kitchen_equipment",
    "stock_status.json": "stock_status",
    "recipes.json": "recipes",
    "recipe_equipment.json": "recipe_equipment",
    "recipe_ingredients.json": "recipe_ingredients",
    "recipe_steps.json": "recipe_steps",
    "recipe_step_variants.json": "recipe_step_variants",
}

RECIPE_KEYS = {
    "id", "slug", "name", "description", "cuisine", "baseServings", "prepMinutes",
    "cookMinutes", "difficulty", "sortOrder", "dishStampKey", "requiredEquipment",
    "methods", "ingredients", "steps",
}
METHOD_KEYS = {"key", "label", "equipment", "iconKey", "canonical"}
INGREDIENT_LINE_KEYS = {"ingredient", "quantity", "unit", "optional", "preparationNote"}
STEP_KEYS = {
    "stepNumber", "kind", "instruction", "detail", "durationSeconds", "equipment",
    "ingredientRefs", "caution", "spriteKey", "variantGroup", "variants",
}
VARIANT_KEYS = {"method", "equipment", "instruction", "durationSeconds", "spriteKey", "priority"}
CATALOG_KEYS = {"id", "name", "filipinoGloss", "category", "displayUnit", "defaultStatus", "spriteKey"}
EQUIPMENT_KEYS = {"id", "name", "description", "shipped", "pickerNote", "spriteKey"}

# Every key a shipped path can reach (docs/07 section 11.3); the manifest may grow.
REQUIRED_SPRITE_KEYS = (
    "step_prep_none", "step_heat_stovetop", "step_cook_stovetop", "step_wait_stovetop",
    "step_finish_none", "step_cook_air_fryer", "step_wait_air_fryer",
    "dish_chicken_adobo", "dish_sinangag", "dish_crispy_pork_belly",
    "variant_panfry", "variant_airfry",
    "ing_chicken_thighs", "ing_pork_belly", "ing_rice", "ing_garlic", "ing_soy_sauce",
    "ing_vinegar", "ing_bay_leaf", "ing_cooking_oil", "ing_salt", "ing_black_pepper",
    "ing_sugar", "ing_spring_onion", "ing_calamansi", "ing_eggs", "ing_banana_ketchup",
    "eq_stovetop", "eq_oven", "eq_air_fryer", "eq_grill", "eq_pressure_cooker",
)

SPRITE_TOKEN_RE = re.compile(r"^(bg|step|dish|variant|ing|eq|mascot|ui|sfx|font)_[a-z0-9_]+$")
DATE_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b")
SCHEDULE_KEYS = {"date", "dates", "due_date", "scheduled_at", "schedule", "milestone", "deadline", "freeze"}


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.errors = []
        self.checks = 0
        self.groups = {}

    def group(self, name):
        self.groups.setdefault(name, 0)

    def check(self, condition, where, message):
        self.checks += 1
        if not condition:
            self.errors.append(f"{where}: {message}")
        return bool(condition)

    def fail(self, where, message):
        self.checks += 1
        self.errors.append(f"{where}: {message}")
        return False


def load_json(path, report, where):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        report.fail(where, "file is missing")
    except json.JSONDecodeError as exc:
        report.fail(where, f"JSON does not parse: {exc}")
    return None


# ---------------------------------------------------------------------------
# docs/07 section 11.3 asset manifest and db/schema-sqlite.sql columns
# ---------------------------------------------------------------------------
def load_sprite_manifest(path, report):
    where = "docs/07-pixel-ui-spec.md section 11.3"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        report.fail(where, "file is missing")
        return set()
    match = re.search(r"^### 11\.3 [^\n]*\n(.*?)(?=^### |^## )", text, re.MULTILINE | re.DOTALL)
    if not report.check(match is not None, where, "asset manifest table not found"):
        return set()
    keys = {token for token in re.findall(r"`([^`]+)`", match.group(1)) if SPRITE_TOKEN_RE.match(token)}
    report.check(len(keys) >= 74, where, f"expected at least the 74-key manifest, parsed {len(keys)} keys")
    for key in REQUIRED_SPRITE_KEYS:
        report.check(key in keys, where, f"manifest is missing the shipped key {key!r}")
    return keys


def strip_sql_comment(line):
    out = []
    in_string = False
    index = 0
    while index < len(line):
        char = line[index]
        if char == "'":
            in_string = not in_string
            out.append(char)
        elif not in_string and char == "-" and line[index + 1:index + 2] == "-":
            break
        else:
            out.append(char)
        index += 1
    return "".join(out)


def load_ddl_columns(path, report):
    where = "db/schema-sqlite.sql"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        report.fail(where, "file is missing")
        return {}
    tables = {}
    current = None
    for raw in text.splitlines():
        line = strip_sql_comment(raw)
        opened = re.match(r"^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z_][a-z0-9_]*)\s*\(", line, re.I)
        if opened:
            current = opened.group(1)
            tables[current] = []
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped.startswith(")"):
            current = None
            continue
        if not stripped or stripped.startswith("("):
            continue
        first = stripped.split()[0]
        # The DDL writes keywords in upper case and column names in lower case.
        if re.match(r"^[a-z][a-z0-9_]*$", first):
            tables[current].append(first)
    return tables


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def sentence_count(text):
    return sum(text.count(mark) for mark in ".!?")


def walk_json(node, where, report, path="$"):
    """Check that no calendar date or scheduling field leaked into content."""
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(key, str) and key.lower() in SCHEDULE_KEYS:
                report.fail(where, f"{path}.{key}: scheduling fields are not content")
            walk_json(value, where, report, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk_json(value, where, report, f"{path}[{index}]")
    elif isinstance(node, str) and DATE_RE.search(node):
        report.fail(where, f"{path}: calendar date {node!r} in content")


# ---------------------------------------------------------------------------
# Availability (mirrors lib/domain/rules/availability: presence only, no amounts)
# ---------------------------------------------------------------------------
def evaluate_recipe(recipe, stock, owned, method_key=None):
    """Return (state, missing_codes, confirmation_codes) for one recipe."""
    missing = []
    confirm = []
    for line in recipe["ingredients"]:
        if line["optional"]:
            continue
        status = stock.get(line["ingredient"], "unknown")
        if status == "out":
            missing.append(f"ingredient:{line['ingredient']}")
        elif status == "unknown":
            confirm.append(f"ingredient:{line['ingredient']}")

    required = set(recipe["requiredEquipment"])
    for step in recipe["steps"]:
        if step["variants"]:
            continue  # the chosen method declares this appliance
        if step["equipment"]:
            required.add(step["equipment"])
    if recipe["methods"]:
        chosen = next((item for item in recipe["methods"] if item["key"] == method_key), None)
        if chosen is None:
            raise ValueError(f"method {method_key!r} is not declared by {recipe['slug']}")
        required.add(chosen["equipment"])

    for equipment_id in sorted(required):
        if equipment_id not in owned:
            missing.append(f"equipment:{equipment_id}")

    missing.sort()
    confirm.sort()
    if missing:
        return "blocked", missing, confirm, sorted(required)
    if confirm:
        return "needs_confirmation", missing, confirm, sorted(required)
    return "ready", missing, confirm, sorted(required)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
def check_catalog(ingredients, equipment, sprites, report):
    report.group("catalog")
    where = "assets/fixtures/ingredients.json"
    report.check(isinstance(ingredients, list), where, "ingredients must be a list")
    if not isinstance(ingredients, list):
        return {}, {}
    report.check(len(ingredients) == 15, where, f"expected exactly 15 ingredients, found {len(ingredients)}")

    by_id = {}
    names = []
    for index, row in enumerate(ingredients):
        here = f"{where}[{index}]"
        if not report.check(isinstance(row, dict), here, "ingredient row must be an object"):
            continue
        report.check(set(row) == CATALOG_KEYS, here, f"unexpected fields {sorted(set(row) ^ CATALOG_KEYS)}")
        ingredient_id = row.get("id")
        if not report.check(isinstance(ingredient_id, str) and ingredient_id, here, "id must be a non-empty string"):
            continue
        if not report.check(ingredient_id not in by_id, here, f"duplicate ingredient id {ingredient_id!r}"):
            continue
        by_id[ingredient_id] = row
        names.append(str(row.get("name", "")))
        report.check(row.get("category") in INGREDIENT_CATEGORIES, here,
                     f"category {row.get('category')!r} is not one of {INGREDIENT_CATEGORIES}")
        report.check(row.get("displayUnit") in UNIT_CODES, here,
                     f"displayUnit {row.get('displayUnit')!r} is not a known unit code")
        report.check(row.get("defaultStatus") == "unknown", here,
                     f"defaultStatus must be 'unknown' (docs/09 section 3.5), found {row.get('defaultStatus')!r}")
        report.check(row.get("spriteKey") == f"ing_{ingredient_id}", here,
                     "spriteKey must be ing_<id>")
        report.check(row.get("spriteKey") in sprites, here,
                     f"spriteKey {row.get('spriteKey')!r} is not in the docs/07 section 11.3 manifest")
        gloss = row.get("filipinoGloss")
        report.check(isinstance(gloss, str) and gloss.strip() != "", here, "filipinoGloss must be a non-empty string")
        if isinstance(gloss, str):
            report.check(gloss.strip().lower() != str(row.get("name", "")).strip().lower(), here,
                         "filipinoGloss must add a Filipino name, not repeat the English name")
            report.check(len(gloss) <= 40, here, "filipinoGloss must stay short (<= 40 characters)")
    report.check(len(set(names)) == len(names), where, "ingredient names must be unique")

    where = "assets/fixtures/equipment.json"
    report.check(isinstance(equipment, list), where, "equipment must be a list")
    by_code = {}
    if isinstance(equipment, list):
        report.check(len(equipment) == 5, where, f"expected exactly 5 appliances, found {len(equipment)}")
        for index, row in enumerate(equipment):
            here = f"{where}[{index}]"
            if not report.check(isinstance(row, dict), here, "equipment row must be an object"):
                continue
            report.check(set(row) == EQUIPMENT_KEYS, here, f"unexpected fields {sorted(set(row) ^ EQUIPMENT_KEYS)}")
            code = row.get("id")
            if not report.check(isinstance(code, str) and code, here, "id must be a non-empty string"):
                continue
            report.check(code not in by_code, here, f"duplicate equipment id {code!r}")
            by_code[code] = row
            report.check(isinstance(row.get("name"), str) and row["name"].strip(), here, "name must not be empty")
            report.check(isinstance(row.get("description"), str) and row["description"].strip(), here,
                         "description must not be empty")
            report.check(row.get("spriteKey") == f"eq_{code}", here, "spriteKey must be eq_<id>")
            report.check(row.get("spriteKey") in sprites, here, "spriteKey is not in the asset manifest")
            report.check(isinstance(row.get("shipped"), bool), here, "shipped must be a boolean")
            if row.get("shipped"):
                report.check(row.get("pickerNote") is None, here, "a shipped appliance carries no picker note")
            else:
                report.check(row.get("pickerNote") == UNUSED_NOTE, here,
                             f"an unused appliance must be flagged {UNUSED_NOTE!r}")

        shipped = sorted(code for code, row in by_code.items() if row.get("shipped"))
        unused = sorted(code for code, row in by_code.items() if not row.get("shipped"))
        report.check(shipped == sorted(SHIPPED_EQUIPMENT), where,
                     f"shipped appliances must be {sorted(SHIPPED_EQUIPMENT)}, found {shipped}")
        report.check(unused == sorted(UNUSED_EQUIPMENT), where,
                     f"unused appliances must be {sorted(UNUSED_EQUIPMENT)}, found {unused}")
    return by_id, by_code


def check_kitchen(kitchen_file, ingredients, equipment, report):
    report.group("kitchen")
    where = "assets/fixtures/kitchen_demo.json"
    if not report.check(isinstance(kitchen_file, dict), where, "kitchen fixture must be an object"):
        return None, {}, set()
    report.check(kitchen_file.get("seedVersion") == SEED_VERSION, where, f"seedVersion must be {SEED_VERSION}")
    profile = kitchen_file.get("kitchen")
    stock_rows = kitchen_file.get("stock")
    if not report.check(isinstance(profile, dict), where, "kitchen profile must be an object"):
        return None, {}, set()
    report.check(profile.get("name") == DEMO_KITCHEN_NAME, where,
                 f"demo kitchen name must be {DEMO_KITCHEN_NAME!r}")
    chosen = profile.get("equipment")
    report.check(isinstance(chosen, list) and len(set(chosen)) == len(chosen), where,
                 "equipment must be a list of unique appliance ids")
    chosen = chosen if isinstance(chosen, list) else []
    for code in chosen:
        report.check(code in equipment, where, f"unknown appliance {code!r}")
    report.check(sorted(chosen) == sorted(SHIPPED_EQUIPMENT), where,
                 f"demo kitchen must own {sorted(SHIPPED_EQUIPMENT)}, found {sorted(chosen)}")

    stock = {}
    if not report.check(isinstance(stock_rows, list), where, "stock must be a list"):
        return profile.get("name"), stock, set(chosen)
    for index, row in enumerate(stock_rows):
        here = f"{where}.stock[{index}]"
        if not report.check(isinstance(row, dict), here, "stock row must be an object"):
            continue
        report.check(set(row) == {"ingredient", "status"}, here, "stock rows carry ingredient and status only")
        ingredient_id = row.get("ingredient")
        report.check(ingredient_id in ingredients, here, f"unknown ingredient {ingredient_id!r}")
        report.check(row.get("status") in STOCK_STATUSES, here,
                     f"status {row.get('status')!r} is not one of {STOCK_STATUSES}")
        if ingredient_id in stock:
            report.fail(here, f"duplicate stock row for {ingredient_id!r}")
        stock[ingredient_id] = row.get("status")
    report.check(sorted(stock) == sorted(ingredients), where,
                 "every catalog ingredient needs exactly one demo stock row (docs/09 section 3.5)")
    report.check(set(stock.values()) == set(STOCK_STATUSES), where,
                 "the demo kitchen must exercise all four stock statuses")
    return profile.get("name"), stock, set(chosen)


def check_recipe(recipe, where, ingredients, equipment, sprites, report):
    report.group("recipes")
    if not report.check(isinstance(recipe, dict), where, "recipe must be an object"):
        return
    report.check(set(recipe) == RECIPE_KEYS, where, f"unexpected fields {sorted(set(recipe) ^ RECIPE_KEYS)}")
    slug = recipe.get("slug")
    locked = LOCKED_DISHES.get(slug)
    if not report.check(locked is not None, where, f"slug {slug!r} is not one of the three shipped dishes"):
        return
    report.check(recipe.get("id") == slug, where, "id must equal the slug")
    report.check(recipe.get("name") == locked["name"], where,
                 f"name must be the locked {locked['name']!r}, found {recipe.get('name')!r}")
    report.check(recipe.get("cuisine") == "Filipino", where, "cuisine must be 'Filipino'")
    report.check(recipe.get("baseServings") == locked["servings"], where,
                 f"baseServings must be {locked['servings']}")
    report.check(isinstance(recipe.get("prepMinutes"), int) and recipe["prepMinutes"] > 0, where,
                 "prepMinutes must be a positive integer")
    report.check(isinstance(recipe.get("cookMinutes"), int) and recipe["cookMinutes"] > 0, where,
                 "cookMinutes must be a positive integer")
    report.check(recipe.get("difficulty") in DIFFICULTIES, where,
                 f"difficulty {recipe.get('difficulty')!r} is not one of {DIFFICULTIES}")
    report.check(isinstance(recipe.get("sortOrder"), int) and recipe["sortOrder"] >= 1, where,
                 "sortOrder must be an integer >= 1")
    report.check(isinstance(recipe.get("description"), str) and recipe["description"].strip(), where,
                 "description must not be empty")
    report.check(recipe.get("dishStampKey") in sprites, where,
                 f"dishStampKey {recipe.get('dishStampKey')!r} is not in the asset manifest")

    required_equipment = recipe.get("requiredEquipment")
    report.check(isinstance(required_equipment, list), where, "requiredEquipment must be a list")
    for code in required_equipment or []:
        report.check(code in equipment, where, f"requiredEquipment names unknown appliance {code!r}")
        report.check(code in SHIPPED_EQUIPMENT, where, f"requiredEquipment names unshipped appliance {code!r}")

    methods = recipe.get("methods")
    report.check(isinstance(methods, list), where, "methods must be a list")
    methods = methods if isinstance(methods, list) else []
    method_by_key = {}
    if methods:
        report.check(len(methods) == 2, where, f"a method recipe declares exactly 2 methods, found {len(methods)}")
        for index, method in enumerate(methods):
            here = f"{where}.methods[{index}]"
            if not report.check(isinstance(method, dict), here, "method must be an object"):
                continue
            report.check(set(method) == METHOD_KEYS, here, f"unexpected fields {sorted(set(method) ^ METHOD_KEYS)}")
            key = method.get("key")
            if not report.check(isinstance(key, str) and key in EXPECTED_METHODS, here,
                                f"method key {key!r} is not one of {sorted(EXPECTED_METHODS)}"):
                continue
            expected = EXPECTED_METHODS[key]
            report.check(method.get("label") == expected["label"], here,
                         f"label must be {expected['label']!r}")
            report.check(method.get("equipment") == expected["equipment"], here,
                         f"equipment must be {expected['equipment']!r}")
            report.check(method.get("equipment") in SHIPPED_EQUIPMENT, here, "method appliance must be shipped")
            report.check(method.get("iconKey") in sprites, here, "iconKey is not in the asset manifest")
            report.check(isinstance(method.get("canonical"), bool), here, "canonical must be a boolean")
            report.check(not any("ingredient" in str(field).lower() for field in method), here,
                         "a method must not scope ingredient lines (docs/06 C5, F-03)")
            method_by_key[key] = method
        report.check(set(method_by_key) == set(EXPECTED_METHODS), where,
                     f"methods must be {sorted(EXPECTED_METHODS)}, found {sorted(method_by_key)}")
        canonical = [key for key, method in method_by_key.items() if method.get("canonical")]
        report.check(len(canonical) == 1, where, "exactly one method is the canonical path")
        if required_equipment:
            report.fail(where, "a method recipe keeps requiredEquipment empty: the method declares its appliance")
    else:
        report.check(isinstance(locked["equipment"], list) and locked["equipment"], where,
                     "only the method dish may omit requiredEquipment")
        report.check(sorted(required_equipment or []) == sorted(locked["equipment"]), where,
                     f"requiredEquipment must be {locked['equipment']}, found {required_equipment}")

    # --- ingredient lines ------------------------------------------------
    lines = recipe.get("ingredients")
    report.check(isinstance(lines, list) and lines, where, "ingredients must be a non-empty list")
    lines = lines if isinstance(lines, list) else []
    line_by_id = {}
    for index, line in enumerate(lines):
        here = f"{where}.ingredients[{index}]"
        if not report.check(isinstance(line, dict), here, "ingredient line must be an object"):
            continue
        report.check(set(line) == INGREDIENT_LINE_KEYS, here,
                     f"unexpected fields {sorted(set(line) ^ INGREDIENT_LINE_KEYS)}")
        ingredient_id = line.get("ingredient")
        report.check(ingredient_id in ingredients, here, f"unknown ingredient {ingredient_id!r}")
        if ingredient_id in line_by_id:
            report.fail(here, f"duplicate ingredient line for {ingredient_id!r}")
        line_by_id[ingredient_id] = line
        report.check(isinstance(line.get("quantity"), (int, float)) and line["quantity"] > 0, here,
                     "quantity must be a positive number")
        report.check(line.get("unit") in UNIT_CODES, here, f"unit {line.get('unit')!r} is not a known unit code")
        catalog_row = ingredients.get(ingredient_id or "", {})
        report.check(line.get("unit") == catalog_row.get("displayUnit"), here,
                     f"unit must match the ingredient display unit {catalog_row.get('displayUnit')!r}")
        report.check(isinstance(line.get("optional"), bool), here, "optional must be a boolean")
        note = line.get("preparationNote")
        report.check(note is None or (isinstance(note, str) and len(note) <= 120), here,
                     "preparationNote must be null or <= 120 characters")
    report.check(any(not line.get("optional") for line in lines if isinstance(line, dict)), where,
                 "every recipe needs at least one required ingredient")
    for ingredient_id in sorted(line_by_id):
        report.check(ingredient_id in ingredients, where, f"ingredient {ingredient_id!r} is not in the catalog")

    # --- steps -----------------------------------------------------------
    steps = recipe.get("steps")
    report.check(isinstance(steps, list) and steps, where, "steps must be a non-empty list")
    steps = steps if isinstance(steps, list) else []
    report.check(1 <= len(steps) <= 20, where, f"1..20 steps are allowed, found {len(steps)}")
    numbers = [step.get("stepNumber") for step in steps if isinstance(step, dict)]
    report.check(numbers == list(range(1, len(steps) + 1)), where,
                 f"step numbers must be contiguous 1..{len(steps)}, found {numbers}")
    if locked["steps"] is not None:
        report.check(len(steps) == locked["steps"], where,
                     f"{locked['name']} must have exactly {locked['steps']} steps, found {len(steps)}")
    else:
        report.check(5 <= len(steps) <= 7, where, f"the method dish keeps 5..7 canonical steps, found {len(steps)}")

    finishes = 0
    variant_steps = []
    for step in steps:
        if not isinstance(step, dict):
            continue
        number = step.get("stepNumber")
        here = f"{where}.steps[{number}]"
        report.check(set(step) == STEP_KEYS, here, f"unexpected fields {sorted(set(step) ^ STEP_KEYS)}")
        kind = step.get("kind")
        report.check(kind in STEP_KINDS, here, f"kind {kind!r} is not one of {STEP_KINDS}")
        instruction = step.get("instruction")
        if report.check(isinstance(instruction, str) and instruction.strip(), here,
                        "instruction must not be empty"):
            report.check(len(instruction) <= 180, here, f"instruction is {len(instruction)} characters (max 180)")
            report.check(sentence_count(instruction) <= 2, here,
                         "instruction must be at most 2 sentences")
        detail = step.get("detail")
        report.check(detail is None or (isinstance(detail, str) and 0 < len(detail) <= 120), here,
                     "detail must be null or 1..120 characters")
        caution = step.get("caution")
        report.check(caution is None or (isinstance(caution, str) and 0 < len(caution) <= 90), here,
                     "caution must be null or 1..90 characters")
        duration = step.get("durationSeconds")
        if kind in ("prep", "finish"):
            report.check(duration is None, here, f"a {kind} step carries no timer")
        elif kind == "wait":
            report.check(isinstance(duration, int) and duration > 0, here, "a wait step requires a duration > 0")
        elif kind in ("heat", "cook"):
            report.check(duration is None or (isinstance(duration, int) and duration > 0), here,
                         "a heat/cook duration must be null or > 0")
        if isinstance(duration, int):
            report.check(duration > 0, here, "a duration is never zero or negative (docs/09 L3)")
        appliance = step.get("equipment")
        if kind in ("prep", "finish"):
            report.check(appliance is None, here, f"a {kind} step is equipment-neutral")
        elif kind in ("heat", "cook"):
            report.check(appliance in equipment, here, f"a {kind} step needs a known appliance")
        else:
            report.check(appliance is None or appliance in equipment, here,
                         "a wait step may name a known appliance or be neutral")
        refs = step.get("ingredientRefs")
        report.check(isinstance(refs, list), here, "ingredientRefs must be a list")
        for ref in refs or []:
            report.check(ref in ingredients, here, f"ingredientRefs names unknown ingredient {ref!r}")
            report.check(ref in line_by_id, here, f"ingredientRefs names {ref!r}, which is not on the recipe")
        report.check(len(set(refs or [])) == len(refs or []), here, "ingredientRefs must not repeat an id")
        report.check(step.get("spriteKey") in sprites, here,
                     f"spriteKey {step.get('spriteKey')!r} is not in the asset manifest")
        variant_group = step.get("variantGroup")
        report.check(variant_group is None or (isinstance(variant_group, str) and 0 < len(variant_group) <= 40),
                     here, "variantGroup must be null or 1..40 characters")
        if kind == "finish":
            finishes += 1
            report.check(number == len(steps), here, "the finish step is the last step")
        variants = step.get("variants")
        report.check(isinstance(variants, list), here, "variants must be a list")
        variants = variants if isinstance(variants, list) else []
        if variants:
            variant_steps.append(step)
            report.check(bool(methods), here, "a step variant needs the recipe to declare methods")
            report.check(variant_group is not None, here, "a method-dependent step declares a variantGroup")
            per_method = {}
            for index, variant in enumerate(variants):
                vwhere = f"{here}.variants[{index}]"
                if not report.check(isinstance(variant, dict), vwhere, "variant must be an object"):
                    continue
                report.check(set(variant) == VARIANT_KEYS, vwhere,
                             f"unexpected fields {sorted(set(variant) ^ VARIANT_KEYS)}")
                method_key = variant.get("method")
                report.check(method_key in method_by_key, vwhere,
                             f"variant method {method_key!r} is not declared by the recipe")
                if method_key in per_method:
                    report.fail(vwhere, f"duplicate variant for method {method_key!r}")
                per_method[method_key] = variant
                report.check(variant.get("equipment") == method_by_key.get(method_key, {}).get("equipment"), vwhere,
                             "a variant uses the appliance its method declares")
                report.check(variant.get("equipment") != appliance, vwhere,
                             "a variant's appliance differs from its canonical step's appliance (docs/09 L11)")
                priority = variant.get("priority")
                report.check(isinstance(priority, int) and priority >= 1, vwhere, "priority must be >= 1")
                override = variant.get("instruction")
                report.check(override is None or (isinstance(override, str) and 0 < len(override) <= 180), vwhere,
                             "instruction override must be null or 1..180 characters")
                if isinstance(override, str):
                    report.check(sentence_count(override) <= 2, vwhere,
                                 "instruction override must be at most 2 sentences")
                override_duration = variant.get("durationSeconds")
                report.check(override_duration is None or (isinstance(override_duration, int)
                                                           and override_duration > 0), vwhere,
                             "durationSeconds override must be null or > 0")
                report.check(variant.get("spriteKey") in sprites, vwhere,
                             "spriteKey override is not in the asset manifest")
                report.check(any(variant.get(field) is not None
                                 for field in ("instruction", "durationSeconds", "spriteKey")), vwhere,
                             "a variant overrides at least one field (db schema CHECK)")
                report.check(not any("ingredient" in str(field).lower() for field in variant), vwhere,
                             "a variant must not change ingredientRefs (docs/09 section 4.1)")
                if override_duration is not None:
                    report.check(kind in ("heat", "cook", "wait"), vwhere,
                                 "only a timed kind may carry a duration override")
        else:
            report.check(variant_group is None, here, "a step without variants declares no variantGroup")
    report.check(finishes == 1, where, f"exactly one finish step is required, found {finishes}")

    # --- method resolution ----------------------------------------------
    if methods:
        canonical_keys = [key for key, method in method_by_key.items() if method.get("canonical")]
        non_canonical = [key for key in method_by_key if key not in canonical_keys]
        for step in variant_steps:
            here = f"{where}.steps[{step['stepNumber']}]"
            if canonical_keys:
                canonical_equipment = method_by_key[canonical_keys[0]].get("equipment")
                report.check(step.get("equipment") == canonical_equipment, here,
                             "the canonical method's appliance implements this step")
            for key in non_canonical:
                report.check(any(variant.get("method") == key for variant in step["variants"]), here,
                             f"method {key!r} needs an override on this step")
        for key, method in method_by_key.items():
            report.check(resolve_method(recipe, key) is not None, where,
                         f"method {key!r} does not resolve on every step")
    return


def resolve_method(recipe, method_key):
    """Return the resolved implementation list for one method, or None when it cannot resolve."""
    method = next((item for item in recipe.get("methods") or [] if item["key"] == method_key), None)
    if method is None:
        return None
    resolved = []
    for step in recipe.get("steps") or []:
        variants = step.get("variants") or []
        if not variants:
            resolved.append({"stepNumber": step["stepNumber"], "equipment": step.get("equipment"),
                             "instruction": step.get("instruction"),
                             "durationSeconds": step.get("durationSeconds"),
                             "spriteKey": step.get("spriteKey"), "isVariant": False})
            continue
        override = next((variant for variant in variants if variant.get("method") == method_key), None)
        if override is None:
            if not method.get("canonical") or step.get("equipment") != method.get("equipment"):
                return None
            resolved.append({"stepNumber": step["stepNumber"], "equipment": step.get("equipment"),
                             "instruction": step.get("instruction"),
                             "durationSeconds": step.get("durationSeconds"),
                             "spriteKey": step.get("spriteKey"), "isVariant": False})
            continue
        resolved.append({
            "stepNumber": step["stepNumber"],
            "equipment": override.get("equipment") if override.get("equipment") is not None else step.get("equipment"),
            "instruction": override.get("instruction") if override.get("instruction") is not None
            else step.get("instruction"),
            "durationSeconds": override.get("durationSeconds") if override.get("durationSeconds") is not None
            else step.get("durationSeconds"),
            "spriteKey": override.get("spriteKey") if override.get("spriteKey") is not None
            else step.get("spriteKey"),
            "isVariant": True,
        })
    return resolved


def check_recipes(recipes, ingredients, equipment, sprites, report):
    report.check(len(recipes) == 3, "assets/fixtures/recipes/", f"expected exactly 3 recipes, found {len(recipes)}")
    slugs = []
    sort_orders = []
    for recipe in recipes:
        slug = (recipe or {}).get("slug", "<unknown>")
        slugs.append(slug)
        sort_orders.append((recipe or {}).get("sortOrder"))
        check_recipe(recipe, f"assets/fixtures/recipes/{slug}.json", ingredients, equipment, sprites, report)
    report.check(sorted(slugs) == sorted(LOCKED_DISHES), "assets/fixtures/recipes/",
                 f"recipes must be exactly {sorted(LOCKED_DISHES)}, found {sorted(slugs)}")
    report.check(len(set(slugs)) == len(slugs), "assets/fixtures/recipes/", "recipe slugs must be unique")
    report.check(sorted(sort_orders) == list(range(1, len(recipes) + 1)), "assets/fixtures/recipes/",
                 f"sortOrder must be exactly 1..{len(recipes)}, found {sort_orders}")

    adobo = next((recipe for recipe in recipes if recipe is not None and recipe.get("slug") == "chicken-adobo"), None)
    if adobo is not None:
        timed = [step["stepNumber"] for step in adobo["steps"]
                 if step["kind"] in ("heat", "cook", "wait") and step["durationSeconds"]]
        report.check(len(timed) == 3, "assets/fixtures/recipes/chicken-adobo.json",
                     f"the worked Adobo has three timed steps (docs/04 section 5), found {len(timed)}")
        report.check(adobo["cookMinutes"] == 35, "assets/fixtures/recipes/chicken-adobo.json",
                     "cookMinutes must be 35 (docs/04 section 5)")

    pork = next((recipe for recipe in recipes
                 if recipe is not None and recipe.get("slug") == "crispy-pork-belly"), None)
    if pork is not None:
        where = "assets/fixtures/recipes/crispy-pork-belly.json"
        report.check(len(pork.get("methods") or []) == 2, where, "exactly 2 methods")
        report.check(len(pork.get("requiredEquipment") or []) == 0, where,
                     "requiredEquipment stays empty: the method declares its appliance")
        variant_steps = [step for step in pork["steps"] if step["variants"]]
        report.check(bool(variant_steps), where, "at least one step changes with the method")
        for step in variant_steps:
            report.check(step.get("variantGroup") == "cook_method", where,
                         "method-dependent steps share the cook_method group (docs/09 section 4.3)")
        # Ingredients are identical across methods: one static list, one is_optional each.
        report.check(all(isinstance(line.get("optional"), bool) for line in pork["ingredients"]), where,
                     "every pork belly ingredient carries one static optional flag")
        optional_oil = any(line["ingredient"] == "cooking_oil" and line["optional"]
                           for line in pork["ingredients"])
        required_oil = any(line["ingredient"] == "cooking_oil" and not line["optional"]
                           for line in pork["ingredients"])
        report.check(optional_oil and not required_oil, where,
                     "cooking oil is statically optional for both methods (docs/06 C5 / F-03)")
        for key in ("pan_fry", "air_fry"):
            resolved = resolve_method(pork, key)
            report.check(resolved is not None, where, f"method {key!r} resolves on every step")
            if resolved:
                difference = [(impl["stepNumber"], impl["instruction"], impl["durationSeconds"], impl["spriteKey"])
                              for impl in resolved]
                report.check(len({entry[0] for entry in difference}) == len(pork["steps"]), where,
                             f"method {key!r} covers every step")


def check_seed(seed, fixtures, sprites, ddl_columns, report):
    report.group("seed")
    for name in SEED_COLUMNS:
        if not report.check(name in seed, "assets/seed/", f"{name} is missing"):
            return
    for name, expected in SEED_COLUMNS.items():
        table = SEED_TABLES[name]
        where = f"assets/seed/{name}"
        rows = seed[name]
        if not report.check(isinstance(rows, list), where, "must be a JSON array of rows"):
            continue
        report.check(table in ddl_columns, "db/schema-sqlite.sql", f"table {table} is not in the DDL")
        for index, row in enumerate(rows):
            here = f"{where}[{index}]"
            if not report.check(isinstance(row, dict), here, "row must be an object"):
                continue
            report.check(set(row) == expected, here,
                         f"columns must be exactly {sorted(expected)}, found {sorted(row)}")
            unknown = set(row) - set(ddl_columns.get(table, []))
            report.check(not unknown, here,
                         f"invented columns not in db/schema-sqlite.sql {table}: {sorted(unknown)}")

    units = seed["units.json"]
    unit_by_code, unit_by_id = {}, {}
    for row in units:
        unit_by_code[row["code"].lower()] = row
        unit_by_id[row["id"]] = row
        report.check(row["dimension"] in UNIT_DIMENSIONS, "assets/seed/units.json",
                     f"dimension {row['dimension']!r} is not one of {UNIT_DIMENSIONS}")
        report.check(len(row["code"]) <= 10 and 0 < len(row["name"]) <= 30, "assets/seed/units.json",
                     "code/name lengths are outside the DDL CHECKs")
    report.check(sorted(row["code"] for row in units) == sorted(UNIT_CODES), "assets/seed/units.json",
                 f"units must seed the 9 catalog units {sorted(UNIT_CODES)}")
    report.check(len(unit_by_code) == len(units) == len(unit_by_id), "assets/seed/units.json",
                 "unit ids and codes must be unique")

    ingredients = seed["ingredients.json"]
    ingredient_by_code, ingredient_by_id = {}, {}
    for row in ingredients:
        ingredient_by_code[row["code"]] = row
        ingredient_by_id[row["id"]] = row
        report.check(row["category"] in INGREDIENT_CATEGORIES, "assets/seed/ingredients.json",
                     f"category {row['category']!r} is not one of {INGREDIENT_CATEGORIES}")
        report.check(0 < len(row["code"]) <= 60 and 0 < len(row["name"]) <= 100, "assets/seed/ingredients.json",
                     "code/name lengths are outside the DDL CHECKs")
    report.check(len(ingredients) == 15, "assets/seed/ingredients.json",
                 f"15 ingredient rows are required, found {len(ingredients)}")
    report.check(len(ingredient_by_code) == len(ingredients) == len(ingredient_by_id),
                 "assets/seed/ingredients.json", "ingredient ids and codes must be unique")
    report.check(len({row["name"].lower() for row in ingredients}) == len(ingredients),
                 "assets/seed/ingredients.json", "ingredient names must be unique (COLLATE NOCASE)")

    equipment = seed["equipment.json"]
    equipment_by_code, equipment_by_id = {}, {}
    for row in equipment:
        equipment_by_code[row["code"]] = row
        equipment_by_id[row["id"]] = row
        report.check(0 < len(row["code"]) <= 30 and 0 < len(row["name"]) <= 60, "assets/seed/equipment.json",
                     "code/name lengths are outside the DDL CHECKs")
    report.check(len(equipment) == 5, "assets/seed/equipment.json",
                 f"5 appliances are required, found {len(equipment)}")
    report.check(len(equipment_by_code) == len(equipment) == len(equipment_by_id),
                 "assets/seed/equipment.json", "equipment ids and codes must be unique")

    kitchens = seed["kitchens.json"]
    report.check(len(kitchens) == 1, "assets/seed/kitchens.json", "exactly one kitchen row")
    if kitchens:
        kitchen = kitchens[0]
        report.check(kitchen["id"] == 1, "assets/seed/kitchens.json", "kitchens.id must be 1")
        report.check(16 <= len(kitchen["kitchen_uid"]) <= 64, "assets/seed/kitchens.json",
                     "kitchen_uid must be 16..64 characters")
        report.check(0 < len(kitchen["name"].strip()) <= 100, "assets/seed/kitchens.json",
                     "kitchen name must be 1..100 characters")

    kitchen_equipment = seed["kitchen_equipment.json"]
    expected_owned = None
    if fixtures.get("kitchen"):
        expected_owned = sorted(fixtures["kitchen"]["kitchen"]["equipment"])
    owned = []
    for row in kitchen_equipment:
        report.check(row["kitchen_id"] == 1, "assets/seed/kitchen_equipment.json", "kitchen_id must be 1")
        report.check(row["equipment_id"] in equipment_by_id, "assets/seed/kitchen_equipment.json",
                     f"unknown equipment_id {row['equipment_id']}")
        if row["equipment_id"] in equipment_by_id:
            owned.append(equipment_by_id[row["equipment_id"]]["code"])
    report.check(len(set(owned)) == len(owned), "assets/seed/kitchen_equipment.json",
                 "duplicate kitchen_equipment row")
    if expected_owned is not None:
        report.check(sorted(owned) == expected_owned, "assets/seed/kitchen_equipment.json",
                     f"seed ownership {sorted(owned)} must equal the demo kitchen {expected_owned}")

    stock = seed["stock_status.json"]
    seen_stock = set()
    for row in stock:
        report.check(row["kitchen_id"] == 1, "assets/seed/stock_status.json", "kitchen_id must be 1")
        report.check(row["ingredient_id"] in ingredient_by_id, "assets/seed/stock_status.json",
                     f"unknown ingredient_id {row['ingredient_id']}")
        report.check(row["status"] in STOCK_STATUSES, "assets/seed/stock_status.json",
                     f"status {row['status']!r} is not one of {STOCK_STATUSES}")
        key = (row["kitchen_id"], row["ingredient_id"])
        report.check(key not in seen_stock, "assets/seed/stock_status.json", "duplicate stock_status row")
        seen_stock.add(key)
    report.check(len(stock) == 15, "assets/seed/stock_status.json",
                 f"one stock row per catalog ingredient (15), found {len(stock)}")
    report.check({row["ingredient_id"] for row in stock} == set(ingredient_by_id),
                 "assets/seed/stock_status.json", "stock rows must cover every catalog ingredient")

    recipes = seed["recipes.json"]
    recipe_by_slug, recipe_by_id = {}, {}
    for row in recipes:
        recipe_by_slug[row["slug"]] = row
        recipe_by_id[row["id"]] = row
        report.check(row["servings"] > 0, "assets/seed/recipes.json", "servings must be > 0")
        report.check(row["prep_minutes"] is None or row["prep_minutes"] > 0, "assets/seed/recipes.json",
                     "prep_minutes must be null or > 0")
        report.check(row["cook_minutes"] is None or row["cook_minutes"] > 0, "assets/seed/recipes.json",
                     "cook_minutes must be null or > 0")
        report.check(row["difficulty"] in DIFFICULTIES, "assets/seed/recipes.json",
                     f"difficulty {row['difficulty']!r} is not one of {DIFFICULTIES}")
        report.check(0 < len(row["name"]) <= 150 and 0 < len(row["slug"]) <= 160, "assets/seed/recipes.json",
                     "name/slug lengths are outside the DDL CHECKs")
    report.check(len(recipes) == 3, "assets/seed/recipes.json", f"3 recipes are required, found {len(recipes)}")
    report.check(len(recipe_by_slug) == len(recipes) == len(recipe_by_id), "assets/seed/recipes.json",
                 "recipe ids and slugs must be unique")
    report.check(sorted(recipe_by_slug) == sorted(LOCKED_DISHES), "assets/seed/recipes.json",
                 f"seed recipes must be {sorted(LOCKED_DISHES)}, found {sorted(recipe_by_slug)}")

    recipe_equipment = seed["recipe_equipment.json"]
    seen_link = set()
    for row in recipe_equipment:
        report.check(row["recipe_id"] in recipe_by_id, "assets/seed/recipe_equipment.json",
                     f"unknown recipe_id {row['recipe_id']}")
        report.check(row["equipment_id"] in equipment_by_id, "assets/seed/recipe_equipment.json",
                     f"unknown equipment_id {row['equipment_id']}")
        key = (row["recipe_id"], row["equipment_id"])
        report.check(key not in seen_link, "assets/seed/recipe_equipment.json", "duplicate recipe_equipment row")
        seen_link.add(key)

    recipe_ingredients = seed["recipe_ingredients.json"]
    seen_line, per_recipe_ingredients = set(), {}
    for row in recipe_ingredients:
        where = "assets/seed/recipe_ingredients.json"
        report.check(row["recipe_id"] in recipe_by_id, where, f"unknown recipe_id {row['recipe_id']}")
        report.check(row["ingredient_id"] in ingredient_by_id, where,
                     f"unknown ingredient_id {row['ingredient_id']}")
        report.check(isinstance(row["quantity"], (int, float)) and row["quantity"] > 0, where,
                     f"quantity must be > 0 for ingredient_id {row['ingredient_id']}")
        report.check(row["unit_id"] in unit_by_id, where, f"unknown unit_id {row['unit_id']}")
        report.check(row["is_optional"] in (0, 1), where, "is_optional must be 0 or 1")
        report.check(row["preparation_note"] is None or len(row["preparation_note"]) <= 120, where,
                     "preparation_note must be null or <= 120 characters")
        key = (row["recipe_id"], row["ingredient_id"])
        report.check(key not in seen_line, where, "duplicate (recipe_id, ingredient_id) row")
        seen_line.add(key)
        per_recipe_ingredients.setdefault(row["recipe_id"], set()).add(row["ingredient_id"])

    steps = seed["recipe_steps.json"]
    step_by_id = {}
    steps_by_recipe = {}
    for row in steps:
        where = "assets/seed/recipe_steps.json"
        report.check(row["id"] not in step_by_id, where, f"duplicate step id {row['id']}")
        step_by_id[row["id"]] = row
        recipe = recipe_by_id.get(row["recipe_id"])
        report.check(recipe is not None, where, f"unknown recipe_id {row['recipe_id']}")
        report.check(row["kind"] in STEP_KINDS, where, f"kind {row['kind']!r} is not one of {STEP_KINDS}")
        report.check(isinstance(row["instruction"], str) and row["instruction"].strip(), where,
                     "instruction must not be empty")
        report.check(len(row["instruction"]) <= 180, where, "instruction must be <= 180 characters")
        report.check(row["detail"] is None or len(row["detail"]) <= 120, where,
                     "detail must be null or <= 120 characters")
        report.check(row["caution"] is None or len(row["caution"]) <= 90, where,
                     "caution must be null or <= 90 characters")
        duration = row["duration_seconds"]
        if row["kind"] == "wait":
            report.check(isinstance(duration, int) and duration > 0, where, "a wait step requires a duration")
        elif row["kind"] in ("prep", "finish"):
            report.check(duration is None, where, f"a {row['kind']} step carries no duration")
        else:
            report.check(duration is None or (isinstance(duration, int) and duration > 0), where,
                         "duration must be null or > 0")
        if row["kind"] in ("prep", "finish"):
            report.check(row["equipment_id"] is None, where, f"a {row['kind']} step has no equipment")
        elif row["kind"] in ("heat", "cook"):
            report.check(row["equipment_id"] in equipment_by_id, where,
                         f"a {row['kind']} step needs a known equipment_id")
        else:
            report.check(row["equipment_id"] is None or row["equipment_id"] in equipment_by_id, where,
                         "wait equipment_id must be null or known")
        try:
            refs = json.loads(row["ingredient_refs_json"])
        except (TypeError, json.JSONDecodeError):
            refs = None
        if report.check(isinstance(refs, list) and all(isinstance(ref, str) for ref in refs), where,
                        "ingredient_refs_json must be a JSON array of ingredient codes"):
            for ref in refs:
                report.check(ref in ingredient_by_code, where, f"ingredient_refs_json names unknown code {ref!r}")
                if recipe is not None and per_recipe_ingredients.get(recipe["id"]):
                    report.check(ingredient_by_code.get(ref, {}).get("id") in per_recipe_ingredients[recipe["id"]],
                                 where, f"ingredient_refs_json names {ref!r}, which is not on the recipe")
        report.check(row["sprite_key"] in sprites, where,
                     f"sprite_key {row['sprite_key']!r} is not in the asset manifest")
        report.check(0 < len(row["sprite_key"]) <= 80, where, "sprite_key must be 1..80 characters")
        report.check(row["variant_group"] is None or 0 < len(row["variant_group"]) <= 40, where,
                     "variant_group must be null or 1..40 characters")
        steps_by_recipe.setdefault(row["recipe_id"], []).append(row)

    for recipe_id, recipe in recipe_by_id.items():
        rows = sorted(steps_by_recipe.get(recipe_id, []), key=lambda item: item["step_number"])
        numbers = [row["step_number"] for row in rows]
        report.check(numbers == list(range(1, len(rows) + 1)), "assets/seed/recipe_steps.json",
                     f"{recipe['slug']}: step numbers must be contiguous 1..{len(rows)}, found {numbers}")
        report.check(len(rows) > 0, "assets/seed/recipe_steps.json", f"{recipe['slug']}: needs steps")
        finishes = [row for row in rows if row["kind"] == "finish"]
        report.check(len(finishes) == 1, "assets/seed/recipe_steps.json",
                     f"{recipe['slug']}: exactly one finish step")
        if finishes:
            report.check(finishes[0]["step_number"] == len(rows), "assets/seed/recipe_steps.json",
                         f"{recipe['slug']}: the finish step is last")

    variants = seed["recipe_step_variants.json"]
    seen_variant = set()
    for row in variants:
        where = "assets/seed/recipe_step_variants.json"
        step = step_by_id.get(row["step_id"])
        report.check(step is not None, where, f"unknown step_id {row['step_id']}")
        report.check(row["equipment_id"] in equipment_by_id, where,
                     f"unknown equipment_id {row['equipment_id']}")
        report.check(isinstance(row["priority"], int) and row["priority"] >= 1, where, "priority must be >= 1")
        report.check(row["instruction_override"] is None
                     or (isinstance(row["instruction_override"], str) and row["instruction_override"].strip()),
                     where, "instruction_override must be null or non-empty")
        report.check(row["duration_override"] is None
                     or (isinstance(row["duration_override"], int) and row["duration_override"] > 0),
                     where, "duration_override must be null or > 0")
        report.check(row["sprite_override"] is None or row["sprite_override"] in sprites, where,
                     "sprite_override is not in the asset manifest")
        report.check(any(row[field] is not None
                         for field in ("instruction_override", "duration_override", "sprite_override")), where,
                     "a variant overrides at least one field")
        if step is not None:
            report.check(row["equipment_id"] != step["equipment_id"], where,
                         "a variant's equipment differs from its step's equipment (docs/09 L11)")
            report.check(step["variant_group"] is not None, where,
                         "a variant belongs to a step with a variant_group")
        key = (row["step_id"], row["equipment_id"])
        report.check(key not in seen_variant, where, "duplicate (step_id, equipment_id) variant")
        seen_variant.add(key)


def check_parity(fixtures, seed, report):
    report.group("parity")
    where = "fixtures vs seed"
    if not seed.get("recipes.json") or not fixtures.get("recipes"):
        report.fail(where, "cannot compare: content did not load")
        return
    recipe_by_slug = {row["slug"]: row for row in seed["recipes.json"]}
    ingredient_by_id = {row["id"]: row for row in seed["ingredients.json"]}
    equipment_by_id = {row["id"]: row for row in seed["equipment.json"]}
    unit_by_id = {row["id"]: row for row in seed["units.json"]}
    steps = seed["recipe_steps.json"]
    variants = seed["recipe_step_variants.json"]
    lines = seed["recipe_ingredients.json"]
    links = seed["recipe_equipment.json"]

    for recipe in fixtures["recipes"]:
        slug = recipe["slug"]
        here = f"assets/fixtures/recipes/{slug}.json vs assets/seed/"
        row = recipe_by_slug.get(slug)
        if not report.check(row is not None, here, "recipe is missing from the seed"):
            continue
        report.check(row["name"] == recipe["name"], here, "name differs between fixtures and seed")
        report.check(row["description"] == recipe["description"], here, "description differs")
        report.check(row["cuisine"] == recipe["cuisine"], here, "cuisine differs")
        report.check(row["servings"] == recipe["baseServings"], here, "servings differs from baseServings")
        report.check(row["prep_minutes"] == recipe["prepMinutes"], here, "prep_minutes differs from prepMinutes")
        report.check(row["cook_minutes"] == recipe["cookMinutes"], here, "cook_minutes differs from cookMinutes")
        report.check(row["difficulty"] == recipe["difficulty"], here, "difficulty differs")

        seed_equipment = sorted(equipment_by_id[link["equipment_id"]]["code"]
                                for link in links if link["recipe_id"] == row["id"])
        report.check(seed_equipment == sorted(recipe["requiredEquipment"]), here,
                     f"recipe_equipment {seed_equipment} != requiredEquipment {sorted(recipe['requiredEquipment'])}")

        fixture_lines = {line["ingredient"]: (line["quantity"], line["unit"], line["optional"],
                                             line["preparationNote"]) for line in recipe["ingredients"]}
        seed_lines = {}
        for line in lines:
            if line["recipe_id"] != row["id"]:
                continue
            code = ingredient_by_id[line["ingredient_id"]]["code"]
            seed_lines[code] = (line["quantity"], unit_by_id[line["unit_id"]]["code"],
                                bool(line["is_optional"]), line["preparation_note"])
        report.check(seed_lines == fixture_lines, here,
                     "display ingredient lines differ between fixtures and seed")

        seed_steps = sorted((step for step in steps if step["recipe_id"] == row["id"]),
                            key=lambda item: item["step_number"])
        report.check(len(seed_steps) == len(recipe["steps"]), here,
                     f"step count {len(seed_steps)} != {len(recipe['steps'])}")
        for step in recipe["steps"]:
            match = next((item for item in seed_steps if item["step_number"] == step["stepNumber"]), None)
            if not report.check(match is not None, here, f"step {step['stepNumber']} is missing from the seed"):
                continue
            expected = (
                step["kind"], step["instruction"], step["detail"], step["durationSeconds"],
                step["equipment"], json.dumps(step["ingredientRefs"], separators=(",", ":")),
                step["caution"], step["spriteKey"], step["variantGroup"],
            )
            observed = (
                match["kind"], match["instruction"], match["detail"], match["duration_seconds"],
                equipment_by_id[match["equipment_id"]]["code"] if match["equipment_id"] is not None else None,
                match["ingredient_refs_json"], match["caution"], match["sprite_key"], match["variant_group"],
            )
            report.check(expected == observed, here, f"step {step['stepNumber']} differs: {expected} != {observed}")

        fixture_variants = []
        for step in recipe["steps"]:
            for variant in step["variants"]:
                fixture_variants.append((step["stepNumber"], variant["equipment"], variant["instruction"],
                                         variant["durationSeconds"], variant["spriteKey"], variant["priority"]))
        seed_variants = []
        for step in seed_steps:
            for variant in variants:
                if variant["step_id"] != step["id"]:
                    continue
                seed_variants.append((step["step_number"], equipment_by_id[variant["equipment_id"]]["code"],
                                      variant["instruction_override"], variant["duration_override"],
                                      variant["sprite_override"], variant["priority"]))
        report.check(sorted(seed_variants, key=repr) == sorted(fixture_variants, key=repr), here,
                     "step variants differ between fixtures and seed")

    # identity, category and display-unit parity for the catalogs
    ingredient_by_code = {row["code"]: row for row in seed["ingredients.json"]}
    for item in fixtures["ingredients"]["ingredients"]:
        row = ingredient_by_code.get(item["id"])
        if not report.check(row is not None, "assets/fixtures/ingredients.json vs assets/seed/",
                            f"{item['id']} is missing from the seed"):
            continue
        report.check(row["name"] == item["name"], "fixtures vs seed", f"{item['id']}: name differs")
        report.check(row["category"] == item["category"], "fixtures vs seed", f"{item['id']}: category differs")
    equipment_by_code = {row["code"]: row for row in seed["equipment.json"]}
    for item in fixtures["equipment"]["equipment"]:
        row = equipment_by_code.get(item["id"])
        if not report.check(row is not None, "assets/fixtures/equipment.json vs assets/seed/",
                            f"{item['id']} is missing from the seed"):
            continue
        report.check(row["name"] == item["name"], "fixtures vs seed", f"{item['id']}: name differs")
        report.check(row["description"] == item["description"], "fixtures vs seed",
                     f"{item['id']}: description differs")

    kitchen = fixtures["kitchen"]
    seed_kitchen = seed["kitchens.json"][0]
    report.check(seed_kitchen["name"] == kitchen["kitchen"]["name"], "fixtures vs seed", "kitchen name differs")
    stock_by_code = {ingredient_by_id[row["ingredient_id"]]["code"]: row["status"]
                     for row in seed["stock_status.json"]}
    fixture_stock = {row["ingredient"]: row["status"] for row in kitchen["stock"]}
    report.check(stock_by_code == fixture_stock, "fixtures vs seed",
                 "demo stock statuses differ between fixtures and seed")


def check_availability(recipes, stock, owned, report):
    report.group("availability")
    by_slug = {recipe["slug"]: recipe for recipe in recipes if recipe is not None}
    demo = {ingredient: stock.get(ingredient, "unknown") for ingredient in stock}
    # Kitchen with everything present (used only to isolate equipment effects).
    full = {ingredient: "have" for ingredient in stock}

    adobo = by_slug.get("chicken-adobo")
    if adobo is not None:
        state, missing, confirm, _ = evaluate_recipe(adobo, demo, owned)
        report.check(state == "blocked", "demo kitchen: Chicken Adobo",
                     f"expected blocked on bay_leaf, got {state}")
        report.check(missing == ["ingredient:bay_leaf"], "demo kitchen: Chicken Adobo",
                     f"expected only ingredient:bay_leaf missing, got {missing}")
        report.check(confirm == [], "demo kitchen: Chicken Adobo", f"expected no prompts, got {confirm}")

    sinangag = by_slug.get("sinangag")
    if sinangag is not None:
        state, missing, confirm, _ = evaluate_recipe(sinangag, demo, owned)
        report.check(state == "ready", "demo kitchen: Sinangag", f"expected ready, got {state}")
        report.check(missing == [] and confirm == [], "demo kitchen: Sinangag",
                     f"expected no missing/prompt codes, got {missing} / {confirm}")

    pork = by_slug.get("crispy-pork-belly")
    if pork is not None:
        for method_key in ("pan_fry", "air_fry"):
            state, missing, confirm, required = evaluate_recipe(pork, demo, owned, method_key)
            report.check(state == "ready", f"demo kitchen: pork belly {method_key}",
                         f"expected ready when both appliances are owned, got {state}")
            report.check(confirm == [], f"demo kitchen: pork belly {method_key}",
                         f"optional unknowns must not prompt, got {confirm}")
        state, missing, _, required = evaluate_recipe(pork, demo, owned, "air_fry")
        report.check(required == ["air_fryer", "stovetop"], "demo kitchen: pork belly air_fry",
                     f"the air-fry path needs both appliances, got {required}")
        _, _, _, required = evaluate_recipe(pork, demo, owned, "pan_fry")
        report.check(required == ["stovetop"], "demo kitchen: pork belly pan_fry",
                     f"the pan-fry path needs the stovetop only, got {required}")

        state, missing, _, _ = evaluate_recipe(pork, demo, {"stovetop"}, "air_fry")
        report.check(state == "blocked" and missing == ["equipment:air_fryer"],
                     "pork belly air_fry without an air fryer",
                     f"expected blocked on equipment:air_fryer, got {state} / {missing}")
        state, missing, _, _ = evaluate_recipe(pork, demo, {"air_fryer"}, "pan_fry")
        report.check(state == "blocked" and missing == ["equipment:stovetop"],
                     "pork belly pan_fry without a stovetop",
                     f"expected blocked on equipment:stovetop, got {state} / {missing}")
        state, missing, _, _ = evaluate_recipe(pork, demo, {"stovetop"}, "pan_fry")
        report.check(state == "ready", "pork belly pan_fry with a stovetop",
                     f"the pan-fry path works with the stovetop only, got {state} / {missing}")

    # unknown prompts, out blocks, optional never blocks (docs/06 section 8, #2-#4)
    unknown_required = {}
    for slug, recipe in by_slug.items():
        method_key = "air_fry" if recipe["methods"] else None
        for line in recipe["ingredients"]:
            if not line["optional"]:
                unknown_required[line["ingredient"]] = "unknown"
        all_unknown = dict(full)
        all_unknown.update(unknown_required)
        state, missing, confirm, _ = evaluate_recipe(recipe, all_unknown, owned, method_key)
        report.check(state == "needs_confirmation", f"unknown required: {slug}",
                     f"unknown must not block (expected needs_confirmation, got {state} / {missing})")
        optional_out = dict(full)
        for line in recipe["ingredients"]:
            if line["optional"]:
                optional_out[line["ingredient"]] = "out"
        state, missing, confirm, _ = evaluate_recipe(recipe, optional_out, owned, method_key)
        report.check(state == "ready", f"optional out: {slug}",
                     f"optional ingredients never block (got {state} / {missing})")
        low_required = dict(full)
        for line in recipe["ingredients"]:
            if not line["optional"]:
                low_required[line["ingredient"]] = "low"
        state, missing, confirm, _ = evaluate_recipe(recipe, low_required, owned, method_key)
        report.check(state == "ready", f"low required: {slug}", f"'low' never blocks (got {state})")

    for slug in sorted(by_slug):
        recipe = by_slug[slug]
        if recipe["methods"]:
            report.check(resolve_method(recipe, "pan_fry") is not None, f"method path: {slug}",
                         "pan_fry resolves")
            report.check(resolve_method(recipe, "air_fry") is not None, f"method path: {slug}",
                         "air_fry resolves")
            pan = {impl["stepNumber"]: impl for impl in resolve_method(recipe, "pan_fry")}
            air = {impl["stepNumber"]: impl for impl in resolve_method(recipe, "air_fry")}
            for number in [step["stepNumber"] for step in recipe["steps"] if step["variants"]]:
                if not report.check(number in pan and number in air, f"method path: {slug}",
                                    f"step {number} resolves on both methods"):
                    continue
                report.check(pan[number]["instruction"] != air[number]["instruction"], f"method path: {slug}",
                             f"step {number} reads differently per method")
                report.check(pan[number]["durationSeconds"] != air[number]["durationSeconds"],
                             f"method path: {slug}", f"step {number} times differently per method")
                report.check(pan[number]["spriteKey"] != air[number]["spriteKey"], f"method path: {slug}",
                             f"step {number} shows a different sprite per method")
            for impl in list(pan.values()) + list(air.values()):
                report.check("ingredient" not in impl, f"method path: {slug}",
                             "a resolved implementation never scopes ingredients")


def check_sqlite_load(seed, report):
    """Prove the seed rows insert into db/schema-sqlite.sql without violating a constraint."""
    where = "seed load into db/schema-sqlite.sql"
    report.group("seed load")
    try:
        import sqlite3
    except ImportError:  # pragma: no cover - every CPython build ships sqlite3
        report.check(True, where, "")
        return
    try:
        schema = SCHEMA_SQL.read_text(encoding="utf-8")
    except FileNotFoundError:
        report.fail(where, "db/schema-sqlite.sql is missing")
        return
    order = ["units.json", "ingredients.json", "equipment.json", "kitchens.json",
             "kitchen_equipment.json", "stock_status.json", "recipes.json",
             "recipe_equipment.json", "recipe_ingredients.json", "recipe_steps.json",
             "recipe_step_variants.json"]
    connection = sqlite3.connect(":memory:")
    try:
        connection.executescript(schema)
        for name in order:
            rows = seed[name]
            if not rows:
                continue
            columns = list(rows[0])
            statement = (f"INSERT INTO {SEED_TABLES[name]} ({', '.join(columns)}) "
                         f"VALUES ({', '.join('?' for _ in columns)})")
            connection.executemany(statement, [[row[column] for column in columns] for row in rows])
        expected_rows = {"units": 9, "ingredients": 15, "equipment": 5, "kitchens": 1,
                         "kitchen_equipment": 2, "stock_status": 15, "recipes": 3,
                         "recipe_equipment": 2, "recipe_ingredients": 26, "recipe_steps": 18,
                         "recipe_step_variants": 1}
        for table, expected in sorted(expected_rows.items()):
            observed = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            report.check(observed == expected, where, f"{table} holds {observed} rows, expected {expected}")
        broken = connection.execute(
            """
            SELECT e.id FROM stock_event e
            WHERE e.from_status <> COALESCE((
                SELECT previous.to_status FROM stock_event previous
                WHERE previous.ingredient_id = e.ingredient_id AND previous.id < e.id
                ORDER BY previous.id DESC LIMIT 1), 'unknown')
            """
        ).fetchall()
        report.check(broken == [], where, f"the seeded stock chain is broken at {broken}")
        connection.rollback()
    except sqlite3.Error as exc:
        report.fail(where, f"seed rejected by the schema: {exc}")
    finally:
        connection.close()


def main():
    report = Report()
    sprites = load_sprite_manifest(PIXEL_SPEC, report)
    ddl_columns = load_ddl_columns(SCHEMA_SQL, report)

    ingredients_file = load_json(FIXTURES / "ingredients.json", report, "assets/fixtures/ingredients.json")
    equipment_file = load_json(FIXTURES / "equipment.json", report, "assets/fixtures/equipment.json")
    kitchen_file = load_json(FIXTURES / "kitchen_demo.json", report, "assets/fixtures/kitchen_demo.json")

    recipe_paths = sorted(RECIPE_FIXTURES.glob("*.json")) if RECIPE_FIXTURES.is_dir() else []
    report.check(len(recipe_paths) == 3, "assets/fixtures/recipes/",
                 f"expected 3 recipe files, found {len(recipe_paths)}")
    recipes = []
    for path in recipe_paths:
        payload = load_json(path, report, f"assets/fixtures/recipes/{path.name}")
        if isinstance(payload, dict) and isinstance(payload.get("recipe"), dict):
            report.check(payload.get("seedVersion") == SEED_VERSION,
                         f"assets/fixtures/recipes/{path.name}", f"seedVersion must be {SEED_VERSION}")
            report.check(path.stem == payload["recipe"].get("slug"),
                         f"assets/fixtures/recipes/{path.name}", "file name must equal the recipe slug")
            recipes.append(payload["recipe"])
        else:
            report.fail(f"assets/fixtures/recipes/{path.name}", "expected {seedVersion, recipe}")

    if not isinstance(ingredients_file, dict) or not isinstance(equipment_file, dict):
        print("Kusina content validation\nERROR: catalog fixtures did not load; stopping.", file=sys.stderr)
        return 1
    report.check(ingredients_file.get("seedVersion") == SEED_VERSION, "assets/fixtures/ingredients.json",
                 f"seedVersion must be {SEED_VERSION}")
    report.check(equipment_file.get("seedVersion") == SEED_VERSION, "assets/fixtures/equipment.json",
                 f"seedVersion must be {SEED_VERSION}")

    ingredients = ingredients_file.get("ingredients") or []
    equipment = equipment_file.get("equipment") or []
    ingredient_by_id, equipment_by_code = check_catalog(ingredients, equipment, sprites, report)
    kitchen_name, stock, owned = check_kitchen(kitchen_file, ingredient_by_id, equipment_by_code, report)
    check_recipes(recipes, ingredient_by_id, equipment_by_code, sprites, report)

    seed = {}
    for name in SEED_COLUMNS:
        payload = load_json(SEED / name, report, f"assets/seed/{name}")
        if payload is not None:
            seed[name] = payload
    check_seed(seed, {"kitchen": kitchen_file, "recipes": recipes,
                      "ingredients": ingredients_file, "equipment": equipment_file},
               sprites, ddl_columns, report)
    check_parity({"recipes": recipes, "kitchen": kitchen_file, "ingredients": ingredients_file,
                  "equipment": equipment_file}, seed, report)
    check_availability(recipes, stock, owned, report)
    check_sqlite_load(seed, report)

    # No scheduling content anywhere: the user owns dates.
    for name, payload in list(seed.items()) + [
        ("ingredients", ingredients_file), ("equipment", equipment_file), ("kitchen", kitchen_file)
    ]:
        walk_json(payload, f"content:{name}", report)
    for recipe in recipes:
        walk_json(recipe, f"content:{recipe.get('slug')}", report)

    total_ingredients = len(ingredients)
    total_equipment = len(equipment)
    step_count = len(seed.get("recipe_steps.json", []))
    line_count = len(seed.get("recipe_ingredients.json", []))
    variant_count = len(seed.get("recipe_step_variants.json", []))

    print("Kusina content validation")
    print(f"  manifest: {len(sprites)} sprite keys from docs/07 section 11.3")
    print(f"  fixtures: {len(recipes)} recipes, {total_ingredients} ingredients, {total_equipment} appliances,"
          f" kitchen {kitchen_name!r}")
    print(f"  seed:     {len(seed)} tables, {step_count} steps, {line_count} ingredient lines,"
          f" {variant_count} step variants")
    print(f"  checks:   {report.checks} assertions")

    if report.errors:
        print(f"FAIL: {len(report.errors)} content error(s)", file=sys.stderr)
        for error in report.errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("OK: fixtures and seed content are valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
