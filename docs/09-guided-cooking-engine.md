# Guided-Cooking Engine

**Status:** draft for review - Owner: engine-designer - Depends on: docs/02, docs/03 section 7, docs/04 section 5

**Purpose:** the implementation contract for the pure-Dart guided-cooking engine: step data, equipment variants, session state, timers, progress, and the three-choice usage review over tri-state stock. The engine has no Flutter imports and no SQL. It is testable with a fixed clock and an in-memory store.

**Reads:** [02-domain-model.md](02-domain-model.md) sections 3, 5, 6, 7; [03-database-design.md](03-database-design.md) section 7; [04-seed-data-plan.md](04-seed-data-plan.md) section 5; [GLOSSARY.md](../GLOSSARY.md). **Amendments:** [06-flutter-product-scope.md](06-flutter-product-scope.md) owns the rule changes quoted below. **UI:** [07-pixel-ui-spec.md](07-pixel-ui-spec.md). **Data layer:** [08-flutter-architecture.md](08-flutter-architecture.md), `db/schema-sqlite.sql`.

Locked inputs (docs/06): Flutter target, offline SQLite, tri-state presence `unknown | have | low | out`, 3 shipped dishes, no quantities or scaling, timers advisory but suspension-correct, "guide me anyway" exists. This document never contradicts them.

## 0. Amendments this engine depends on

The engine is written against the amended rules. It is a bug in this document to restate the old quantity rules. The text that actually changes behavior:

| Old rule (docs/02) | Conflict | Engine consequence | Owner |
|---|---|---|---|
| R8 availability hard-gates start | L5 requires guide-anyway | `start(guideAnyway: true)` is legal when unavailable; it persists the missing list (§5.3) | docs/06 |
| R8 "missing stock row = zero = missing" | L3 `unknown` is not missing | `unknown` never blocks; it is flagged, and only an explicit usage choice writes a status `unknown→low`/`out` (§8) | docs/06 |
| R4/R5/R6/R14 balances and signed deltas | no quantities | completion writes presence transitions + append-only stock events, never amounts (§8) | docs/06 |
| R13 completion collects editable amounts | the review is a three-way status choice | `CompletionChoice` has exactly three values; completion writes stock events, never amounts (§8) | docs/06 A4 |
| R9 serving scaling | deferred | engine reads no serving input; `servings` = base yield, display only | docs/06 |
| R12 "timer state is not persisted" | suspension correctness | timer is persisted as an absolute UTC instant + duration, never a counter (§6) | docs/06 |
| docs/03 §4.13 `current_step_number` is `1..N` | review phase must survive a kill | `N+1` is the review sentinel (§7.3) | docs/03 SQLite port, T3 |
| docs/02 §6 "app closed during timer: timer not persisted" | superseded | replaced by §10 rows 1-6 | docs/06 |
| GLOSSARY "Consumption review" (editable amounts) | no quantities | the review is a per-ingredient three-way choice; GLOSSARY edit proposed by docs/06 | docs/06 |

---

## 1. Vocabulary additions

Terms used here and nowhere else in the package. Defined once; used consistently.

| Term | Definition |
|---|---|
| **Presence status** | One of `unknown`, `have`, `low`, `out` for one kitchen and one ingredient. `unknown` means "never set or deliberately unset"; the other three are the tri-state presence levels. |
| **Stock event** | An append-only record of one presence-status transition: `from_status → to_status`, with a `reason` and an optional `session_id`. Replaces the old "inventory transaction" (signed quantity). A no-op writes no event. |
| **Step variant** | An alternate implementation of one guided step that requires a different appliance. The canonical step is the implementation used when the cook's chosen method does not override that step. |
| **Variant group** | A named set of steps that must take the same appliance path (for example, one `cook_method` group covering "boil then air-fry" versus "boil then pan-fry"). The cook's choice for a group is one appliance; every step in the group is then resolved on that appliance. |
| **Method** | The cook-facing name for one option of a variant group: `pan_fry` (needs `stovetop`) or `air_fry` (needs `air_fryer`) on dish 3. The cook picks the method on the recipe detail; the engine never picks it and never swaps it. |
| **Equipment path** | The engine's per-step choice of implementation (canonical or a specific variant) fixed at session start. Synonymous with "the way this cook is doing the dish". |
| **Review phase** | The state where all steps are behind the cook and the completion review is open. Persisted as `current_step_number = N + 1` (sentinel). |
| **Completion line** | One ingredient presented in the review: current presence status, the cook's choice, and the resulting transition (if any). |
| **Guide-anyway start** | A session started while availability is `blocked`, with `started_without_availability = 1` and the missing list persisted. |

`Usage review` is docs/06's name for the end-of-session screen; this document also calls it the completion review. GLOSSARY's "consumption review" (editable amounts) is amended by docs/06 §3.9, which also proposes the `stock event` definition. `Guided step`, `cooking session`, `active session`, `availability`, and `missing requirement` keep their GLOSSARY meanings. The presence state is always **stock status**; the retired term for a measured amount is not used in this document, and no numeric quantity exists in the MVP.

**No quantities, no scaling, no conversion.** The engine never reads `recipe_ingredients.quantity`, never accepts a servings argument, and never compares amounts. Those columns stay in the seed as display-only reference data (docs/06 L3).

---

## 2. Step model

### 2.1 Declarative, never generated

Steps are authored seed rows. The engine selects, orders, and displays them; it never composes instruction text, never fills a duration from a template, never appends conditional clauses. Given the same recipe and the same persisted session row, two implementations must produce byte-identical step text. This keeps copy reviewable (school rubric), keeps timers truthful, and makes golden tests possible.

### 2.2 Fields

`recipe_steps` (MVP additions in bold; requirements for T3 in §3, not DDL):

| Field | Type | Null | Rule |
|---|---|---|---|
| `step_number` | int | no | 1..N contiguous per recipe (existing invariant). Defines order; there is no separate `order` field. |
| `kind` | enum | no | One of the five kinds in §2.3. **New.** |
| `instruction` | text | no | ≤ 2 short sentences, ≤ 180 characters. The only mandatory cooking copy. |
| `detail` | text | yes | ≤ 120 characters. Secondary line: technique note, what "tender" looks like. **New.** |
| `duration_seconds` | int | yes | Non-null and > 0 means the step offers one countdown timer. `0` and negative are **seed errors**, normalized to null by the loader (§2.4 L3). |
| `equipment_id` | text | yes | The appliance this canonical implementation needs. Null = equipment-neutral. Must exist in the equipment catalog (L10); it need not appear in `recipe_equipment`, which is empty for a recipe whose appliance is declared by a method group. |
| `ingredient_refs` | list<text> | empty | Catalog ingredient ids this step touches; stored as `ingredient_refs_json` (JSON array of codes, loader-validated by L9). Drives the "have ready" chips and the review's default ordering. Display only. **New.** |
| `caution` | text | yes | ≤ 90 characters, imperative, safety or irreversible-action warning. Rendered above the advance button (§9). **New.** |
| `sprite_key` | text | seed: yes | Stable asset id from the fixed set in docs/07. When null the loader derives `step_{kind}_{equipment_id ?? "none"}`; the loaded model always has a non-null key. The engine never invents a key; unknown key → fallback `step_{kind}_none`. **New.** |
| `variant_group` | text | yes | Group id shared by steps that must co-vary. Null = no appliance choice. **New.** |

A step has no `timer_id`, no `branch`, no `ingredient_quantity`, no `servings`, no `image_path`, no `next_step` pointer. Action targets are never in step data.

### 2.3 Kinds

Five, not seven. Each kind exists only because it changes engine or UI behavior; anything that only changes an icon does not earn a kind.

| Kind | Equipment | Timer | Engine/UI behavior it buys | Lint |
|---|---|---|---|---|
| `prep` | null | null | Hands-on, no appliance scene; `prep` sprite; no notification possible. | duration must be null; equipment must be null |
| `heat` | required | allowed | Appliance must be ready before the next action; caution defaults to non-null; UI shows the appliance and a "hot" tone. | equipment non-null |
| `cook` | required | expected | Active cooking; the common timer step; `keepAwake` suggested while its timer runs. | equipment non-null |
| `wait` | allowed | required | Unattended wait; timer mandatory; notification is scheduled; "leave the kitchen" copy. | duration non-null and > 0 |
| `finish` | null | null | Plating/serving; always the last step; its advance opens the review. | exactly one per recipe; must be step N; duration null |

Rejected: **`add`** — adding ingredients is `prep` (room temperature) or `cook` (into a hot pan); `ingredient_refs` already carries the chip list, and a separate kind would only change an icon. **`check`** — doneness checks are `cook` or `wait`; a distinct kind would need its own art and no state behavior. Both are P1 if the UI ever branches on them.

### 2.4 Authoring limits and loader lint

The loader rejects a recipe that fails any rule; failures are reported with recipe slug, step number, rule id. These extend docs/04 §7 (they do not replace it).

| ID | Rule | On failure |
|---|---|---|
| L1 | 1 ≤ N ≤ 20 steps; contiguous `1..N`. | `SeedInvalid` |
| L2 | `instruction` ≤ 2 sentences and ≤ 180 chars; `detail` ≤ 120; `caution` ≤ 90. Sentence count = terminal punctuation count; `!`/`?` count too. | `SeedInvalid` |
| L3 | `duration_seconds` is null or > 0. `0` is never "instant". | normalized to null, warning logged |
| L4 | At most one timer per step (single nullable duration makes this structural). A step with two separately timed waits is two steps. | `SeedInvalid` (authoring) |
| L5 | No branching: no `if`, `optional` clause, or alternative appliance named inside `instruction`; alternatives live in `recipe_step_variants`. | `SeedInvalid` |
| L6 | `kind = wait` ⇒ `duration_seconds != null`, and only `wait`, `heat`, and `cook` may carry a duration (`prep` and `finish` must be null). Matches §2.3, the §2.5 table and the schema CHECKs. | `SeedInvalid` |
| L7 | `kind = prep` or `finish` ⇒ `equipment_id == null`; `kind ∈ {heat, cook}` ⇒ `equipment_id != null`. | `SeedInvalid` |
| L8 | Exactly one `finish`, at step N. | `SeedInvalid` |
| L9 | Every `ingredient_refs` id exists in the catalog; every step ingredient belongs to the recipe's ingredient list. | `SeedInvalid` |
| L10 | Every `equipment_id` (canonical or variant) exists in the equipment catalog. `recipe_equipment` is optional for a recipe with a `variant_group`: the group's canonical steps and variant rows declare the appliances instead, and `recipe_equipment` may be empty. For a recipe with no group, each canonical step's appliance must still be listed in `recipe_equipment` (existing seed rule 8.4). | `SeedInvalid` |
| L11 | Variant `priority` ≥ 1 and unique per `(step, equipment)` (stored for authoring order only — it is **not** a selection input); a variant's equipment ≠ canonical equipment; overrides nullable except `equipment_id`; a variant may change a duration but never remove a timer. Every method option of a group must resolve on every step in the group (a canonical step on the option's appliance, or a variant row for it). | `SeedInvalid` |
| L12 | `sprite_key` ∈ docs/07 asset manifest, or omitted (derived). | warning, fallback key |
| L13 | No quantities, units, or serving references in step copy. | warning (rubric: no quantity comeback) |

### 2.5 Worked canonical example: Chicken Adobo

docs/04 §5 authored the copy; this is that copy expressed in the step model. No variants: one path, `equipment_path = {2..6: stovetop}`.

| # | Kind | Instruction | Duration | Equipment | ingredient_refs | Caution | sprite_key | Group |
|---:|---|---|---:|---|---|---|---|---|
| 1 | prep | Pat the chicken dry and season with black pepper. | — | — | chicken thighs, black pepper | — | `step_prep_none` | — |
| 2 | heat | Heat the cooking oil in a wide pan over medium heat. | 480 | stovetop | cooking oil | Hot oil. | `step_heat_stovetop` | — |
| 3 | cook | Brown the chicken on all sides in batches. | — | stovetop | chicken thighs | — | `step_cook_stovetop` | — |
| 4 | cook | Add the garlic and cook until fragrant. Pour in the soy sauce, vinegar, sugar, and 120 ml water. | — | stovetop | garlic, soy sauce, vinegar, sugar | — | `step_cook_stovetop` | — |
| 5 | wait | Add the bay leaves, cover, and simmer until the chicken is tender. | 1500 | stovetop | bay leaf | — | `step_wait_stovetop` | — |
| 6 | cook | Uncover and reduce the sauce, spooning it over the chicken. | 300 | stovetop | — | — | `step_cook_stovetop` | — |
| 7 | finish | Serve hot with rice. | — | — | — | — | `step_finish_none` | — |

Notes: docs/04 step 2 was one row containing "heat the oil" and "brown the chicken"; splitting it is required by the one-timer-per-step rule (L4) and by L7 (a `heat` step for the preheat, then a `cook` step for the browning). This is an amendment to the docs/04 §5 table, owned by the recipe seed author; it does not change the dish.

Row 7's instruction mentions rice as a serving suggestion, but rice is not an Adobo ingredient line (docs/06 §5), so the row carries no `ingredient_refs` entry and lint L9 is right to reject one. The seed follows this table.

---

## 3. Persistence contract (requirements for T3; DDL is T3's)

The engine needs these persisted fields. Column names are the contract; T3 owns types, indexes, and exact DDL. The final schema is [`db/schema-sqlite.sql`](../db/schema-sqlite.sql) (docs/08 §4) and uses `stock_status`, `stock_event`, `recipe_step_variants`, and `session_step_choices`; §3.6 checks this section against it field by field. No DDL is duplicated here.

### 3.1 `cooking_sessions` (additions)

| Column | Type | Rule |
|---|---|---|
| `status` | TEXT | `'in_progress' \| 'completed' \| 'abandoned'` (existing). |
| `current_step_number` | INTEGER | 1..N+1. `N+1` = review phase. `CHECK (current_step_number >= 1)` only; no upper bound (N is app-enforced). |
| `timer_started_at` | TEXT NULL | UTC ISO-8601 with `Z`, millisecond precision. Null = no timer. |
| `timer_duration_seconds` | INTEGER NULL | > 0. Non-null iff `timer_started_at` non-null. |
| `last_seen_at` | TEXT NULL | UTC ISO-8601. Last instant the guide screen was known foreground. Drives `done` vs `overrun` and the "you were away" copy. Present in the final schema. |
| `started_without_availability` | INTEGER | 0/1, default 0. |
| `missing_requirements_json` | TEXT NULL | JSON array of stable code strings persisted at guide-anyway start: `["equipment:air_fryer","ingredient:bay_leaf","group:cook_method"]` (docs/06 A2). Null when the start was available. The in-memory `MissingRequirement` may carry kind/id/alternatives; persistence is codes only, and a group's alternatives are not persisted because the pinned path records the choice. |
| `started_at`, `completed_at`, `updated_at` | TEXT | existing; `completed_at` set only on completion. |

`abandoned_at` is **not** required: abandonment is recorded by `status` + `updated_at` (docs/02 §7 has no abandonment timestamp either). If T3 adds it, the engine tolerates it and writes it on abandon.

No timer step id is stored: every step change clears the timer, so a live timer belongs to `current_step_number` by construction. docs/06 §3.5 names `timer_step_number`; the final schema omits it (§3.6). There is also no paused column; do not add pause semantics (§6.8).

### 3.2 `session_step_choices` (new, required)

Persist the equipment path fixed at start — the cook's chosen method rendered per step; otherwise an equipment edit would rewrite instructions mid-cook (violates docs/02 §6 "does not alter an active session").

| Column | Rule |
|---|---|
| `session_id` | FK, part of PK |
| `step_number` | 1..N, part of PK |
| `equipment_id` | INTEGER NULL (null = equipment-neutral implementation) |
| `is_variant` | INTEGER 0/1 — 1 when a `recipe_step_variants` row was selected |
| `variant_id` | INTEGER NULL — set iff `is_variant = 1`; FK to `recipe_step_variants` |

`equipment_id` alone would identify the implementation (variants are unique per step and equipment, and a variant's equipment never equals its canonical step's equipment); the final table stores `variant_id` as well, so the engine writes all three fields. No lookup by equipment is needed at read time.

The engine reads the table once when the session opens and never recomputes the path while the session is active. (A single `equipment_path_json` column would also satisfy the contract, but the final table is joinable and lint-checkable.)

### 3.3 `stock_event` and completion writes (final schema)

The final schema is `stock_status(kitchen_id, ingredient_id, status, updated_at)` for current state and `stock_event(id, ingredient_id, from_status, to_status, reason, cooking_session_id, note, created_at)` for history — no `kitchen_id` on the event because there is exactly one local kitchen. [docs/06](06-flutter-product-scope.md) §3.3 (A3) fixes the reason domain and the legal reason/transition pairs; docs/08 §4.3 implements it. Engine requirements:

| Requirement | Detail |
|---|---|
| Status domain | `from_status`, `to_status`, and `stock_status.status ∈ ('unknown','have','low','out')`. |
| No-op ban | `CHECK (from_status <> to_status)`. A "no change" outcome writes **no row**, never a self-transition. |
| Reason domain | `reason IN ('initial','restock','used_some','used_up','waste','correction')` — docs/06 §3.3. `consume` and `adjustment` are retired names. The engine writes `used_some`, `used_up`, and (review correction only) `restock`. |
| Engine transition set | `used_some`: `(have,low)`, `(unknown,low)`. `used_up`: `(have,out)`, `(low,out)`, `(unknown,out)`. `restock` (review correction): `(unknown,have)`, `(low,have)`, `(out,have)`. No other engine triples: `low + Used it`, `out + Used it up`, and every `Didn't use` write nothing. Exactly §8.3. |
| Session link | `cooking_session_id` is non-null only for `used_some` and `used_up`. The review's `restock` correction is written **unlinked** (`NULL`) so it cannot collide with the usage unique index; its `note` may name the session for audit. |
| Idempotency index | `UNIQUE (cooking_session_id, ingredient_id) WHERE cooking_session_id IS NOT NULL` — one usage event per ingredient per session. The unlinked restock sits outside it. |
| One current row | `stock_status` PK `(kitchen_id, ingredient_id)` with `kitchen_id = 1`; every ingredient used by a shipped recipe gets a row from seed (§3.5). |
| Append-only | No UPDATE/DELETE paths in the app; corrections are new events. |

Because the restock event is unlinked, the usage unique index cannot guard it; the terminal pre-check and the conditional session update are what stop a second completion from writing it twice (§8.6). The transaction stays atomic: each status update, its event, and the session completion all commit or none do.

### 3.4 `recipe_step_variants` (new, required)

The final schema defines `recipe_step_variants(id, step_id, equipment_id, instruction_override, duration_override, sprite_override, priority)`. Engine requirements: `step_id` → `recipe_steps.id`; `equipment_id` non-null and ≠ the canonical step's equipment; `duration_override` null or > 0; `priority` integer ≥ 1, unique per `(step_id, equipment_id)`; delete cascades with the step. `variant_group` lives on `recipe_steps` (one row per step; no separate group table needed). The final schema matches: the step fields in §2.2 exist, `priority >= 1`, and `UNIQUE (step_id, equipment_id)` is enforced.

### 3.5 Stock seed requirement

Every catalog ingredient that appears in a shipped recipe **must** have a `stock_status` row for the local kitchen, defaulting to `unknown`. Rationale: the review's status write is an `UPDATE ... WHERE status = <read>`; a missing row would turn into a data error at completion. If a row is missing anyway, completion aborts with `SeedMissing` (§8.5) and nothing is written.

### 3.6 Conformance with the final SQLite schema (for T5)

`db/schema-sqlite.sql` now implements §3.1-§3.5. Field by field:

| Item | Status |
|---|---|
| `cooking_sessions.last_seen_at` | present; drives `done` vs `overrun` (§6.2) |
| `started_without_availability` + `missing_requirements_json` | present, with a coupled CHECK (0 ⇔ NULL) |
| `current_step_number` | `CHECK (>= 1)` only; `N+1` is legal |
| timer persistence | `timer_started_at` + `timer_duration_seconds`; no paused state, no step id; cleared on advance/complete/abandon |
| `session_step_choices` | present: `(session_id, step_number, equipment_id, is_variant, variant_id)` |
| `recipe_steps` | `kind`, `detail`, `caution`, `sprite_key`, `variant_group`, `ingredient_refs_json`; row CHECKs encode L6-L8 |
| `recipe_step_variants` | present; `priority >= 1`, unique `(step_id, equipment_id)` |
| `stock_status` / `stock_event` | final names; reason domain and pairs from docs/06 §3.3; usage-only session link; usage unique index |
| one active session | partial unique index on `(kitchen_id) WHERE status = 'in_progress'` |
| every seeded ingredient has a stock row | seed requirement plus the app guard (§3.5) |

Residual notes, none blocking:

- **`timer_step_number` (docs/06 §3.5) is not persisted.** Correctness does not need it: every step change clears the timer, so a live timer can only belong to the current step. Optional hardening if T5 wants literal parity with the amendment text.
- **`docs/06` §3.3's handoff names `ingredient_stock`; the package uses `stock_status`** (docs/08 §4.1). docs/09 uses the final names.
- **The review `restock` correction is unlinked** (§3.3) so it does not collide with `uq_stock_event_session_ingredient`.
- **`docs/07` §13.3's conflicts C1/C2 were raised against an earlier docs/09 draft.** §8 and §9 now follow docs/06 A3/A4: three choices, the `Probably have` chip, `low + Used it` as a no-op, `unknown + used` → `low`/`out`, and restock as a secondary affordance.
- **`docs/08` §4.3 now matches this section** on the reason enum and on the engine's writers (`used_some`, `used_up`, and the unlinked review `restock`); nothing to reconcile.

No Phase B schema blockers remain in this document's contract.


---

## 4. Equipment variants (bounded)

### 4.1 Shape

- The canonical step is authored for the dish as named. It is the implementation used where the cook's chosen method has no override for that step; it is **not** a default method.
- A variant row carries only the **delta**: an instruction override, a duration override, a sprite override, and the appliance it needs. It cannot add or remove steps, change `kind`, change `ingredient_refs`, introduce a timer where the canonical has none, or remove one where it has one. Step count and step order are identical on every path — that is what keeps progress, review order, and test coverage stable.
- `variant_group` makes several steps co-vary (e.g. a `cook_method` group where two steps both become pan-fry). The group's appliance is the **cook's pick** (§4.2): it is resolved once at start and applied to every step in the group, so mixed paths inside one group are impossible.

### 4.2 Explicit method choice (no auto-selection)

The method is a **cook's decision**, made on the recipe detail and fixed at `start()`; it is then persisted per step (§3.2). Pure function `planPath(recipe, ownedEquipment, requestedByGroup)`.

1. **The cook chooses.** For every `variant_group` the recipe has, the recipe detail offers one method per appliance (`cook_method` on dish 3: Pan-fry `pan_fry` → `stovetop`, Air-fry `air_fry` → `air_fryer`). The pick travels as `requestedByGroup: {group: equipmentId}`. No method is pre-selected, nothing is chosen on the cook's behalf, and `priority` is never read: it stays an authoring column (§3.4), not a selection input.
2. **No request, no start.** `start()` on a recipe with a `variant_group` and no request for that group returns `MethodChoiceRequired` and writes nothing. `checkAvailability()` / `evaluateAvailability()` without a request reports the per-method states for display only — the recipe-list badge shows the best method's state and names the method — and neither pins a path nor starts anything.
3. **Map the pick to a step implementation.** For each step:
   - `variant_group == null` → the canonical implementation; `equipment_id` = the canonical step's appliance (null = neutral). A missing appliance here is a missing requirement (`equipment`, id).
   - step in the requested group, `canonical.equipment_id == requested` → the canonical implementation.
   - step in the requested group, otherwise → the variant row with `equipment_id == requested`. The canonical step text is used only where the chosen method has no override for that step.
   - step in the requested group with neither a canonical nor a variant for the requested appliance → authoring error (L10/L11, `SeedInvalid`). The app records a `variantGroup` missing requirement (id = group, alternatives = the group's appliances) and pins the canonical implementations, so Guide anyway can still show instructions.
4. **Availability for the chosen path.** Equipment feasibility is exactly the set of appliances the chosen implementations need: `missing` = `{equipment_id of each chosen implementation that is not owned}`, reported as stable codes `equipment:<code>`. Dish 3: a Pan-fry pick needs `stovetop` for the boil steps and for the crisp step; an Air-fry pick needs `stovetop` and `air_fryer`. Ingredient presence is unchanged (docs/06 §3.2). A `blocked` result never re-selects: the cook's pick stands and Guide anyway may start it.
5. **Pin.** Write one `session_step_choices` row per step: `is_variant = 1` with `variant_id` and the variant's `equipment_id` where the chosen method overrides the step; otherwise `is_variant = 0`, `variant_id` NULL, and `equipment_id` = the appliance planned for that step (the chosen method's appliance where the step belongs to the requested group, the canonical appliance otherwise; NULL only for an equipment-neutral step). Later equipment edits never change it.
6. **Report.** `AvailabilityResult` = the pinned path's equipment feasibility (step 4) + the docs/06 §3.2 presence sets: `blocked` when anything is missing (`out` required ingredient or unowned equipment); `needsConfirmation` when nothing is missing but a required ingredient is `unknown`; `ready` otherwise. `lowWarnings` lists required `low` ingredients; `guideAnywayAllowed` is true whenever the recipe loaded.

Determinism: the pick is data, so two developers produce the same path from the same inputs — no ranking, no map iteration order, no floating point, no invented tie-breaks.

### 4.3 Worked example: Crispy Pork Belly, pan-fry vs air-fry

Dish 3 proves the mechanic. The canonical crisp step is the air fryer (the dish is named for it) and the pan-fry implementation is the `stovetop` variant; the boil steps are shared and always stovetop. Neither implementation is a default: the cook picks the method on the recipe detail and the pick decides step 5.

| # | Kind | Instruction (canonical) | Duration | Equipment | Group | Variant delta (stovetop) |
|---:|---|---|---:|---|---|---|
| 1 | prep | Pat the pork belly dry, score the skin, and season both sides with salt and black pepper. | — | — | — | — |
| 2 | heat | Bring a pot of water to a boil. | 420 | stovetop | — | — |
| 3 | cook | Boil the pork belly until the meat is tender, skimming the surface. | 1500 | stovetop | — | — |
| 4 | prep | Drain well and dry the skin with paper towels. | — | — | — | — |
| 5 | cook | Air-fry at 200 °C until the skin puffs and crackles. | 1200 | air_fryer | `cook_method` | stovetop variant: "Heat oil in a pan and fry the pork belly skin-side down until crisp.", duration 720, sprite `step_cook_stovetop` |
| 6 | finish | Rest on a rack, chop into pieces, and serve with banana ketchup. | — | — | — | — |

Path outcomes:

| Cook picks | Kitchen owns | Selected step 5 | Result |
|---|---|---|---|
| Pan-fry (`pan_fry`) | `stovetop` | `stovetop` variant: pan-fry copy, 720 s, sprite `step_cook_stovetop`, `is_variant = 1` | `ready` |
| Pan-fry (`pan_fry`) | no `stovetop` | `stovetop` variant, best effort (never swapped to Air-fry) | `blocked`, missing `equipment:stovetop`; Guide anyway starts it |
| Air-fry (`air_fry`) | `stovetop` + `air_fryer` | canonical: air-fry copy, 1200 s, `is_variant = 0` | `ready` |
| Air-fry (`air_fry`) | no `air_fryer` | canonical, best effort (never swapped to Pan-fry) | `blocked`, missing `equipment:air_fryer`; Guide anyway starts it |

The 1200 → 720 s delta is the point of the mechanic: the times differ by method, and the engine shows the time for the method the cook picked.

**Seed requirement (resolved, C4).** `recipe_equipment` for this dish is **empty**: each method declares its appliance through its own rows — step 5's canonical `air_fryer` and its `stovetop` variant — and L10 now permits that. Every availability read for a method-bearing recipe therefore goes through `checkAvailability()`/`planPath`, never through `recipe_equipment` alone: a stovetop-only kitchen that picks Pan-fry is `ready` (it never sees "missing air fryer"), and the same kitchen that picks Air-fry is `blocked` with `equipment:air_fryer` because the cook asked for the air fryer. This generalizes: a future dish cookable by oven *or* air fryer needs no shared appliance in `recipe_equipment`.

### 4.4 Why composition keeps art cheap

- **Default sprite derivation.** `sprite_key` defaults to `step_{kind}_{equipment}`; a variant gets the same treatment from its own equipment. Most variants therefore need **no** `sprite_override`.
- **Budget by kind × appliance, not by step.** The three shipped dishes have 7 + 5 + 6 = 18 canonical steps but only six distinct `(kind, equipment)` pairs: `prep/none`, `heat/stovetop`, `cook/stovetop`, `wait/stovetop`, `cook/air_fryer`, `finish/none`. Six step-scene composites cover all 18 steps and every path. Allow ≤ 2 overrides (e.g. a distinct pan-fry still) → **8 files maximum**, not 18, and not 18 × paths.
- **Composition, not per-step illustration.** Each scene = shared kitchen background + appliance sprite + kind pose + optional ingredient stills from docs/07's manifest. Ingredient stills are shared across dishes. The engine's only job is to hand the UI one valid key.

### 4.5 Why the engine must not generate a path per appliance combination

| Approach | Rejected because |
|---|---|
| Author one full step list per appliance combination | Combinatorial: a dish with 3 independent appliance choices has up to 2³ = 8 paths; 3 shipped dishes are cheap, but the mechanic exists to scale to the designed 9 dishes. Each path duplicates copy, art keys, validation, and tests, and the copies drift (one path says 20 min, another 25; the seed lint can't see it). |
| Compose instruction text at runtime ("if using an air fryer, ...") | Violates declarative-data rule §2.1 and L5; unreadable mid-cook; the cook must parse conditionals with greasy hands; timers become ambiguous; copy can no longer be reviewed or golden-tested. |
| Ask at each step which appliance to use | Mid-cook prompts; the group can end up mixed (air-fry step then pan-fry step); timers change under the cook; no stable resume. |
| Store the appliance in the canonical copy and let the cook adapt | Dish 3 would be identical to a pan-fry recipe for a stovetop kitchen; the variant mechanic disappears and the 3-dish demo loses its point. |
| Per-step variant chosen independently, no group | Two steps of one method can disagree; renders an impossible dish. Groups are the composition rule. |
| Rank the methods and pick for the cook (priority order, canonical-first, best-available) | Removes the cook's decision from the one dish whose point is that they choose, and makes the picker, the pinned choice, and criterion #14 dead surface. `priority` stays a stored authoring field (§3.4) but `planPath` never reads it. |

The chosen model is O(steps + variants), not O(paths): one canonical list, delta rows, one pinned row per step per session. Cost for dish 3: 1 variant row, 6 pinned rows, 1 extra sprite override at most.

### 4.6 Mid-session equipment edits

The path is pinned. Adding or removing an appliance during a session changes nothing in the guide, the copy, the timer, or the review. The next session replans from the new equipment set. This matches docs/02 §6 and removes a whole class of mid-cook surprises.

---

## 5. Session state machine

### 5.1 States and persisted fields

| State | Meaning | Terminal |
|---|---|---|
| `in_progress` | The cook is between step 1 and the review sentinel. | no |
| `completed` | Review confirmed; stock events written in the same transaction. | yes |
| `abandoned` | Explicitly abandoned; no stock events ever. | yes |

Persisted per session: `id`, `kitchen_id`, `recipe_id`, `status`, `current_step_number`, `started_at`, `timer_started_at`, `timer_duration_seconds`, `last_seen_at`, `started_without_availability`, `missing_requirements_json`, `completed_at`, `updated_at`, plus the pinned path in `session_step_choices`. `servings` is stored as `recipes.servings` and never read by the engine.

Invariants (assert in debug, enforce in code):

- At most one `in_progress` session per kitchen: partial unique index `WHERE status = 'in_progress'`.
- `1 ≤ current_step_number ≤ N + 1`; `N+1` only after the final step was advanced.
- Both timer columns (`timer_started_at`, `timer_duration_seconds`) are null or non-null together and are cleared whenever `current_step_number` changes, on completion, and on abandonment. A live timer therefore always belongs to the current step; no step id is stored.
- `completed_at` non-null iff `status = 'completed'`.
- A terminal session is never written again, not even `last_seen_at`; the only exception is an idempotent `complete()` that performs no write at all.

### 5.2 Transition table

| # | From | To | Trigger | Guards | Writes | On guard failure |
|---:|---|---|---|---|---|---|
| S1 | — | `in_progress` | `start()` | recipe exists and lint-passed; no active session; a request for every `variant_group` the recipe has (§4.2); availability is `ready` or `needsConfirmation`, **or** `guideAnyway == true` | session row with step 1, `started_at`, path rows, flags | `RecipeNotFound`, `ActiveSessionExists`, `MethodChoiceRequired`, `AvailabilityBlocked(missing)` |
| S2 | `in_progress` | `in_progress` | `advance()` | 1 ≤ step ≤ N; step N+1 not reached; caller is on the pinned path | `current_step_number += 1`; clear both timer columns; `last_seen_at = now` | `StepOutOfRange`, `AlreadyAtReview` |
| S3 | `in_progress` | `in_progress` | `startTimer()` | current step's effective `duration_seconds` > 0; timer currently null | `timer_started_at = now`, `timer_duration_seconds = d`; schedule notification | `TimerNotAvailable`, `TimerAlreadyRunning` |
| S4 | `in_progress` | `in_progress` | `clearTimer()` | timer non-null | both timer columns NULL; cancel notification | no-op |
| S5 | `in_progress` | `in_progress` | `onResume()` / `markSeen()` | session exists | `onResume` writes nothing; `markSeen` writes `last_seen_at` | `NoActiveSession` |
| S6 | `in_progress` | `completed` | `complete()` at review | `current_step_number == N + 1`; every line valid (§8.1, §8.5); transaction succeeds | status, `completed_at`, both timer columns NULL; status updates + stock events | `CompletionIncomplete`, `InvalidCompletionLine`, `SeedMissing`; nothing written |
| S7 | `in_progress` | `abandoned` | `abandon(confirmed: true)` | `confirmed == true` | status, `updated_at`, both timer columns NULL; cancel notification; no stock events | `AbandonNotConfirmed` |
| S8 | `completed` \| `abandoned` | — | any transition | terminal | — | `SessionNotActive`; `complete()` returns `alreadyCompleted` instead |
| S9 | — | — | `start()` while active | active session exists | none | returns the active session (§5.3) |

`advance()` from step N sets `N+1` (review) and **does not complete** the session. `complete()` is only legal at `N+1`; calling it at step ≤ N is `CompletionIncomplete`.

### 5.3 Start

```
start(recipeId, guideAnyway, nowUtc, requestedByGroup) -> StartResult
```

1. Load recipe. Missing or lint-failing → `RecipeNotFound` / `SeedInvalid`. Never fabricate a step list.
2. `activeSession()` non-null → `StartResult.activeSessionExists(session)`; no new row. UI offers Resume / Abandon. This is the one-active-session rule and the second-attempt edge case in one place.
3. Resolve the cook's method: `requestedByGroup` must cover every `variant_group` the recipe has, else `StartResult` carries `MethodChoiceRequired` and nothing is written (§4.2). `planPath(recipe, ownedEquipment, requestedByGroup)` + ingredient presence, then branch on `AvailabilityResult.state`:
   - `ready` or `needsConfirmation` → start; `started_without_availability = 0`; `missing_requirements_json = null`. `needsConfirmation` still starts (the cook confirms the unknown items); it is not a block.
   - `blocked` and `guideAnyway == false` → `StartResult.blocked(missing)`; no row is written.
   - `blocked` and `guideAnyway == true` → start; `started_without_availability = 1`; persist `missing_requirements_json` as the returned stable code strings for the chosen method's unowned equipment and `out` ingredients. This is the only way to start a blocked dish; the flag and list are immutable for the session's life.
4. Write the session and the pinned path in one transaction. **No stock writes at start** (docs/02 R13 survives). No reservation, no status change, no notification.

`guideAnyway` is not an error when `state != blocked`: it is accepted and records `0`, so the flag can never lie. The UI should send it only from the blocked state. The flag means "started without availability" and nothing else.

### 5.4 Resume

- Cold start: `activeSession()` is read; if present, the home screen shows a resume card. Opening the guide calls `currentStep(sessionId, now)` then `onResume(sessionId, now)`, which returns a `ResumeInfo` with `currentStepNumber`, `totalSteps`, `timerState`, `awaySince` (now − `last_seen_at`), `stale` (now − `started_at` > 24 h), `startedWithoutAvailability`, and the missing list. `onResume` is **read-only**; the UI then calls `markSeen(now)`.
- The step is whatever was persisted. A kill, reboot, or abandonment of the app never changes `current_step_number`.
- A timer is not "restored" as a counter: it is re-derived from `timer_started_at` + duration (§6.2). The resume copy is generated by the engine, not the UI (§6.3).
- Equipment edits since the session started do not change the pinned path (docs/02 §6 preserved).
- Stale session (> 24 h): the engine sets `stale = true`; the UI offers Resume or Abandon. The engine **never auto-abandons** and never auto-completes.

### 5.5 Abandon

- Explicit action only, behind a confirmation dialog; the engine requires `confirmed: true`.
- Any step, including review and including a running timer, is abandonable.
- Writes: `status = 'abandoned'`, `updated_at`, timer cleared, notification cancelled. **Zero stock events** (docs/02 R13/R5 preserved for this path).
- Completed sessions cannot be abandoned (`SessionNotActive`), and the completion transaction refuses a session that was abandoned first (conditional UPDATE affects 0 rows → rollback).

### 5.6 Error taxonomy (engine-level; UI maps to copy)

| Code | Thrown by | Meaning |
|---|---|---|
| `RecipeNotFound` | start, review | Seed missing the recipe; never guess steps. |
| `SeedInvalid` | start, review, completion | Recipe or step data violates §2.4 or §3.5. |
| `ActiveSessionExists` | start | One active session rule; payload = the session. |
| `AvailabilityBlocked` | start | Unavailable without guide-anyway; payload = missing list. |
| `NoActiveSession` | any | No `in_progress` session for this kitchen/id. |
| `SessionNotActive` | advance, complete, abandon, timer | Session is terminal. |
| `StepOutOfRange` | advance | Step index outside 1..N, or path row missing. |
| `AlreadyAtReview` | advance, currentStep | `current_step_number == N + 1`; the UI opens `review()` instead. |
| `CompletionIncomplete` | complete | Not at review. |
| `InvalidCompletionLine` | complete | Ingredient not in the recipe, or a choice not allowed for the line's current status (`Used it` on `out`, or invalidated by a re-read); nothing written. |
| `AbandonNotConfirmed` | abandon | Guard for the confirmation dialog. |
| `TimerNotAvailable` | startTimer | Effective duration is null/≤ 0. |
| `TimerAlreadyRunning` | startTimer | No stacking; one timer per session. |
| `SeedMissing` | complete, resume | Inventory row or path row absent; abort transaction. |

---

## 6. Timer semantics

Timers are advisory: they never advance a step, never complete a session, and never touch stock. They are **suspension-correct**: the remaining time is always derived from an absolute instant, so backgrounding, killing, or rebooting the app cannot lose or drift the count.

### 6.1 Exactly what is persisted

| Field | Persisted when | Cleared when |
|---|---|---|
| `timer_started_at` (UTC ISO-8601 `...Z`) | `startTimer()` — the absolute instant | advance, clear, complete, abandon |
| `timer_duration_seconds` (int > 0) | same transaction as above; snapshot of the **effective** duration on the pinned path (variant override included) | same events |
| `last_seen_at` (UTC ISO-8601) | app pause/detach, `markSeen`, `advance`, `startTimer` | never (it is a fact, not state) |

Nothing else. No remaining-seconds column, no tick counter, no "paused" flag, no notification handle (notification id is derived from `session_id`, so it is cancellable without extra state), no per-step timer history (docs/02 §7 "no per-step completion log" survives).

### 6.2 Derivation

```
timerState(nowUtc):
  if timer_started_at == null            -> idle
  deadline = timer_started_at + durationSeconds
  raw      = deadline - nowUtc
  if nowUtc < timer_started_at:          // clock moved backwards
      -> running, remaining = durationSeconds, clockSkewDetected = true
  if raw > 0:                            -> running, remaining = raw
  if raw <= 0:                           // ended
      endedAgo = -raw
      lastSeen = max(persisted last_seen_at, in-memory last observed time)
      if lastSeen >= deadline            -> done      // the deadline was crossed while the guide was foreground
      else                               -> overrun   // it ended while the cook was away
```

`elapsed = clamp(now − startedAt, 0, duration)`. Remaining is never negative, never greater than the duration, and never "restored" from a counter. `last_seen_at` is persisted on lifecycle pause and on `markSeen`; while foreground the engine tracks `lastSeen = max(persisted, last read instant)` in memory — so a countdown that reaches zero on screen is `done`, and one that reaches zero while the app is backgrounded is `overrun`. This is the only reason `last_seen_at` exists and it is why `done` and `overrun` are distinguishable without a persisted "ended" flag.

Wall-clock jumps are accepted, not repaired: a forward jump makes a timer look finished early; a backward jump caps the remaining time at the duration. `timer_started_at` is never rewritten (it would falsify the fact). Optional P2 hardening: persist a monotonic `elapsedRealtime` anchor and prefer whichever source is smaller; rejected for MVP (extra platform channel, no observable user benefit on a kitchen timer).

### 6.3 States and copy

| State | Condition | UI | Engine copy (single source of truth) |
|---|---|---|---|
| `idle` | no timer | "Start timer" button on a timed step; nothing otherwise | — |
| `running` | 0 < remaining ≤ duration, or clock skew | Countdown, screen awake, in-app chime armed | "12:30 left" |
| `done` | ended, deadline crossed while foreground | "Timer done" flash + chime; button becomes "Clear timer"; advance stays enabled | "Timer done." |
| `overrun` | ended while away | "Finished {ago} ago" banner on return; advance stays enabled | "You were away {away}. The timer finished {ago} ago." |

Resume copy is composed by `onResume`, not the UI: `{away}` = now − `last_seen_at` rounded down to the largest unit (e.g. "4 min"), `{ago}` = now − deadline ("1 min"). Under 1 minute: "less than a minute". Over 24 hours: "more than a day". If no timer ran: "Welcome back. Step {k} of {N}."

### 6.4 Lifecycle matrix

| Event | Engine behavior | Persisted consequence | Accepted limitation |
|---|---|---|---|
| App backgrounded | `onPause` persists `last_seen_at`; timer untouched; notification already scheduled | `last_seen_at` | — |
| App killed | same as backgrounded; on next launch `onResume` derives | none beyond `last_seen_at` | — |
| Timer finishes while away | `overrun`; copy with `{ago}`; advance still manual | none | — |
| Device reboot | SQLite + UTC instant survive; `onResume` derives `done`/`overrun` | none | A queued local notification may be lost on reboot; the app never depends on notification delivery. |
| Wall clock forward | may show `overrun` early | none | Accepted; a kitchen timer is not a legal clock. |
| Wall clock backward | `running` capped at duration, `clockSkewDetected = true` | none | `started_at` not rewritten. |
| DST shift | UTC math unaffected; only display labels convert to local | none | — |
| Notification permission denied | timer still correct; no chime when backgrounded | none | In-app only. |
| Timer on a non-final step, cook advances early | timer cleared, notification cancelled, step changes | timer fields null | The pot keeps cooking; that is the cook's call, not the engine's. |

### 6.5 Completion notification

- Exactly one pending notification per session, id derived from `session_id`, scheduled for `timer_started_at + duration` in **local** trigger time but computed from UTC (platform API converts).
- Title: the recipe name. Body: the step's `instruction` truncated to one line, or a fixed "Timer done" if truncation would cut mid-sentence. Tapping opens the guide at the current step — it never advances or completes.
- Cancelled on clear, advance, completion, abandonment, and on timer restart.
- Denied permission is not an error; the in-app countdown remains authoritative.
- Exact-alarm restrictions (Android 12+) mean delivery can be late. Correctness never depends on it: state is derived on return.

### 6.6 Screen wake

The view keeps the screen on while (a) the guide screen is focused and (b) `timerState.phase == running`. Release on pause, on leaving the guide, on `done`/`overrun`, and on completion. The engine exposes the condition; the view owns the platform call (T2/T3).

### 6.7 Never auto-advance

No engine path changes `current_step_number` other than `advance()`. Timer end, notification tap, app resume, clock jump, and 24-hour staleness all leave the step and the session status untouched. `done` is information, not an action.

### 6.8 Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Persist remaining seconds and decrement in Dart | Wrong after suspension; a killed app loses the count; two writers (timer + DB) drift. |
| Pause / resume a timer | You cannot pause a pot. Pausing would also need a second timestamp and a paused state to test. |
| Monotonic uptime clock as the source of truth | Survives clock changes but not reboots; needs a platform channel; reintroduces "which clock" ambiguity. P2. |
| Auto-advance when the timer ends | Violates R12 (advisory) and the safety model: the cook must look at the food. |
| Persist a "timer ended" boolean | Derived state; a stale boolean would need a second repair path. |
| Per-step timer history | No history requirement (docs/02 §7); write amplification. |

---

## 7. Progress and review handoff

### 7.1 Math

```
completedSteps = clamp(currentStepNumber - 1, 0, N)     // in_progress
progress       = completedSteps / N                      // N >= 1 by lint
percent        = (completedSteps * 100) ~/ N            // integer floor; 100 only at review
```

| Position | completedSteps | progress | Shown |
|---|---:|---:|---|
| Step 1 of 7 | 0 | 0% | first step |
| Step 3 of 7 | 2 | 28% | step 3 |
| Step 7 of 7 (finish) | 6 | 85% | final step; primary button "Finish" |
| Review (`N+1`) | 7 | 100% | review; session still `in_progress` |
| Completed | 7 | 100% | summary |

`completedSteps` is derived from the persisted step index; there is no per-step log (docs/02 §7). A completed session keeps 100%.

### 7.2 No partial credit for a running timer

A running timer contributes **0** progress until the cook advances the step. Reasons:

1. Progress measures steps behind the cook, not time spent; timed steps are a minority (3 of 7 in adobo).
2. Timers are advisory and skippable. Time-based credit would reward leaving a pot, not cooking.
3. Progress must not move without user input; a silently ticking bar competes with the real completion gate and makes resume copy lie.
4. There is no persisted timer history to reconcile, and adding one for a progress animation is not worth a table.
5. A half-filled step has no UI representation: no "mostly done", no percentage on a step, no partial review.

The timer ring is the only time visualization; it is not a progress input. Rejected: weighted progress (time + steps) — untestable without a clock, and it would show 100% for a cook who started a 25-minute timer and left.

### 7.3 Review handoff

- Advancing from step N writes `current_step_number = N + 1` and **does not** change `status`. The review is a phase of an `in_progress` session, so killing the app in review resumes in review (no lost confirmation) and abandoning still writes nothing.
- The review is reached only through `advance()` at step N; a step-number jump is impossible because the engine never accepts a target step.
- Completion requires the sentinel: `complete()` at step ≤ N is `CompletionIncomplete`. This is the "final step hands to review without completing the session" rule, enforced in one predicate.
- `currentStep()` at the sentinel throws `AlreadyAtReview`; the UI calls `review()` instead. `ResumeInfo` carries `isReview` so a cold start in review reopens the review, not a fake step.
- Back from the review leaves the guide; the session stays at `N+1`. Re-entering the guide shows the review again. No engine operation decrements `current_step_number`, so completed steps cannot be un-completed; `advance()` at the sentinel is `AlreadyAtReview` and the only way to a new run is a new session.

---

## 8. Usage review and tri-state completion

**Normative sources:** [docs/06](06-flutter-product-scope.md) §3.3 (A3) defines the legal stock event and the reason domain; §3.4 (A4) defines the review's three choices and the status mapping. This section is the engine's implementation of both. If this document and docs/06 disagree, docs/06 wins.

docs/06 calls this screen the **usage review**. GLOSSARY's pre-pivot term is "consumption review"; its amendment is owned by docs/06 §3.9. The engine API is `review()`.

### 8.1 Choices

| Choice | Label | Legal for | Effect |
|---|---|---|---|
| `usedIt` | "Used it" | `have`, `low`, `unknown`; **disabled** for `out` (copy "already out") | `have→low` / `unknown→low` (`used_some`); `low` = no event (copy "already low") |
| `usedItUp` | "Used it up" | `have`, `low`, `unknown`, `out` | `have`/`low`/`unknown` → `out` (`used_up`); `out` = no event (stays `out`) |
| `didntUse` | "Didn't use" | every status, including `unknown` | no event, status unchanged |

Exactly three mutually exclusive choices. There is **no fourth "Not tracked" choice**: `unknown` is a stock status shown as context ("Probably have — confirm"), not a decision. Every line renders the same three actions; one may be disabled (`out` + `Used it`) and two may be no-ops for the line's status, and the UI must say which and why.

### 8.2 Defaults

| Line | Default | Why |
|---|---|---|
| required, `have`/`low` | `usedIt` | the common case for a dish you are cooking |
| required, `unknown` | `didntUse` | unknown is never upgraded by a default; only an explicit tap writes a status |
| required, `out` | `didntUse` | `Used it` is disabled; nothing can be inferred |
| optional, any status | `didntUse` | docs/06 §3.4: optional items usually are not used |

Defaults are presentation only. `review()` computes them in memory; nothing is written until `complete()`.

### 8.3 Mapping (normative; mirrors docs/06 §3.4)

| Status shown | **Didn't use** | **Used it** | **Used it up** |
|---|---|---|---|
| `have` | no event | `have→low` · `used_some` | `have→out` · `used_up` |
| `low` | no event | no event; stays `low` ("already low") | `low→out` · `used_up` |
| `unknown` | no event | `unknown→low` · `used_some` | `unknown→out` · `used_up` |
| `out` | no event; stays `out` | **disabled** (`InvalidCompletionLine` if submitted) | no event; stays `out` |

Three consequences the engine must not "improve":

- **`Used it` on `low` does not become `out`.** There is no level between `low` and `out`; `out` means none left. A cook who used some of a low ingredient is still low, and the log records nothing for that line.
- **`unknown` + an explicit usage writes a status.** The cook has told us they used it, so the status is learned: `unknown→low` (`used_some`) or `unknown→out` (`used_up`). The *default* `didntUse` still writes nothing.
- **`out` is the floor.** No choice can move `out` to `have`; only the explicit restock correction (§8.4) can. Nothing negative exists because there is no quantity.

### 8.4 Restock correction and the transition function

The review also lets the cook correct an ingredient to `have` ("I actually have this"). That is a `restock` event, not a usage event, and it is applied **before** the usage transition for that line, inside the same completion transaction:

| Correction | Event |
|---|---|
| `unknown→have`, `low→have`, `out→have` | `restock`, unlinked (`cooking_session_id` NULL; `note` may name the session) |
| already `have` | no event |

`completionTransitions(current, choice, restockToHave)` returns 0-2 chained transitions:

```
if restockToHave and current != have:
    emit(current -> have, restock); current = have
switch (current, choice):
    (have,    usedIt)    -> emit(have    -> low, used_some)
    (unknown, usedIt)    -> emit(unknown -> low, used_some)
    (low,     usedIt)    -> none
    (have,    usedItUp)  -> emit(have    -> out, used_up)
    (low,     usedItUp)  -> emit(low     -> out, used_up)
    (unknown, usedItUp)  -> emit(unknown -> out, used_up)
    (out,     usedItUp)  -> none
    (*,       didntUse)  -> none
    (out,     usedIt)    -> invalid line
```

Reason codes the engine may write: `used_some`, `used_up`, `restock`. `initial`, `waste`, and `correction` belong to the Stock screen and are never written by completion. `consume` and `adjustment` (docs/03) are retired by docs/06 §3.3.

docs/07 §8.1 specifies the control: tap the line's status tag → **I have it** (a secondary per-line affordance, not a fourth main choice). The `restock` row is written inside the completion transaction, before that line's usage transition. Because `stock_event.cooking_session_id` is reserved for `used_some` / `used_up` (§3.3), the review restock is written unlinked with the session id in `note`, so it cannot collide with `uq_stock_event_session_ingredient`.

A chain can be net-zero: `out` + restock + `Used it up` writes `out→have` then `have→out`. Both events are kept because they record two distinct claims (the stock was wrong; the cook then emptied it). Collapsing them to one `correction` event would hide the usage and break the reason pairing, so chaining wins.

### 8.5 Atomic SQLite transaction

`BEGIN IMMEDIATE` (single writer). Order is fixed:

1. Read the session. Verify: exists, `status = 'in_progress'`, `current_step_number = N+1`. If `completed` → return `alreadyCompleted` with zero writes (§8.6). If `abandoned` → `SessionNotActive`. Otherwise → `CompletionIncomplete`.
2. Read the current status of every line's ingredient **inside the transaction**. The review's displayed status is a snapshot and is never trusted for the write.
3. Per line, validate the choice against the **re-read** status (`isChoiceAllowed`). A stock edit between review and confirm can invalidate a submitted choice (snapshot `have`, now `out`, choice `usedIt`) → `InvalidCompletionLine`, rollback, refresh the review.
4. Compute the chain (§8.4) from the re-read status. For each transition in order:
   - `UPDATE stock_status SET status = ?, updated_at = ? WHERE kitchen_id = ? AND ingredient_id = ? AND status = ?`; `changes == 1` required (0 → `SeedMissing`, rollback).
   - `INSERT INTO stock_event (ingredient_id, from_status, to_status, reason, cooking_session_id, created_at) VALUES (?, ?, ?, ?, ?, ?)`; `cooking_session_id` is the session id for `used_some`/`used_up`, NULL for a review `restock`.
   - The pair must be legal per docs/06 §3.3; the DB CHECK is the second gate.
5. `UPDATE cooking_sessions SET status = 'completed', completed_at = ?, updated_at = ?, timer_started_at = NULL, timer_duration_seconds = NULL WHERE id = ? AND status = 'in_progress'`; `changes == 1` required, else rollback (`SessionNotActive`).
6. `COMMIT`. Any failure → `ROLLBACK`: no status, no event, no completion; retry after fixing the line.

Zero-event completions are legal (all `didntUse`, or every choice a no-op) and still run step 5. The old docs/02 completion steps that lock balances and validate amounts are superseded: presence has no insufficiency, so completion is never rejected for "not enough stock".

### 8.6 Idempotency

Three guards, in order:

1. **Terminal pre-check:** `complete()` on a `completed` session returns `CompletionResult.alreadyCompleted` — success-shaped, zero writes. A double tap or a retry after a kill is safe.
2. **Conditional session update** (`WHERE status = 'in_progress'`): a lost race affects 0 rows → rollback.
3. **Partial unique index** `uq_stock_event_session_ingredient` on `stock_event (cooking_session_id, ingredient_id) WHERE cooking_session_id IS NOT NULL`: at most one usage event per ingredient per session. The review `restock` is unlinked, so a completion can legitimately write a correction *and* a usage event for the same ingredient (§8.4) without colliding.

No completion token: one local process, one writer. Rejected as unnecessary state.

### 8.7 Guide-anyway behaviour at review

| Situation | Behaviour |
|---|---|
| required ingredient `unknown` | Three choices, default `didntUse`. Explicit `Used it` writes `unknown→low`; `Used it up` writes `unknown→out`. |
| required ingredient `out` | `Used it` is disabled; `Used it up` is a no-op (stays `out`); the restock correction is how the cook says "I actually have it" (then `have→low` if they also used it). |
| unowned equipment on the chosen method's path | Not part of the review (equipment is not stocked). The missing list stays in the guide banner and the session history. |
| every line left at defaults | Completion is legal; it may write zero events. |

Guide-anyway changes start metadata and banners only; it never changes review legality.

### 8.8 Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Keep editable amounts / an optional quantity tier | Re-opens locked L3; reintroduces units, conversion, negative-balance checks, and a keypad in the kitchen. P1. |
| A fourth "Not tracked" choice | Duplicates the `unknown` chip and creates a dead-end button; `unknown` is a status, not a decision (docs/06 §3.4). |
| `low` + `Used it` → `out` | Overstates the loss (some is left) and makes `low` meaningless; docs/06 A4 makes it a no-op. |
| `out` + `Used it` → `low` | Invents stock from a tap; docs/06 disables the action. |
| `Used it` on `unknown` → no write | Loses the only chance to learn the status; docs/06 A4 writes `unknown→low`. |
| Apply the restock correction outside the completion transaction | Leaves partial state if the cook then abandons; one transaction keeps the review atomic. |
| Auto-complete with defaults | Loses the confirmation moment; R13 survives. |

## 9. Practical cooking UX rules the engine exposes

Contract items for T2/T3; the engine supplies the state and the strings, the view supplies the pixels.

| Rule | Value | Engine support |
|---|---|---|
| One-tap advance | single primary action per step; no confirm dialog on advance | `advance()`; the only confirmations are abandon and completion |
| Large targets | primary action meets docs/07's minimum tap target (≥ 48 dp equivalent; full-width on the 180×320 canvas); never two competing primaries | `StepView` exposes one primary action; the timer control is secondary |
| Step text length | instruction ≤ 180 chars, ≤ 2 sentences; must not scroll at the docs/07 body size | seeded copy; lint L2 |
| Secondary detail | ≤ 120 chars, one line if possible; never duplicates the instruction | `StepView.detail` |
| Cautions before the action | `caution` renders **above** the primary button, distinct tone, with an icon; never hidden behind a tooltip or auto-dismissed | `StepView.caution` |
| Keep screen on | while guide focused and timer `running` | `TimerState.phase` |
| Timer is optional | "Start timer" appears only when the effective duration is > 0; the step is advanceable without it | `StepView.timer.phase == idle`, effective duration |
| Never auto-advance | timer end shows `done`/`overrun`; the cook taps | `advance()` is the only mutator |
| Resume affordance | home shows a resume card for an active session; the guide shows the resume banner with `{away}`/`{ago}` | `activeSession()`, `onResume()` |
| Abandon confirmation | destructive dialog with the explicit action named; default is Cancel | `abandon(confirmed:)` guard |
| No destructive back | system back / close = leave the guide; the session stays `in_progress`. Abandon is only via the menu. Nothing is lost by backing out | no write on back |
| Honest banners | the guide-anyway banner lists what is missing and stays for the whole session; a variant banner names the appliance path | `missing_requirements_json`, pinned path |
| Review is a checklist | three big buttons per line (`Didn't use`, `Used it`, `Used it up`), one disabled with its reason (`already out`); the status chip shows `Probably have` for `unknown`; an "I have it" correction affordance per line; no keypad | `CompletionLine.allowedChoices`, `status`, `restockToHave` |
| Progress is quiet | one bar, integer percent, no animation on resume, no confetti until completion | `progressFraction` |
| Completion summary | counts of Used it / Used it up / Didn't use, plus lines corrected to `have` | `CompletionResult` |

---

## 10. Edge cases

Extends docs/02 §6; every row has an engine rule and a test id (§12).

| # | Case | Engine behavior | Persisted | Test |
|---:|---|---|---|---|
| 1 | App killed mid-timer | timer derived from `timer_started_at`; `overrun` if the deadline passed while away; step unchanged | none | T-28 |
| 2 | Timer finished while away | `overrun`, copy "you were away 4 min; timer finished 1 min ago"; no advance | none | T-23, T-28 |
| 3 | Clock moved backwards 2 h | `running`, remaining capped at duration, `clockSkewDetected`; the start instant is never rewritten | none | T-24 |
| 4 | Clock moved forward 1 h | may read `overrun`; advance still manual | none | T-25 |
| 5 | Session older than 24 h | `onResume.stale = true`; UI offers Resume/Abandon; never auto-abandons | none | T-29 |
| 6 | One-step recipe (N = 1) | start at step 1; `advance()` → review (`2`); `complete()` allowed; 0% → 100% | session | T-32 |
| 7 | Zero/negative duration in seed | normalized to null, no timer, warning; step still advanceable | none | T-01, T-27 |
| 8 | All-optional ingredient recipe | availability ignores optionals; review defaults all `didntUse`; completion writes no events | session status only | T-54 |
| 9 | Unknown stock in review | three choices; default `didntUse` writes nothing; explicit `Used it` → `unknown→low`, `Used it up` → `unknown→out` | events only on explicit use | T-38, T-39, T-40, T-44 |
| 10 | All equipment missing, guide-anyway | the cook's pick is kept as the pinned path; its unowned appliances are flagged as `equipment:*`; guide runs; review normal | session + missing list | T-07, T-53 |
| 11 | Equipment edited mid-session | pinned path unchanged; next session replans | none | T-53 |
| 12 | Second session attempted while active | `activeSessionExists` with the session; no new row | none | T-14 |
| 13 | Double completion | second call returns `alreadyCompleted`, zero writes, zero events | none | T-48 |
| 14 | Seed missing (recipe or inventory row) | `RecipeNotFound` / `SeedMissing`; no partial writes | none | T-56 |
| 15 | Killed in review (`N+1`) | resume re-opens the review; still `in_progress` | none | T-59 |
| 16 | Stock edited between review and confirm | transition is computed from the status re-read in the transaction; if the new status disables the choice (`out` + `Used it`) the completion is rejected with nothing written | events per re-read status | T-50, T-51 |
| 17 | Timer started twice | `TimerAlreadyRunning`; one notification | none | T-26 |
| 18 | Advance with a running timer | timer cleared and notification cancelled; step moves; no auto-done | timer columns null | T-15 |
| 19 | Abandon at review / at final step | allowed with confirmation; zero events | status abandoned | T-19 |
| 20 | Notification permission denied | timer still correct; no chime | none | T-57 |
| 21 | Reboot mid-timer | same as app kill | none | T-28 |
| 22 | DST transition during timer | UTC math unchanged; only labels shift | none | T-58 |
| 23 | Equipment added after guide-anyway start | pinned path and missing list unchanged (history stays honest) | none | T-53 |
| 24 | Second `start()` after abandon | allowed; new session row, new path | session | T-55 |

---

## 11. Dart structures (signatures only, no bodies, no Flutter imports)

Three pure-Dart files under `lib/domain/guide/` (matches docs/08's layout). The engine takes an injected `DateTime nowUtc` from the caller and a `GuideStore` seam; it never reads the system clock and never imports `dart:ui`, `flutter/*`, or a database package.

### 11.1 `lib/domain/guide/guide_models.dart`

Constructor stubs (`{ ... }`) stand for the obvious `const` constructor: every field is a required named parameter, in field order. No bodies are shown; the only derived member in the models is the `AvailabilityState` switch, which the UI performs itself (no `available` boolean, to keep one source of truth).

```dart
enum StepKind { prep, heat, cook, wait, finish }

enum StockStatus { unknown, have, low, out }

enum SessionStatus { inProgress, completed, abandoned }

enum TimerPhase { idle, running, done, overrun }

enum CompletionChoice { usedIt, usedItUp, didntUse }   // exactly three; docs/06 A4

enum StockEventReason { initial, restock, usedSome, usedUp, waste, correction }

enum EngineError {
  recipeNotFound, seedInvalid, activeSessionExists, availabilityBlocked,
  methodChoiceRequired, noActiveSession, sessionNotActive, stepOutOfRange,
  alreadyAtReview,
  completionIncomplete, invalidCompletionLine, abandonNotConfirmed,
  timerNotAvailable, timerAlreadyRunning, seedMissing,
}

class RecipeStep {
  final int stepNumber;
  final StepKind kind;
  final String instruction;
  final String? detail;
  final int? durationSeconds;
  final String? equipmentId;
  final List<String> ingredientIds;
  final String? caution;
  final String spriteKey;
  final String? variantGroup;
  final List<StepVariant> variants;

  const RecipeStep({
    required this.stepNumber,
    required this.kind,
    required this.instruction,
    this.detail,
    this.durationSeconds,
    this.equipmentId,
    this.ingredientIds = const <String>[],
    this.caution,
    required this.spriteKey,
    this.variantGroup,
    this.variants = const <StepVariant>[],
  });
}

class StepVariant {
  final int stepNumber;
  final String equipmentId;
  final String? instructionOverride;
  final int? durationOverrideSeconds;
  final String? spriteOverride;
  final int priority;

  const StepVariant({
    required this.stepNumber,
    required this.equipmentId,
    this.instructionOverride,
    this.durationOverrideSeconds,
    this.spriteOverride,
    required this.priority,
  });
}

class RecipeGuide {
  final String id;
  final String slug;
  final String name;
  final List<RecipeStep> steps;
  final List<String> requiredIngredientIds;
  final List<String> optionalIngredientIds;
  final List<String> requiredEquipmentIds;

  const RecipeGuide({ ... });
}

class EquipmentPath {
  final Map<int, StepVariant?> chosenVariants; // step number → variant, null = canonical
  final Map<int, String?> equipmentByStep;     // step number → appliance, null = neutral

  const EquipmentPath({ required this.chosenVariants, required this.equipmentByStep });
}

class GuidedSession {
  final String id;
  final String kitchenId;
  final String recipeId;
  final SessionStatus status;
  final int currentStepNumber;       // 1..N+1; N+1 = review
  final DateTime startedAtUtc;
  final DateTime? lastSeenAtUtc;
  final DateTime? completedAtUtc;
  final DateTime? timerStartedAtUtc;
  final int? timerDurationSeconds;
  final bool startedWithoutAvailability;
  final List<MissingRequirement> missingRequirements;
  final EquipmentPath path;

  const GuidedSession({ ... });
}

class TimerState {
  final TimerPhase phase;
  final Duration remaining;
  final Duration elapsed;
  final Duration? overdue;            // null idle/running; zero = done; > 0 = overrun
  final bool clockSkewDetected;

  const TimerState({
    required this.phase,
    required this.remaining,
    required this.elapsed,
    this.overdue,
    this.clockSkewDetected = false,
  });
}

class StepView {
  final int stepNumber;
  final int totalSteps;
  final bool isReview;               // stepNumber == totalSteps + 1
  final StepKind kind;
  final String instruction;
  final String? detail;
  final String? caution;
  final String spriteKey;
  final String? equipmentId;
  final List<String> ingredientIds;
  final bool isVariant;
  final TimerState timer;
  final double progressFraction;

  const StepView({ ... });
}

class MissingRequirement {
  final MissingKind kind;            // equipment | ingredient | variantGroup
  final String id;
  final List<String> alternatives;   // group members; empty otherwise

  const MissingRequirement({required this.kind, required this.id, this.alternatives = const <String>[]});
}

enum MissingKind { equipment, ingredient, variantGroup }

enum AvailabilityState { ready, needsConfirmation, blocked }   // docs/06 §3.2 A2

class AvailabilityResult {
  final AvailabilityState state;     // sole source of truth; do not add an `available` bool
  final bool guideAnywayAllowed;     // true whenever the recipe exists
  final List<MissingRequirement> missing;   // the chosen method's unowned equipment, `out` required ingredients
  final List<String> lowWarnings;           // required ingredients at `low`
  final List<String> confirmUnknown;        // required ingredients at `unknown`
  final EquipmentPath path;          // best-effort path, used when blocked / guide-anyway

  const AvailabilityResult({ ... });
}

class CompletionLine {
  final String ingredientId;
  final String ingredientName;
  final bool isRequired;
  final StockStatus status;          // snapshot shown in the review; re-read at commit
  final CompletionChoice choice;
  final List<CompletionChoice> allowedChoices;   // 2-3 values; `out` omits usedIt
  final bool restockToHave;          // review correction, applied before the usage transition

  const CompletionLine({ ... });
}

class StockTransition {
  final StockStatus from;
  final StockStatus to;
  final StockEventReason reason;

  const StockTransition({ required this.from, required this.to, required this.reason });
}

class StartResult {
  final GuidedSession? session;
  final GuidedSession? activeSession;
  final AvailabilityResult? blockedBy;
  final EngineError? error;

  const StartResult({this.session, this.activeSession, this.blockedBy, this.error});
}

class ResumeInfo {
  final GuidedSession session;
  final StepView? currentStep;       // null when the session is at the review sentinel
  final bool isReview;               // session.currentStepNumber == totalSteps + 1
  final TimerState timer;
  final Duration awaySince;
  final Duration? timerFinishedAgo;
  final bool stale;                  // started more than 24 h ago
  final String resumeCopy;

  const ResumeInfo({ ... });
}

class CompletionResult {
  final CompletionOutcome outcome;   // completed | alreadyCompleted | rejected
  final List<CompletionLine> lines;
  final int usedItCount;
  final int usedItUpCount;
  final int didntUseCount;
  final int restockCorrections;
  final int eventsWritten;           // 0 for `alreadyCompleted`, `didntUse`-only, or no-ops
  final EngineError? error;

  const CompletionResult({ ... });
}

enum CompletionOutcome { completed, alreadyCompleted, rejected }

class EngineException implements Exception {
  final EngineError code;
  final String? detail;

  const EngineException(this.code, [this.detail]);
}
```

### 11.2 `lib/domain/guide/guide_rules.dart` (pure functions, no state)

```dart
AvailabilityResult evaluateAvailability(
  RecipeGuide recipe,
  Set<String> ownedEquipment,
  Map<String, StockStatus> statuses, {
  Map<String, String> requestedByGroup = const <String, String>{},   // empty = per-method display states
});

EquipmentPath planPath(
  RecipeGuide recipe,
  Set<String> ownedEquipment,
  Map<String, String> requestedByGroup,   // cook's method pick per variant group; no default
);

TimerState deriveTimer({
  required DateTime? timerStartedAtUtc,
  required int? timerDurationSeconds,
  required DateTime nowUtc,
  required DateTime? lastSeenAtUtc,
  DateTime? inMemoryLastSeenUtc,
});

List<StockTransition> completionTransitions({
  required StockStatus current,
  required CompletionChoice choice,
  bool restockToHave = false,
});

bool isChoiceAllowed(StockStatus status, CompletionChoice choice);

List<CompletionChoice> allowedChoicesFor(StockStatus status);   // 3, or 2 when status == out

List<CompletionLine> defaultCompletionLines(RecipeGuide recipe, Map<String, StockStatus> statuses);

int completedSteps(int currentStepNumber, int totalSteps);

double progressFraction(int currentStepNumber, int totalSteps);

int progressPercent(int currentStepNumber, int totalSteps);
```

### 11.3 `lib/domain/guide/guide_engine.dart` (public API, signatures only)

```dart
abstract class GuidedCookingEngine {
  /// Required core surface.
  Future<StartResult> start({
    required String recipeId,
    required bool guideAnyway,
    required DateTime nowUtc,
    required Map<String, String> requestedByGroup,   // the cook's method pick; empty = no groups
  });
  Future<StepView> advance({required String sessionId, required DateTime nowUtc});
  Future<StepView> currentStep({required String sessionId, required DateTime nowUtc});
  Future<TimerState> timerState({required String sessionId, required DateTime nowUtc});
  Future<ResumeInfo> onResume({required String sessionId, required DateTime nowUtc});
  Future<List<CompletionLine>> review({required String sessionId});
  Future<CompletionResult> complete({required String sessionId, required List<CompletionLine> lines, required DateTime nowUtc});
  Future<GuidedSession> abandon({required String sessionId, required bool confirmed, required DateTime nowUtc});

  /// Supporting operations the UI needs to drive the core eight.
  Future<AvailabilityResult> checkAvailability({
    required String recipeId,
    Map<String, String> requestedByGroup = const <String, String>{},   // empty = per-method display states
  });
  Future<GuidedSession?> activeSession();
  Future<TimerState> startTimer({required String sessionId, required DateTime nowUtc});
  Future<void> clearTimer({required String sessionId});
  Future<List<CompletionLine>> setChoice({required String sessionId, required String ingredientId, required CompletionChoice choice});
  Future<void> markSeen({required String sessionId, required DateTime nowUtc});
  Future<void> onPause({required String sessionId, required DateTime nowUtc});
}
```

### 11.4 Store seam (implemented by T3's repository layer; no SQL here)

```dart
abstract class GuideStore {
  Future<RecipeGuide?> loadRecipe(String recipeId);
  Future<GuidedSession?> loadActiveSession();
  Future<GuidedSession?> loadSession(String sessionId);
  Future<void> insertSession(GuidedSession session);
  Future<void> updateStepNumber(String sessionId, int stepNumber, DateTime nowUtc);
  Future<void> writeTimer(String sessionId, DateTime? startedAtUtc, int? durationSeconds);
  Future<void> writeLastSeen(String sessionId, DateTime atUtc);
  Future<void> abandonSession(String sessionId, DateTime nowUtc);
  Future<CompletionResult> completeAtomically({required String sessionId, required List<CompletionLine> lines, required DateTime nowUtc});
  Future<Map<String, StockStatus>> statusesOf(List<String> ingredientIds);
  Future<Set<String>> ownedEquipmentIds();
}
```

`completeAtomically` is the only place with SQL; it implements §8.5 exactly and returns `alreadyCompleted` rather than throwing on a terminal session. Everything else is pure Dart and unit-testable with an in-memory fake.

---

## 12. Test cases (given / when / then)

Pure-Dart tests, no widgets, fixed clock. Phase A = fixtures + adobo; Phase B = SQLite (adds the transaction rows). Numbers are stable ids for the Phase A/B test files.

**Step model and seed lint**

| # | Given | When | Then |
|---:|---|---|---|
| T-01 | a step with `duration_seconds = 0` | recipe is loaded | duration normalized to null, `TimerPhase.idle`, no timer button |
| T-02 | a step with a 3-sentence instruction | recipe is loaded | `SeedInvalid` naming recipe, step, lint L2 |
| T-03 | a recipe whose last step is `cook`, not `finish` | recipe is loaded | `SeedInvalid` (L8) |
| T-04 | a `wait` step with null duration | recipe is loaded | `SeedInvalid` (L6) |

**Variant selection**

| # | Given | When | Then |
|---:|---|---|---|
| T-05 | dish 3, kitchen owns stovetop + air fryer, cook picks Air-fry | `start()` | step 5 is the canonical air-fry implementation, 1200 s, `isVariant == false`; pinned rows: steps 2-3 `stovetop`, step 5 `air_fryer` |
| T-06 | dish 3, kitchen owns stovetop, cook picks Pan-fry | `start()` | step 5 (the crisp step of 6) uses the `stovetop` variant: pan-fry copy, 720 s, sprite override, `isVariant == true`; `air_fryer` never appears in the pinned path |
| T-07 | dish 3, kitchen owns neither appliance, cook picks Pan-fry | `checkAvailability()` | `blocked`; missing contains `equipment:stovetop` (no group entry); `guideAnywayAllowed == true` |
| T-08 | dish 3, kitchen owns stovetop only, cook picks Air-fry | `checkAvailability()` | `blocked` with `equipment:air_fryer`; the Pan-fry variant is not offered, substituted, or pinned; Guide anyway starts the air-fry path |
| T-09 | dish 3, no method requested | `start()` | `MethodChoiceRequired`, zero rows written; `checkAvailability()` without a request reports per-method states and pins nothing |
| T-10 | adobo (no groups) with stovetop | `planPath()` | every step canonical; `isVariant == false` everywhere; an empty `requestedByGroup` is accepted |

**Session transitions**

| # | Given | When | Then |
|---:|---|---|---|
| T-11 | available adobo, no active session | `start(guideAnyway: false)` | `in_progress`, step 1, `started_without_availability == 0`, zero events, zero status changes |
| T-12 | blocked adobo | `start(guideAnyway: false)` | `blockedBy.missing` non-empty, no session row written |
| T-13 | blocked adobo | `start(guideAnyway: true)` | `in_progress`, flag 1, missing codes persisted byte-identical to `AvailabilityResult.missing` |
| T-14 | an active session exists | `start()` again | `activeSessionExists` with that session; session count unchanged |
| T-15 | session on step 2, timer running | `advance()` | step 3, both timer columns null, notification cancelled |
| T-16 | session on step N (last) | `advance()` | `current_step_number == N+1`, status still `in_progress`, progress 100% |
| T-17 | session at review | `advance()` | `AlreadyAtReview`, nothing written |
| T-18 | session in progress | `abandon(confirmed: false)` | `AbandonNotConfirmed`, status unchanged |
| T-19 | session in progress with a running timer | `abandon(confirmed: true)` | `abandoned`, timer cleared, zero stock events |
| T-20 | completed session | `advance()` / `abandon(confirmed: true)` | `SessionNotActive` both times, no writes |

**Timer derivation**

| # | Given | When | Then |
|---:|---|---|---|
| T-21 | timer started, duration 1500 s, now = start + 600 s, foreground | `timerState()` | `running`, remaining 900 s, progress unchanged |
| T-22 | timer started, duration 300 s, now = deadline, `last_seen_at = deadline` | `timerState()` | `done`, overdue zero, copy "Timer done." |
| T-23 | timer started, duration 300 s, now = deadline + 60 s, `last_seen_at` = start | `onResume()` | `overrun`, overdue 60 s, copy contains "away" and "1 min"; step unchanged |
| T-24 | timer started, now = start − 2 h | `timerState()` | `running`, remaining == duration, `clockSkewDetected`, start instant unchanged |
| T-25 | timer started, now = deadline + 3600 s (forward jump) | `timerState()` | `overrun`, overdue 3600 s |
| T-26 | a timed step | `startTimer()` twice | second call `TimerAlreadyRunning`, one notification handle |
| T-27 | a step with null duration | `startTimer()` | `TimerNotAvailable` |
| T-28 | timer running, app killed, cold start 10 min later (deadline passed) | `onResume()` | `overrun`, step unchanged, no auto-advance |
| T-29 | session started 30 h ago, timer long finished | `onResume()` | `stale == true`, timer `overrun`, status still `in_progress` |

**Progress and handoff**

| # | Given | When | Then |
|---:|---|---|---|
| T-30 | 7-step adobo on step 3 | `progressPercent()` | 28, `completedSteps == 2` |
| T-31 | 7-step adobo at review (8) | `progressPercent()` | 100, `isReview == true`, status `in_progress` |
| T-32 | 1-step recipe | `start()`, `advance()`, `complete()` | step 1 → review (2) → completed; 0% → 100% |
| T-33 | running timer on step 2 | `progressPercent()` | unchanged (no time-based credit) |

**Usage review and completion**

| # | Given | When | Then |
|---:|---|---|---|
| T-34 | required `have`, choice `usedIt` | `complete()` | status `low`, one `used_some` event `have→low` session-linked, session `completed` |
| T-35 | required `low`, choice `usedIt` | `complete()` | no event, status stays `low`, session `completed`, result notes "already low" |
| T-36 | required `have`, `usedItUp` | `complete()` | `out`, one `used_up` event `have→out` |
| T-37 | required `low`, `usedItUp` | `complete()` | `out`, one `used_up` event `low→out` |
| T-38 | required `unknown`, default choice | `review()`, `complete()` | default `didntUse`; no event; status still `unknown` |
| T-39 | required `unknown`, `usedIt` | `complete()` | `unknown→low`, one `used_some` event |
| T-40 | required `unknown`, `usedItUp` | `complete()` | `unknown→out`, one `used_up` event |
| T-41 | required `out`, submitted `usedIt` | `complete()` | choice is not allowed → `InvalidCompletionLine`, zero writes, session `in_progress` |
| T-42 | required `out`, `usedItUp` | `complete()` | no event, stays `out`, session `completed` |
| T-43 | `have`/`low`/`unknown`/`out` with `didntUse` | `complete()` | zero events, all statuses unchanged, session `completed` |
| T-44 | review with required `have`, required `low`, required `unknown`, required `out`, optional `have` | `review()` | defaults: `usedIt`, `usedIt`, `didntUse`, `didntUse`, `didntUse` |
| T-45 | `unknown` + restock correction + `usedIt` | `complete()` | two chained events `unknown→have` `restock` (session link NULL), `have→low` `used_some` (session link set); final `low` |
| T-46 | `out` + restock correction + `usedIt` | `complete()` | `out→have` `restock` (unlinked), `have→low` `used_some` (linked); final `low` |
| T-47 | session on step 3 of 7 | `complete()` | `CompletionIncomplete`, zero writes |
| T-48 | completed session | `complete()` again | `alreadyCompleted`, statuses and event count unchanged |
| T-49 | `stock_event` insert forced to fail mid-transaction | `complete()` | rollback: session `in_progress`, statuses unchanged, no events |
| T-50 | review snapshot `unknown`, stock set to `have` before confirm, choice `usedIt` | `complete()` | one `have→low` `used_some` event (re-read), no `unknown→low` |
| T-51 | review snapshot `have`, stock set to `out` before confirm, choice `usedIt` | `complete()` | `InvalidCompletionLine` (choice now disabled), rollback, zero events |
| T-52 | every (status × choice × restock) combination | `completionTransitions()` table test | exactly §8.3/§8.4: disabled `out+usedIt`, no-ops for `low+usedIt`, `out+usedItUp`, `didntUse`, and the restock chain |

**Guide-anyway and operations**

| # | Given | When | Then |
|---:|---|---|---|
| T-53 | guide-anyway start, equipment added mid-cook | `currentStep()` | pinned path and missing codes unchanged |
| T-54 | all-optional or all-unknown recipe | `complete()` | session completed, zero events |
| T-55 | abandoned session | `start()` same recipe | allowed; new session row and pinned path |
| T-56 | seed missing the recipe / an inventory row | `start()` / `complete()` | `RecipeNotFound` / `SeedMissing`, no partial writes |
| T-57 | notification permission denied | start timer, wait past deadline | timer derives `done`/`overrun`; no chime; no error |
| T-58 | timer spanning a local DST boundary | `timerState()` at deadline | remaining/overdue match UTC arithmetic exactly |
| T-59 | session at the review sentinel, app killed | cold start + `onResume()` | review re-opens, status still `in_progress`, step unchanged, no write |

59 cases; T-01 to T-33 are Phase A (fixtures, no database); T-34 to T-59 are Phase B (SQLite), except the pure transition-table test T-52, which runs in both. Each is a pure-Dart test with a fixed `nowUtc` and an in-memory `GuideStore` fake, except the transaction rows which use `sqflite_common_ffi`.

---

## 13. Decision log

| # | Decision | Alternative rejected | Why |
|---:|---|---|---|
| E1 | Five step kinds (`prep`, `heat`, `cook`, `wait`, `finish`) | Seven, including `add` and `check` | A kind must change behavior; these five drive timer/notification/caution/sprite rules. `add`/`check` only change icons. |
| E2 | Step data is authored and immutable, never composed | Runtime templates or conditional copy | Reviewable copy, truthful timers, golden tests; templates also violate L5 and recipe immutability. |
| E3 | Variants are per-step deltas with an optional variant group | One full step list per appliance combination | O(steps + variants) instead of O(paths); no copy drift, no combinatorial tests; group keeps multi-step method coherent. |
| E4 | The cook picks the method; `planPath` resolves that pick and never ranks or substitutes | Canonical-first, priority order, or best-available auto-selection (the pre-review design) | Having the app choose hid the cook's decision, so an explicit Pan-fry pick silently reverted to Air-fry at start (F-02); `priority` stays an authoring column only. |
| E5 | Path pinned at session start in `session_step_choices` | Recompute on every read | Mid-session equipment edits must not rewrite instructions or invalidate a resume. |
| E6 | Review phase is the sentinel `current_step_number = N+1` | Separate `phase` column, or complete-on-last-step | One field, no second source of truth; survives a kill in review without completing the session. |
| E7 | Timer persisted as `timer_started_at` + duration, derived on read | Persist remaining seconds and tick | Suspension-correct across background, kill, reboot; no drifting counter or double writer. |
| E8 | `done` vs `overrun` from `last_seen_at` vs deadline | A persisted "timer ended" flag or an arbitrary grace window | Derivation only; distinguishes "saw it finish" from "finished while away", which drives the resume copy. |
| E9 | `out` + "Used it" is disabled, not a silent no-op | Accept the tap as a no-op | docs/06 A4 disables it; the restock correction says "I have it" honestly, while a no-op would look like a recorded use. |
| E10 | `unknown` gets the same three choices; an explicit usage writes `unknown→low` / `unknown→out` | A fourth "Not tracked" choice, or never writing for unknown | docs/06 A4: an explicit tap is knowledge, so learning the status is correct; the default `didntUse` still writes nothing. |
| E11 | Completion transition computed from the status re-read inside the transaction | Guard against the review snapshot | A stock edit between review and confirm must not write a stale transition; if the new status disables the chosen action, the write is rejected for re-confirmation. |
| E12 | Repeated completion returns `alreadyCompleted` | Throw a conflict error | A killed process or a double tap must not show an error after a successful write; idempotent success is safer for the UI. |
| E13 | Abandon has a confirmation guard; back never abandons | Back = abandon | No destructive back navigation; leaving the guide must never lose stock or progress. |
| E14 | No partial credit for a running timer | Time-weighted progress | Timers are skippable and advisory; progress must not move without input and must be derivable from one integer. |
| E15 | Defaults: required `have`/`low` → Used it; everything else → Didn't use | Pre-tick everything as used | One tap reflects the common case; `unknown` and `out` are never upgraded by a default; optional items are usually not used. |
| E16 | `servings` stored as base yield, never read | Keep a servings picker | Locked: no scaling in the MVP; the engine has no quantity path at all. |
| E17 | Restock correction is chained before the usage transition, inside the completion transaction | Apply it immediately on the review tap | Atomic review: abandoning leaves no surprise stock, and a two-event chain records both facts. |
| E18 | Engine reasons are `used_some`, `used_up`, review `restock` only | Reuse `consume` / `adjustment` | docs/06 §3.3 retires the old names; the reason determines the legal transition, so the pair must be explicit. |

---

## 14. Files created, decisions, open questions

**Files created (this task):** `Final Project/docs/09-guided-cooking-engine.md` only. No code, no DDL, no edits to existing docs, no teammate files.

**Corrections applied (captain, turn 3):** the review has exactly three choices (`Didn't use` / `Used it` / `Used it up`) — there is no fourth "Not tracked" choice; docs/06 §3.3-§3.4 are authoritative for the reason codes and the status mapping; `unknown` defaults to `Didn't use` and an explicit usage writes `unknown→low` / `unknown→out`. Sections 3.3, 8, 10, 11, 12 and 13 were rewritten to match; §8.8 records the rejected alternatives.

**Decisions this document fixes:** five step kinds; declarative steps with three authoring limits plus loader lint L1-L13; per-step variant deltas grouped by `variant_group`; the cook's explicit method pick as the only path input, resolved per step and pinned in `session_step_choices`; `in_progress`/`completed`/`abandoned` with the `N+1` review sentinel; absolute-UTC timer derivation with `done`/`overrun` from `last_seen_at`; no auto-advance; progress = completed steps / total with no timer credit; the docs/06 three-choice usage review (`Didn't use` / `Used it` / `Used it up`), reason codes `used_some`/`used_up`/review `restock`, the restock correction chain, and the §8.3 mapping as the only source of stock events; atomic SQLite completion with three idempotency guards; 59 numbered test cases.

**Schema contract (implemented in `db/schema-sqlite.sql`; §3.6 checks it field by field):** `cooking_sessions` with `last_seen_at`, `started_without_availability`, `missing_requirements_json`, two timer columns and no upper bound on `current_step_number`; `session_step_choices`; `recipe_step_variants`; `stock_status` + `stock_event` with `from ≠ to`, the docs/06 §3.3 reason domain and pairs, usage-only session links, and the per-session usage unique index; step-model columns on `recipe_steps`; a `stock_status` row for every seeded ingredient. Two residual notes only: docs/06's `timer_step_number` is not persisted, and docs/06's `ingredient_stock` name yields to `stock_status`.

**Open questions (for T5/user):**

1. **Q1 — Dish 3 equipment seed (resolved, C4).** `recipe_equipment` for Crispy Pork Belly is **empty**; each method declares its appliance through its variant rows, and every availability read uses `checkAvailability()`/`planPath`. A stovetop-only kitchen that picks Pan-fry is `ready`; the same kitchen picking Air-fry is `blocked` with `equipment:air_fryer`. Owner for the seed: Phase C.
2. **Q2 — Amendment-vs-schema field names.** docs/06 §3.5 says the session stores `timer_step_number`; the final schema stores only the two timer fields, which is sufficient (§3.6). Confirm T5 records the deviation rather than adding a column, or add the column and the engine will populate it.
3. **Q3 — docs/04 amendment.** Adobo step 2 must split into `heat` (preheat timer) + `cook` (brown) to satisfy the one-timer/kind rules; docs/04 §5 is read-only, so record it as an amendment for the Phase C seed author (same dish, same copy split).
