Status: draft for review - Owner: domain-analyst - Depends on: docs/01-05

# Flutter Pivot: Product Scope, Locked Decisions, and Risks

**Supersedes for MVP scope:** 01 (platform and platform-dependent scope only). 01 remains the source for the problem framing and the product's intent.
**Applies changes to:** GLOSSARY.md (A10) and the headers of 02, 03, 04 (the two-line superseded-for-the-MVP banner). The replacement rule text for 02 (R1-R16), 03 (schema, data dictionary), and 04 (seed plan) is carried in §3; implementation follows it.

**Reading conventions.** `NN §k` = section k of `docs/NN-*.md`; `R<n>` = a rule id in 02 §2; `04 §8.3` = seed validation query 3. Locked decisions are `L1-L6` (§2). Proposed amendments are `A1-A10` (§3). Open items are `Q1-Q7` (§9).

**Precedence.** Where this document disagrees with 01-05, this document wins for the MVP. Rules in 02 stay in force only until the §3 replacements are applied; implementation should follow the §3 text now.

---

## 1. Pivot summary

The product keeps its domain idea and loses its server. Delivery changes from a React SPA over Express/MySQL to a Flutter app over on-device SQLite; stock changes from measured quantities to tri-state presence; availability changes from a gate to advice.

| Area | Source | Before | After | Kind |
|---|---|---|---|---|
| Problem framing | 01 §1 | three questions: what do I have, what can I cook, how do I follow it | unchanged, minus "how much of it" | survives |
| Primary persona | 01 §2 | Filipino student/home cook, phone in one hand | unchanged, minus "check stock while away from home" (offline, one device) | changes |
| Local-first dish curation | 01 §3, 04 §1 | small reviewed Filipino set, closed catalog | unchanged | survives |
| Kitchen as container | 02 §1, 03 §4.2 | kitchen belongs to a user | kitchen is the whole database; no owner | changes |
| Closed catalog | 02 R3 | users cannot create ingredients/recipes | unchanged | survives |
| Curated 5-appliance list | 02 R7, 04 §2.2 | fixed list, stovetops grouped | unchanged as data; 3 rows unused by shipped dishes | survives |
| Recipe immutability | 02 R10 | no recipe editor | unchanged | survives |
| Manual step advance | 02 R12 | cook taps next; timer is advisory | unchanged; timer state now persisted (A5) | changes |
| Consume on confirmation | 02 R13 | no stock change until review | unchanged in principle; review writes status events (A4) | changes |
| One active session | 02 R11 | one in-progress cook | unchanged | survives |
| Optional never blocks | 02 R8 | optional ingredients excluded from availability | unchanged | survives |
| No reservations | 02 §7 | session reserves nothing | unchanged | survives |
| No destructive UI | 02 R16 | no delete screens | one exception: Reset demo data (A8) | changes |
| Seed validation discipline | 04 §8 | queries gate the recipe UI | unchanged, two queries weakened (§3.8) | changes |
| Safety / data-quality stance | 04 §9 | no nutrition claims, no brand names, no external URIs | unchanged | survives |
| Platform | 01 header, 05 §1 | React + Express + MySQL | Flutter + SQLite on device | changes |
| Accounts and auth | 01 §4.1, US-01; 02 R1/R2/R15; 03 §4.1, §5 | register/login, bcrypt, cookie JWT, ownership scoping | one local kitchen profile, no login (A6) | dropped |
| Offline | 01 §5 (out of scope) | deferred | the default; no network in the MVP | changes |
| Stock model | 01 US-03/04, 02 R4/R5/R6, 03 §4.6/§4.8 | decimal balances in canonical units | tri-state status + append-only stock events (A3, A4) | changes |
| Availability | 01 §3, 02 §3 formula | hard gate; decimal sufficiency test | advisory state `ready / needs_confirmation / blocked`; Guide anyway (A1) | changes |
| Recipe quantities | 02 R9, 03 §4.10 | scaled, compared, deducted | display-only instruction text (A2) | changes |
| Serving scaling | 01 §4.3, 02 R9, 03 §4.13 `servings` | linear scaling at chosen yield | frozen at base yield, P1 deferral (A7) | dropped |
| Quantity entry + unit conversion | 01 US-03, 02 R4, 04 §2.1 | canonical units, mass/volume conversion | no numeric entry on the acceptance path (A4) | dropped |
| Consumption review | 01 US-10, 02 §5 | editable amounts, atomic decimal deduction | status choices: Didn't use / Used it / Used it up (A4) | changes |
| Ledger reconciliation | 03 §7.4 | balance = sum of signed deltas | no balance exists; ordering of events replaces it | dropped |
| Timers | 01 §10 bullet, 02 R12, 05 §3 | client-side interval, not persisted | absolute UTC start instant, derived remaining (A5) | changes |
| Multi-kitchen / sharing | 01 §5, 02 §8, 03 §11 | designed-for future | designed-for future via account sync (§4) | deferred |
| Seed content | 04 §3-4 | 45 ingredients, 12 recipes | 15 ingredients, 3 shipped + 9 designed (§5) | changes |
| Screens | 01 §6 | 10 screens including auth and servings | 10 screens, none for auth or servings (§5) | changes |
| API contract | 05 §4 | 24 endpoints | none; repository interfaces in the app | dropped |
| Success criteria | 01 §9 | decimal boundary, ownership, atomic deduction | §8 of this document | changes |
| Build phases | 05 §5 | Phase 1-4 (server, seed, cooking, polish) | rewritten by T3/T4; P0-P2 shape in §5 | changes |

**Dropped outright:** server runtime, API surface, HTTP sessions, bcrypt/JWT, MySQL for the MVP, cross-tenant authorization tests, unit-conversion helper, decimal availability boundary tests, balance/ledger reconciliation, editable consumption amounts, serving selector, adversarial security pass (05 Phase 4).

---

## 2. Settled decisions

Locked by the user. No alternatives are presented; the "residual risk" column is what remains after the decision, not an invitation to revisit it.

| ID | Decision | One-line consequence | Residual risk |
|---|---|---|---|
| **L1** | **Platform.** Flutter is the delivery target. React/Express/MySQL is set aside and is not built. | Every screen, the guide engine, and the data layer are Dart; there is no web build and no server to demo. | **Accepted rubric risk, recorded once:** 01 §10 says the course required React + a SQL database. One-line contingency: a thin REST API over MySQL can replace the repository implementations behind the same interfaces without touching screens or the guide engine. Not a blocker; not reopened. |
| **L2** | **Storage.** Offline-first, one local kitchen profile, SQLite on device. No accounts, no auth, no network in the MVP. | No onboarding friction and no auth code; the device is the source of truth and uninstalling loses everything. | Data loss on uninstall/device change; no multi-device; demo state must be resettable from inside the app. |
| **L3** | **Stock model.** Tri-state presence `unknown \| have \| low \| out`. No quantities, no decimal deduction, no unit conversion on the acceptance path. Exact quantities are a documented future tier. | Availability is a presence test, not arithmetic; stock accuracy is coarse and deliberately so. | Imprecision: the app cannot say "half a bottle left", cannot auto-deduct, and cannot scale; a cook who wants grams is unserved until P1. |
| **L4** | **Content.** Ship 3 dishes (Chicken Adobo, Sinangag, Crispy Pork Belly); design the remaining 9. | Content authoring is bounded to 3 recipes; only 2 of 5 appliances are exercised by shipped dishes. | Two equipment rows and nine dishes are documentation, not running code; 04 §8.3's coverage invariant must weaken (§3.8). |
| **L5** | **Availability is advisory.** "Guide me anyway" must exist. | A blocked recipe is still startable through an explicit, recorded decision; the product no longer promises "you can cook this now". | A cook can start a cook that cannot succeed; the demo must present this as intentional, not as a bug. |
| **L6** | **No economy.** No gold, EXP, levels, streaks, or rewards. Game feel = pixel UI + progress + timers + completion celebration. | No economy tables, no scoring, no reward logic; all "game" budget goes into art, motion, and ceremony. | The whole feel rests on pixel art and timing (risk §6 R1); there is no progression hook to fall back on. |

---

## 3. Rule amendments (A1-A10)

Status of every item in this section: **Applied for the MVP.** 02, 03, and 04 carry a "superseded for the MVP" banner in their headers, A10 is applied to GLOSSARY.md, and implementation follows this text. The pre-pivot rules stay readable only as the MySQL/React contingency record (L1).

### 3.1 A1 — R8 + R11: availability is advisory; Guide anyway exists

**Conflict.** 02 R8 defines availability as a hard precondition, and 02 R11 says "a new session may start only for an available recipe". 02 §3 turns that into a sufficiency formula, 02 §6 rejects starts with missing requirements, and 01 US-07 tests it. That gate contradicts L5 and is unimplementable without quantities (L3).

**Proposed R8 (replacement).**

> **Availability (advisory).** Availability is computed for display and never blocks an action. For a kitchen `K`, recipe `R`, and — when the recipe ships more than one method — the method `M` the cook selected:
> - `ready` — every equipment item required by `M` is owned and no required ingredient is `out`;
> - `needs_confirmation` — every equipment item required by `M` is owned, no required ingredient is `out`, and at least one required ingredient is `unknown` (shown as "probably have — confirm");
> - `blocked` — at least one equipment item required by `M` is missing or at least one required ingredient is `out`.
>
> A **missing requirement** is one required equipment item not owned or one required ingredient whose status is `out`. `have` and `low` are available; `low` additionally displays a "may run short" warning. Optional ingredients never affect availability and never appear in the missing list, whatever their status. Availability is recomputed on every read; no `cookable` flag is stored. The method `M` is always the cook's explicit pick; nothing selects it on the cook's behalf (docs/09 §4.2).

**Proposed R11 (replacement).**

> **Session lifecycle (amended).** A session is `in_progress`, `completed`, or `abandoned`; at most one session may be active. A session may be started for a recipe in any availability state. Starting a `blocked` recipe requires the explicit **Guide anyway** confirmation, which names every missing requirement and creates the session with `started_without_availability = true` and a snapshot of the missing requirement codes. Starting a `ready` or `needs_confirmation` recipe records `started_without_availability = false` with an empty snapshot; `needs_confirmation` shows an inline warning but is not a blocked start. Starting still reserves and deducts nothing (R13).

**Consequences for dependent rules.** 02 §3 (the formula in A2), 02 §5 "Start", 02 §6 row "Recipe unavailable when starting", and 01 US-07 all follow this text. `GET /api/cooking-sessions` style rejection on an unavailable recipe is removed: the only start failure is a second active session.

### 3.2 A2 — R8 (availability rule, 02 §3): `out` is missing; `unknown` is not

**Conflict.** 02 §3 and 02 §6 read `stock(K, ingredient)` as a decimal and treat a missing stock row as zero. L3 says a missing row is `unknown`, and `unknown` does not block.

**Proposed 02 §3 (replacement).**

> For kitchen `K`, recipe `R`:
>
> ```
> required_equipment(R, M) ⊆ owned_equipment(K)        // hard requirement, still enforced
> missing = { equipment required by M not owned }
>        ∪ { required ingredient I : status(K, I) = out }
> warn    = { required ingredient I : status(K, I) = low }
> confirm = { required ingredient I : status(K, I) = unknown }
> blocked  ⇔ missing ≠ ∅
> needs_confirmation ⇔ missing = ∅ and confirm ≠ ∅
> ready    ⇔ missing = ∅ and confirm = ∅
> ```
>
> Rules:
> - **`out` = missing.** A required ingredient with status `out` makes the recipe `blocked` until the cook restocks it or chooses Guide anyway.
> - **`have` and `low` = available.** `low` never blocks and always renders the warning "you may run short".
> - **`unknown` does not block.** A required ingredient with status `unknown` is flagged "probably have — confirm". The flag is a prompt, not a failure.
> - **No stock row is not zero.** No recorded stock event, or an explicit "I don't know", both mean `unknown`. Nothing is inferred from absence.
> - **No arithmetic.** There is no quantity comparison, no serving scale factor, and no unit conversion anywhere in the calculation.
> - **Optional ingredients** are excluded from all three sets.
> - **Missing requirements are returned** as a list of stable codes (`equipment:air_fryer`, `ingredient:salt`) so the UI and the session snapshot agree.

### 3.3 A3 — R4/R5/R6/R14: stock is a state, not a quantity

**Conflict.** 02 R4 stores and compares stock in canonical units; R5 keeps a balance plus a signed ledger; R6 forbids negative balances; R14 deduces each balance in one transaction. None of that survives L3: there is no balance to be negative and no decimal to deduct.

**Proposed R4 (replacement) — units are display-only.**

> **Units are display vocabulary.** Recipe lines keep a quantity and unit for the instruction text (for example "1 kg chicken thighs", "6 cloves garlic") and the cook sees them as prose. Stock is not measured, so canonical units are not compared or converted. The mass/volume/count conversion rules are retained only for the deferred exact-quantity tier (P1) and for seed authoring validation; no conversion function exists on the MVP acceptance path.

**Proposed R5 (replacement) — status plus append-only event log.**

> **Status changes only by event.** A kitchen's stock status for an ingredient changes only by writing a **stock event**. The event log is append-only: events are never updated or deleted, and a correction is a new event with reason `correction`. The current status is the `to_status` of the newest event for that kitchen and ingredient, or `unknown` when no event exists. Reason determines the legal transition:
>
> | Reason | Legal transition |
> |---|---|
> | `initial` | `unknown` → `have`/`low`/`out` (first record for that ingredient in this kitchen) |
> | `restock` | `unknown`/`out`/`low` → `have` |
> | `used_some` | `have`/`unknown` → `low` |
> | `used_up` | `have`/`low`/`unknown` → `out` |
> | `waste` | `have`/`low` → `out` |
> | `correction` | any → any, `from_status ≠ to_status` |
>
> An event whose `from_status` does not match the current status is rejected, and no event may record a no-op transition. This replaces "no zero-delta transaction": a no-op stock change is still illegal, it just has nothing to do with decimals.

**Proposed R6 (replacement) — one status, no balance.**

> **One status per kitchen and ingredient.** A kitchen has at most one current status per ingredient; the log may hold many events. There is no balance, so **no operation can produce a negative balance** — non-negativity is structurally impossible rather than validated. The duplicate-row and append-only protections move from "balance and ledger" to "unique current status and ordered event log".

**Proposed R14 (replacement) — atomic completion writes transitions.**

> **Atomic completion.** Completion writes, in one transaction: the session's `completed` status and `completed_at`, and one stock event per ingredient the cook marked **Used it** or **Used it up** where that marking changes the status (see A4 table). Each event's `from_status` must equal that ingredient's current status at commit time; a mismatch aborts the whole write. **Didn't use**, and any marking that matches the current status, write nothing. A repeated completion request must not write a second set of events. Nothing is deducted, and no amount is compared: the write is a status transition with a reason and a session link.

**What happens to the old concepts.**

| Old concept | Fate |
|---|---|
| Canonical units (R4, 03 §4.3) | Retained as catalog display metadata and seed-authoring validation; removed from comparison, conversion, and deduction. |
| Non-negative balances (R6, 03 §4.6 `quantity ≥ 0`) | Moot: `inventory_items.quantity` does not exist in the MVP. `out` is the floor of the state lattice. |
| Consumption deduction (R13/R14, 03 §7.5) | Replaced by usage events: `used_some` (`have`/`unknown` → `low`) and `used_up` (`have`/`low`/`unknown` → `out`). "Consume only on confirmation" survives unchanged in principle: no status changes until the usage review is confirmed. |
| Append-only history (R5) | Retained and strengthened: the whole stock model is now an event log. |
| Reconciliation (03 §7.4) | Replaced by an ordering check: the newest event per ingredient reproduces the stored current status, and transition pairs chain (`event.from_status` equals the previous event's `to_status`). |

**Handoff note (T3 owns the SQLite schema).** Field-level hints only, not schema text: `ingredient_stock(kitchen_id=1, ingredient_id, status)` for the current state and `stock_event(id, ingredient_id, from_status, to_status, reason, cooking_session_id NULL, note NULL, created_at)`. Session carries `started_without_availability INTEGER NOT NULL DEFAULT 0` and a missing-codes snapshot (`TEXT`, JSON array).

### 3.4 A4 — R13: completion is a status choice, not an amount

**Conflict.** 01 US-10 and 02 §5 collect "editable actual amounts" and the review defaults to a scaled estimate. With L3 there is no estimate and no amount, and 02 §6 rows ("actual amount exceeds available stock", "stock drops while a session is in progress") stop making sense.

**Proposed R13 and 02 §5 "Completion review" (replacement).**

> Every recipe ingredient appears on the usage review with exactly three mutually exclusive choices: **Didn't use**, **Used it**, **Used it up**. Optional ingredients appear too and default to **Didn't use**; a required ingredient at `have` or `low` defaults to **Used it**, and a required line at `unknown` or `out` defaults to **Didn't use**. The review shows the ingredient's current status as context, and confirming is the only action that writes usage events (R13 survives).
>
> | Status shown | **Didn't use** | **Used it** | **Used it up** |
> |---|---|---|---|
> | `have` | no event | `have → low` | `have → out` |
> | `low` | no event | no event; stays `low` (copy: "already low") | `low → out` |
> | `unknown` | no event | `unknown → low` | `unknown → out` |
> | `out` | no event | disabled (copy: "already out") | no event; stays `out` |
>
> The cook can also set any ingredient back to `have` from the review (tap the line's status tag → **I have it**, writing a `restock` event) so the post-cook state matches the kitchen. Internal reason codes remain `used_some` / `used_up`; **Used it** / **Used it up** are the only user-facing labels.

**User-facing label set (handoff to T2).** Locked here so specs and mockups agree: stock chips **Have / Low / Out / Probably have** (the last is `unknown`, with a "confirm" affordance); recipe badges **Ready / Probably have / Missing**; start button **Start cooking** (`ready`), **Start and confirm items** (`needs_confirmation`), **Guide me anyway** (`blocked`, behind a confirm sheet naming every missing requirement); review actions **Didn't use / Used it / Used it up**.

### 3.5 A5 — R12: timers are persisted as an absolute start instant

**Conflict.** 02 R12 says "timer state is not persisted", 02 §6 repeats it for app closure, and 05 §3 says the timer stops when the page closes. L2 makes suspension the normal case on a phone: a cook locks the screen mid-simmer. A non-persisted countdown is wrong after every background.

**Proposed R12 (replacement).**

> **Manual steps, persisted timers.** Steps advance only when the cook taps next. A timed step starts by writing an **absolute UTC start instant** for that step to the session (`timer_step_number`, `timer_started_at_utc`). Remaining time is always derived (`duration − (now − start)`); no decrementing counter is persisted or trusted. A timer never advances a step and never changes stock. Starting a timer on another step replaces the stored start; clearing or advancing past the step clears it. After a suspension, relaunch, or clock change, the timer renders either the correct remaining time or, if the start instant is in the past beyond the duration, **elapsed by N minutes** — it never silently resumes a stale countdown. A step's timer is advisory: the cook may advance before or after it ends.

### 3.6 A6 — R9: base yield only; scaling deferred

**Conflict.** 02 R9 scales required quantities by `chosen_servings / recipe.servings` and 01 §4.3 exposes a serving selector. With no quantities there is nothing to scale, and L3/L5 make scaling meaningless as an availability input.

**Proposed R9 (replacement).**

> **Base yield only.** The MVP cooks every recipe at its authored base yield; serving scaling is deferred to P1. Recipe quantities are display-only instruction text, so no scale factor is computed, stored, or compared. `recipes.servings` is retained as display metadata (`Base yield: 4`) and shown on the recipe detail; there is no serving selector and no scaled quantity anywhere in the app.

### 3.7 A7 — R1, R2, R15, R16: rules that assume accounts

**Conflict.** L2 removes users and auth, so 02 R1 (one kitchen per user), R2 (atomic register), and R15 (per-user access scope) have no operand; R16 (no destructive UI) collides with the demo need to reset state.

**Proposed replacements.**

> **R1 — Single on-device kitchen.** The MVP has exactly one kitchen, stored in the app's SQLite database. There is no user table, no owner column, and no cross-tenant boundary to enforce. The kitchen is identified by a non-displayed stable identifier generated at first run.
>
> **R2 — Atomic first run.** Creating the kitchen profile (display name plus equipment selection) happens in one local transaction on first launch. A partially written profile is not persisted; a failed first run leaves an empty database that retries cleanly.
>
> **R15 — No access scope (retired for the MVP).** With no accounts there is no other kitchen to reach; every read and write is in the single kitchen's scope by construction. The rule returns with accounts in the sync tier.
>
> **R16 — No destructive UI, one exception.** The MVP exposes no delete screens for ingredients, recipes, or history, and no event or session can be deleted individually. Settings offers **Reset demo data**, which deletes all stock events and sessions and restores the seeded stock statuses in one transaction, behind an explicit confirmation that names what will be lost. **Reset is blocked while a session is `in_progress`**: the app offers Resume or Abandon first and writes nothing until the session is terminal.

### 3.8 A8 — A9 — consequential edits to 03 and 04

03 and 04 are not rule files, but their statements become false and T5 will flag them if they are not recorded.

| ID | File | Current text | Proposed replacement |
|---|---|---|---|
| **A8** | 03 §4.6, §4.8, §6, §7.1, §7.4, §7.5 | `inventory_items.quantity` with `CHECK ≥ 0`; `inventory_transactions.quantity_delta`; reconciliation query | The SQLite MVP drops `inventory_items.quantity` and `quantity_delta`; §4.6 becomes a current-status table, §4.8 becomes **stock events**, §7.1 becomes the availability sets in A2, §7.4 becomes the event-order check in A3 (second table). 03 stays as the MySQL contingency design (L1) but is no longer the MVP schema. |
| **A9** | 04 §6, §8.3, §8.7 | demo kitchen quantities; "every equipment row is used by at least one recipe"; expected 4-slug availability set | §6 demo stock becomes statuses (the same ingredients, statuses only); §8.3 weakens to "every equipment row referenced by a **shipped** recipe exists, and the shipped set uses `{stovetop, air_fryer}`"; §8.7 expects exactly `{chicken-adobo, sinangag, air-fried-crispy-pork-belly}` given the demo statuses. 04's 45-ingredient/12-recipe plan stays as the design-only set. |

### 3.9 A10 — GLOSSARY.md edits (applied)

The L3 vocabulary consequence: **`Inventory transaction`** describes a signed quantity change, which no longer exists. Replacement term: **`Stock event`**. Same for the terms built on balances.

**Proposal 1 — replace the `Inventory transaction` entry.**

> **Stock event**:
> An append-only record of one ingredient's stock status changing in one kitchen, with a reason and a timestamp. The full set of stock events is the kitchen's stock history.
> _Avoid_: Inventory transaction, movement, ledger entry

**Proposal 2 — replace the `Stock level` entry.**

> **Stock status**:
> The presence state of one ingredient in a kitchen: `unknown`, `have`, `low`, or `out`. Replaces the measured stock level.
> _Avoid_: Stock level, quantity, amount

**Proposal 3 — the remaining term adjustments.**

| Existing GLOSSARY term | Proposed | Why |
|---|---|---|
| **Inventory** ("collection of stock levels") | **Stock**: the set of stock statuses for a kitchen. | No levels to collect. |
| **Canonical unit** | keep, marked **deferred tier**; add "not used for comparison in the MVP; display vocabulary only". | Units still label recipe lines. |
| **Serving yield** | **Base yield**: the serve count the recipe's instructions are written for; display-only in the MVP. | No scaling (A6). |
| **Availability** ("can be cooked now: … every required ingredient is sufficient") | **Availability**: `ready`, `needs_confirmation`, or `blocked`, computed for display; `out` blocks, `unknown` prompts, `have`/`low` are available. | A1/A2. |
| **Missing requirement** | **Missing requirement**: a required equipment item not owned, or a required ingredient whose status is `out`. | `unknown` is a prompt, not missing. |
| **Consumption** | **Usage**: the cook's report of what a dish used, expressed as a status transition (internal reasons `used_some` / `used_up`; labels **Used it** / **Used it up**), not an amount. | No amounts. |
| **Consumption review** | **Usage review**: the end-of-session screen where the cook marks each ingredient **Didn't use** / **Used it** / **Used it up**. | Same screen, new question. |
| **User** | **Kitchen profile**: the name, equipment, and stock of the single on-device kitchen; no account, no sign-in. | L2. |
| — | **Guide anyway** (new): the explicit start mode for a `blocked` recipe, which names the missing requirements and records `started_without_availability`. | L5. |
| — | **Stock event reasons** (new): `initial`, `restock`, `used_some`, `used_up`, `waste`, `correction`. | A3. |

**Banned terms in new normative text and shipped UI** (T5 can grep for them): `balance`, `quantity_delta`, `deduct`, `sign in`, `inventory transaction`, `stock level`, and any sentence that compares a stock amount to a requirement. Exempt: the §1 "before" columns, direct quotes of the superseded rules, and GLOSSARY `_Avoid_` lines — those exist precisely to name the retired model.

---

## 4. Offline kitchen profile model

What replaces users and auth: a single kitchen row and nothing else.

| Concern | MVP answer |
|---|---|
| Identity | One row, `kitchen(id = 1 CHECK)`, with `display_name` (a name the cook picks; defaults to "My Kitchen"), `kitchen_uid` (UUID generated once at first run, never displayed), `created_at`, `schema_version`, `seed_version`. |
| Auth | None. No email, no password, no token, no session cookie, no PIN. The app opens into the kitchen. |
| Ownership | Not modelled. `users`, `owner_user_id`, `cooking_sessions.user_id`, and every ownership filter are gone; 03 §4.1 and §5 are retained only as the contingency design (L1). |
| Equipment | `kitchen_equipment(kitchen_id, equipment_id)` rows over the fixed 5-row catalog, chosen on first run and editable in Settings. Equipment stays a hard requirement inside availability (A1); the only escape is Guide anyway. |
| Profile name use | Shown on Cook now and Settings; no name uniqueness, no validation beyond non-empty. |
| First-run | Name (pre-filled) + equipment checkboxes + a one-line "this stays on this phone" note. Skippable: an empty equipment selection is allowed and simply makes equipment-dependent recipes `blocked`. |
| Shared device | Out of scope: another person using the phone sees the same kitchen. There is no per-person data. |
| Data lifetime | Tied to app storage. No export in the MVP; Reset demo data (A7) is the only lifecycle action. |
| Empty state | A kitchen with zero stock events is valid: every ingredient is `unknown`, every recipe is `needs_confirmation`, and the app still works. |

**Future account/sync migration (one paragraph).** The single kitchen is the anonymous case of the future model: `kitchen_uid` and per-event stable ids give every local row an identity that survives upload, and the repository interfaces (stock, events, sessions, recipes) stay unchanged. When accounts arrive, sign-in binds the local `kitchen_uid` to a server-side user through a membership row (03 §11 becomes live again), local stock events and sessions upload idempotently by id, the server assigns a monotonic sequence per kitchen for ordering, and conflicts resolve last-writer-wins per event with the transition chain re-validated server-side. No screen or guide-engine logic changes: authentication and sync are new implementations of the existing data ports, exactly as they are in the L1 contingency.

---

## 5. MVP cut line in numbers

| Quantity | MVP | Design-only / deferred |
|---|---:|---|
| Dishes shipped | **3** | 9 |
| Ingredients | **15** | 30 (the rest of 04's 45) |
| Appliances referenced by shipped dishes | **2 of 5**: `stovetop`, `air_fryer` | `oven`, `grill`, `pressure_cooker` (seeded rows, unused) |
| Screens | **10** | — |
| Stock states | **4** | exact quantities + units (P1) |
| Stock event reasons | **6** | — |
| Cooking methods | **2** (Pan-fry, Air-fry) on 1 dish, picked by the cook, never auto-selected | methods on the remaining 9 |
| Timers | 1 per step, persisted as a start instant | background notifications (out) |
| Serving scaling factors | **0** | 1 (P1) |
| Converted units on the acceptance path | **0** | 9 (P1) |
| Auth screens / API endpoints / network calls | **0 / 0 / 0** | accounts + sync (P2) |
| Food photos | 0 | out |

**The 3 dishes and why these three.**

| Dish | Equipment | Why it ships |
|---|---|---|
| Chicken Adobo | `stovetop` | Baseline. Already authored in 04 §5 (ingredients, 6 steps, 3 timers); docs/09 §2.5 splits 04's step 2 into `heat` + `cook`, so the shipped recipe is **7 steps**. 04 calls it the reference format. |
| Sinangag | `stovetop` | Second baseline, short and cheap (2 servings, ~3 timed steps), and it exercises the raw-rice prep decision in 02 §7. A demo-friendly "quick dish" that keeps the Cook now list non-trivial. |
| Crispy Pork Belly | **methods:** `pan_fry` → `stovetop`, `air_fry` → `air_fryer`. `recipe_equipment` is **empty**: each method declares its appliance through its variant rows (docs/09 §4.3). | The method proof: the same 6 steps branch into pan-fry vs air-fry with different instruction copy, duration, and sprite on the crisp step, and the cook picks which one they are cooking. Without it, the method mechanic in T4 is untested and the equipment filter has nothing to show. |

**The 15 ingredients.** Derived from the three dishes, not chosen; every row is used by at least one shipped recipe. `R` = required, `O` = optional, `–` = absent.

| # | Ingredient | Display unit | Adobo | Sinangag | Crispy pan-fry | Crispy air-fry |
|---|---|---|---:|---:|---:|---:|
| 1 | Chicken thighs | g | R | – | – | – |
| 2 | Pork belly | g | – | – | R | R |
| 3 | Rice | g | – | R | – | – |
| 4 | Garlic | clove | R | R | O | O |
| 5 | Soy sauce | ml | R | – | O | O |
| 6 | Vinegar | ml | R | – | O | O |
| 7 | Bay leaf | pc | R | – | O | O |
| 8 | Cooking oil | ml | O | R | O | O |
| 9 | Salt | g | – | O | R | R |
| 10 | Black pepper | g | O | O | O | O |
| 11 | Sugar | g | O | – | – | – |
| 12 | Spring onion | g | – | O | O | O |
| 13 | Calamansi | pc | – | – | O | O |
| 14 | Eggs | pc | – | O | – | – |
| 15 | Banana ketchup | ml | – | – | O | O |

Notes. 15 vs 45 ingredients (−67%) and 3 vs 12 dishes (−75%). No onion, ginger, or tomato is shipped even though 04 lists them: no shipped dish needs them. Every `R`/`O` flag is **static**: the two Crispy columns are identical on purpose, because variant-scoped ingredients (cooking oil `R` for pan-fry, `O` for air-fry) are deferred to **P1** and are not part of the MVP. `Cooking oil` stays optional in both methods (§8 #13).

**Renamed.** This dish was "Air-Fried Crispy Pork Belly" in `docs/04` §4; it is now **Crispy Pork Belly** because the dish carries two methods, so the method name left the dish name. `docs/01` and `docs/04` keep the original name as the pre-pivot design record; the Flutter contract, fixtures, seed and validator all use the new name and slug `crispy-pork-belly`.

**The 10 screens.** No auth screen, no serving selector.

| # | Screen | Purpose | Replaces (01 §6) |
|---|---|---|---|
| 1 | First run / Kitchen setup | Profile name + equipment checkboxes, once | Sign in / Register + Kitchen setup |
| 2 | Cook now (home) | Recipe cards with `ready / needs_confirmation / blocked`, resume active session | Cook now |
| 3 | All recipes | Full list with the same three states and a filter toggle | All recipes |
| 4 | Recipe detail | Method picker (Pan-fry / Air-fry, nothing pre-selected), per-method availability, missing list, Guide anyway, start | Recipe detail (serving selector removed) |
| 5 | Guided cook | Step, progress, timer, abandon | Guided cook |
| 6 | Usage review | Didn't use / Used it / Used it up per ingredient, restock correction | Consumption review |
| 7 | Inventory | Tri-state list grouped by category, tap to change status | Inventory (no quantity form) |
| 8 | Ingredient detail | Current status + stock event history for one ingredient | Inventory history per ingredient |
| 9 | History | Completed and abandoned sessions, and session-linked events | History |
| 10 | Settings | Kitchen name, equipment, Reset demo data, safety note | Kitchen settings |

**Features in / out.**

| In | Out |
|---|---|
| 3 shipped recipes; 9 documented only | 12 running recipes; user-created recipes |
| Tri-state stock with append-only stock events | Decimal quantities, unit conversion, expiry, batches, barcodes |
| Advisory availability + Guide anyway | "Cook now" promise / hard gating / substitutions / "almost cookable" |
| Step engine, progress, persisted timers | Background timers, notifications, auto-advance |
| Methods (Pan-fry / Air-fry) on the pork-belly dish, chosen by the cook | Methods on every dish; recipe versioning; auto-picked methods |
| Usage review writing status transitions | Editable amounts, atomic decimal deduction, reconciliation |
| Pixel UI, celebration, 10 screens | Accounts, sync, sharing, multi-kitchen, roles |
| Settings: name, equipment, reset | Shopping list, meal plan, ratings, photos, analytics |
| Airplane-mode demo | Network, REST API, MySQL, deployment |

**Cut order when a gate fails** (apply in order, never skip a step). Triggers are phase exits, defined once in docs/08 §8: **Gate A** = Adobo end-to-end on fixtures, **Gate B** = the same flow on SQLite with fixture-vs-DB parity, **Gate C** = 3 dishes + explicit methods + celebration + history. Each row is decided at the gate named in its trigger; there are no calendar dates and no hour ceilings, because the user owns scheduling. Content freeze begins after Gate C.

| Step | Cut | Trigger (evidence-based) | Result |
|---|---|---|---|
| 0 | nothing | — | 3 dishes, 10 screens |
| 1 | Merge All recipes into Cook now with a "Ready only" toggle | Screen 3 is not demo-ready before Gate B | 9 screens |
| 2 | Drop the standalone Ingredient-detail screen; keep last-change text in Inventory | Event-list UI is not working on device before Gate B | 8 screens |
| 3 | Drop Sinangag | Its content is not authored, reviewed, and seeded at Gate B | 2 dishes |
| 4 | **1-dish fallback: Chicken Adobo only** | Method picker + method-scoped availability + method steps are not green at Gate C | 1 dish, method mechanic documented only |
| 5 | Demo on emulator plus a recorded backup run | The physical-device build is not proven at Gate C | demo survives tooling risk |

**The method hedge, recorded.** If Gate C is unhealthy, the **method picker** may be cut: ship a single pinned method path (the pan-fry path, which needs only `stovetop`) while the methods data (`recipe_step_variants`) and the engine seams (`session_step_choices`, `planPath` with a requested method) stay in place and stay tested. Cutting the picker is a presentation cut, not a re-scope: the data and the seam must still pass their tests, so the picker can return without a schema change.

Never cut: tri-state stock (L3), Guide anyway (L5), usage review, or the completion celebration (L6). Those four are the demo's thesis. Changing dishes, screens, or asset count is allowed; changing the stock model is a re-scope, not a cut.

---

## 6. Risk register (top 10)

Likelihood and impact are `L / M / H`. Signals are observable, not hypothetical.

| # | Risk | L | I | Mitigation | Early-warning signal |
|---|---|---|---|---|---|
| R1 | **Pixel-art asset cost.** Hand-drawn tiles, 15 ingredient icons, 5 appliance sprites, 3 dish headers, celebration frames; art is the whole "game feel" (L6) and is easy to under-budget. | H | H | Fix an asset list in T2 before drawing; one palette, fixed 16/32 px grid, ≤ 4-frame loops, reuse one tile set across screens; generate with Pillow at fixed sizes rather than freehand one-off art; ship static fallbacks for every animation. | Under 60% of the T2 asset list before Gate B, or any screen still using placeholder rectangles at Gate C. |
| R2 | **Tri-state imprecision.** No auto-deduction, no scaling, no amounts: statuses drift from reality, and a cook cannot express "half a bottle left". | H | M | Make the usage review mandatory and one tap per ingredient; `low` is a first-class warning, not decoration; copy states "coarse by design"; keep the deferred exact-quantity tier documented (03 §4.6 as the future) so the limitation reads as a tier, not a gap. | A tester asks "how much is left?" or tries to type a number; a demo run ends with a status that contradicts the cook's memory. |
| R3 | **Timer/background correctness.** The OS can kill or throttle the app; there is no background execution; 02 said timers are not persisted (A5 fixes the rule, not the OS). | M | H | Persist the absolute UTC start; derive remaining; render "elapsed by N min" for stale timers; keep-awake on guided cook; test force-kill + relaunch + clock change on a real phone before the demo. | Drift > 2 s after a relaunch, or a timer that shows a stale remaining time on resume. |
| R4 | **Content authoring time.** 3 recipes × ~6-8 steps + 2 variants + 15 ingredients + usage copy; 04 gives only Adobo for free. | M | H | Author in risk order (Adobo already specified → Sinangag by cloning the Adobo format → Crispy last, because it is the cut candidate); content freeze begins after Gate C (§5); no photography, no external text; one reviewer pass, not a rewrite loop. | Sinangag not seeded at Gate B; method steps still being rewritten at Gate C. |
| R5 | **Accepted rubric/platform risk.** 01 §10 requires React + SQL; the pivot ships neither React nor MySQL at runtime. | H | H | Recorded once in L1 and not relitigated: keep 03's schema/DDL and SQL as evidence of the data-model work, name the deviation explicitly in the README and report, ask the instructor before build kickoff, and hold the one-line REST+MySQL contingency behind the repository interfaces. | No instructor sign-off before Gate A, or review feedback that treats the pivot as a missing requirement. |
| R6 | **Phone-in-kitchen usability.** Wet or busy hands, one hand, glancing at the screen, screen timeout; pixel UI invites small controls. | M | H | 48 dp hit-rect minimum (56 dp for the primary action); one primary action per screen; step text ≥ 18 sp; no hidden gestures, no long-press, no hover; next-step button fixed at the bottom; keep-awake during guided cook; test with a phone at arm's length. | A tester needs two hands, 3+ taps for "next", or misses a tap; any text unreadable at arm's length. |
| R7 | **Scope creep to 12 dishes.** 04 already specifies 12 and the design-only list is tempting; each dish costs steps, variants, stock rows, and art. | H | M | Freeze the shipped set at 3 in this document; the 9 others are documentation; adding a dish requires naming the screen or feature it displaces; the cut order (§5) only moves down. | Any dish added without a matching removal; "just one more recipe" in a review comment; new ingredients appearing in seeds. |
| R8 | **Demo fragility.** State drift, a reset that does not fully reset, a script that depends on a prior run. | M | H | Reset demo data action (A7) that reseeds in one transaction; scripted demo path §7; two full dry runs from reset before the class; recorded backup run; no manual DB or file edits during the demo. | Any demo step that needs a manual fix, a second attempt, or "wait, let me restart"; reset not reproducing the exact same starting statuses. |
| R9 | **Flutter tooling and sandbox.** `flutter`/`dart` exit 1 in this environment (non-writable SDK cache); no build has been attempted; device provisioning is unproven. | M | M | Documentation-only phase: no build is promised here; T3 pins the Flutter version, package set, and minimum OS level; verify a `flutter doctor` + one-device run on a writable machine before build kickoff; keep the emulator path as the fallback (cut order step 5). | First toolchain failure blocks a member across a whole working session; no successful on-device run before Gate C. |
| R10 | **Vocabulary drift.** Docs say transaction/balance/quantity; code says event/status/have; mixing them silently reintroduces decimal thinking. | M | M | §3.9 is applied to GLOSSARY.md and 02/03/04 carry the superseded banner, so the new vocabulary is the only one in force; T5 greps for the banned list (§3.9); every new doc uses `stock event`, `stock status`, `usage review`; a one-line vocabulary note at the top of T2/T3/T4 outputs. | A spec sentence contains "balance", "deduct", or "quantity" as a stock verb; two documents name the same column differently. |

---

## 7. Class demo script (2:30)

Demo profile: **Maria's Kitchen**, equipment `stovetop` + `air_fryer`. On a fresh install, complete or skip setup once so the demo kitchen exists, then Settings → **Reset demo data** (A7). Starting statuses: chicken `have`, pork belly `have`, rice `have`, garlic `have`, soy sauce `have`, vinegar `have`, **bay leaf `out`**, cooking oil `have`, salt `have`, pepper `have`, sugar `have`, spring onion `low`, calamansi `unknown`, eggs `have`, banana ketchup `unknown`.

| # | Time | Shown | Said |
|---|---|---|---|
| 1 | 0:00 | App opens on Cook now, pixel header, three recipe cards each with a state chip | "One phone, one kitchen, no login — it opens where the cook left off." |
| 2 | 0:10 | Inventory: tri-state chips — garlic `have`, spring onion `low` (warning), vinegar `have`, calamansi "probably have — confirm", bay leaf `out` | "There are no grams to type. Four states: unknown, have, low, out. Low warns, unknown asks, out blocks." |
| 3 | 0:30 | Tap the pork belly card → **COOKING METHOD** with **NO DEFAULT**: nothing pre-selected, both Pan-fry and Air-fry carry their own availability badge (both **Ready** in the demo kitchen, so no badge flips), and the requirement panel + footer copy change per pick (**Starts on the Pan-fry method.** / **Starts on the Air-fry method.**). Start **Pan-fry**. | "One dish, two appliances, two ways to crisp it. The app never picks the method for me — my pick is pinned for the whole cook." |
| 4 | 0:50 | The guide opens on **Pan-fry method**, step 1 of 6. Continue to step 5: the copy is the sear ("fry the pork belly skin-side down") with its **12:00** timer (tap the ring to start it); note that Air-fry would show the air-fry copy and its **20:00** timer. Close → **Abandon cook** (no stock changes). | "Same six steps, a different crisp step per method — copy, duration and sprite all follow the pinned pick. Abandoning writes nothing." |
| 5 | 1:05 | Back, open Chicken Adobo → amber panel: missing **Bay leaf `out`**; primary button reads **Guide me anyway**; tap it → confirm sheet names the missing item → start | "Availability is advice, not a wall. If the cook knows better, the app records that they started without the item — it does not argue." |
| 6 | 1:20 | Guided cook step 2/7, progress bar, tap the ring to start the 8:00 timer; lock the screen, wait ~15 s, unlock → the guide returns to the same step with the timer still running and its remaining time intact | "The timer stores the start instant, not a countdown — locking the phone doesn't lose time, and it never advances the step by itself." |
| 7 | 1:45 | Advance to the final step → Usage review: each ingredient offers **Didn't use / Used it / Used it up**, with required `have`/`low` lines already at **Used it**; mark chicken **Used it up**, garlic **Used it**, show bay leaf **already out** (Used it disabled, announced "Used it, already out"), tap bay leaf's **I have it** chip → **Out → Have** restock, then leave its choice at **Didn't use** | "This is the only moment stock changes: one confirm, no keyboard. The defaults already say what I used; I only correct what matters — chicken is gone, garlic is low, and the bay leaf was in the cupboard after all." |
| 8 | 2:05 | Confirm → celebration (dish stamp, 100% progress, the usage counts, "Back to Cook now") → Inventory now shows chicken `out`, garlic `low`, bay leaf `have` (the restock), every other required `have` line down to `low` | "The stock log is append-only, so the kitchen can always answer 'what did I do to this?' — no edits, no undo, just events." |
| 9 | 2:20 | History → **Sessions**: the completed Adobo row with its linked stock events; then **Stock events**: the same events plus the unlinked review restock row (bay leaf `Out → Have · restocked`, marked "review note (no cook link)") | "Session, events and status all move in one transaction. Close the app mid-cook and it comes back to the same step." |
| 10 | 2:27 | Back to Cook now | "No accounts, no network, no quantities. The bet is that coarse-but-honest beats precise-but-stale — and that's the pivot." |

Fallback if the method step (4) or timer step (6) misbehaves: show the pre-recorded run and continue from step 7. Never cut steps 3 and 7 — the cook's method pick and the used-it/used-it-up review are the two claims the demo exists to prove.

---

## 8. Testable MVP success criteria

Each row is pass/fail by observation or by a counted assertion; none of them needs a running server.

| # | Criterion | Pass test |
|---|---|---|
| 1 | Cold start needs no account | Fresh install reaches Cook now with a kitchen profile (name + equipment) in ≤ 60 s; no email, password, or PIN field exists anywhere. |
| 2 | `out` blocks, but only as advice | With bay leaf `out`, Adobo renders `blocked` with `ingredient:bay_leaf` in the missing list, and the primary action is Guide anyway. |
| 3 | `unknown` does not block | With every required ingredient `unknown`, each shipped recipe renders `needs_confirmation` with "probably have — confirm"; no recipe is `blocked` on ingredient status alone. |
| 4 | `have`/`low` never block | With all required ingredients `have` or `low`, all shipped recipes render `ready`; `low` also shows the "you may run short" warning. |
| 5 | No numeric stock entry on the acceptance path | Inventory, usage review, and recipe detail contain zero numeric input fields; the only numbers are read-only display strings inside instruction text. |
| 6 | Guide anyway is recorded | Starting a `blocked` recipe writes exactly one session with `started_without_availability = true` and the missing codes as a snapshot; starting a `ready` recipe writes `false` with an empty snapshot. |
| 7 | Usage review is a status choice | Each ingredient accepts exactly one of {Didn't use, Used it, Used it up} and writes at most one event: `have`+Used it → `have → low`; `have`/`low`+Used it up → `* → out`; `unknown`+either → `unknown → low`/`out`; `low`+Used it and `out`+Used it up → no event, status unchanged; `out`+Used it is disabled. No amount is ever read or written. |
| 8 | Append-only log | No code path updates or deletes a stock event; a correction writes a new event; the event count only decreases through Reset demo data. |
| 9 | Completion is atomic | Injecting a failure mid-write leaves zero new events and the session still `in_progress`; a successful completion writes session + all usage events together. |
| 10 | No double completion | A second completion request writes zero events and does not change the event count. |
| 11 | Abandon is inert | Abandoning writes zero stock events and marks the session `abandoned`. |
| 12 | Timer survives suspension | Start a 25:00 timer, force-kill the app, relaunch after 60 s: remaining is 24:00 ± 2 s and the step number is unchanged; the timer never advances the step. |
| 13 | Methods are real and scoped | For Crispy Pork Belly, the Pan-fry and Air-fry methods differ in instruction text, duration, and sprite on the crisp step; the ingredients are identical (cooking oil optional in both, no variant-scoped requirement anywhere); the copy of the method the cook did not pick is never shown and its appliance never enters the missing list. Variant-scoped ingredients are P1. |
| 14 | Equipment stays hard inside advisory availability | With `stovetop` unowned and Pan-fry chosen, the recipe is `blocked` with `equipment:stovetop` in the missing list; with `air_fryer` unowned and Air-fry chosen, `blocked` with `equipment:air_fryer`. Neither choice is silently swapped for the other, and Guide anyway still starts either. |
| 15 | Offline | The full demo script passes in airplane mode with zero network calls observed. |
| 16 | Reset reproduces the demo | Reset demo data restores the exact starting statuses in ≤ 5 s and the demo script replays identically twice in a row. |
| 17 | Vocabulary | Shipped UI and new normative text (docs 06-09 §3/§5/§7/§8, specs) contain none of `balance`, `quantity_delta`, `deduct`, `sign in`, `inventory transaction`, `stock level` — except in quoted "before" text and `_Avoid_` lines (see §3.9 scope note). |
| 18 | Design-only claims are honest | README/docs state 3 shipped dishes and 9 designed-only; no screen or seed exposes a 10th recipe. |

---

## 9. Files, decisions, open questions

**Files created.** `Final Project/docs/06-flutter-product-scope.md` (this file). No existing file was modified at authorship time; `db/schema.sql` and `db/seed-reference.sql` remain untouched.

**Owner pass (applied after review).** GLOSSARY.md was edited (A10) and 02, 03, and 04 gained the two-line "superseded for the MVP" banner under their headers. docs/01 and docs/05 are untouched.

**Key decisions recorded.** L1 Flutter over Flutter+server; L2 one offline kitchen; L3 tri-state presence; L4 three dishes with the pork-belly variant as the mechanic proof; L5 advisory availability with Guide anyway; L6 no economy. Amendment package A1-A10 (§3) is the implementation contract and is now applied to the normative record (02/03/04 banner, A10 in GLOSSARY). The 15-ingredient set and the 10-screen list in §5 are the MVP boundary; the cut order in §5 is the only sanctioned way to shrink it.

**Open questions for the user.**

| # | Question | Why it matters | Default if unanswered |
|---|---|---|---|
| Q1 | Does the instructor accept Flutter + SQLite in place of React + MySQL, and by when is that confirmed? | L1's residual risk (R5) is the only accepted risk; a "no" moves the build to the API contingency. | Keep the pivot; record the deviation in the README and report. |
| Q2 | Does Guide anyway also cover **missing equipment**, or only missing ingredients? | A1 applies it to both; if equipment must stay hard-gated, the confirm sheet and the missing-list copy change. | Cover both (as written in A1). |
| Q3 | Should the equipment picker show all 5 appliances (3 with "no dishes yet") or only the 2 the shipped dishes use? | A 5-row picker is future-proof; a 2-row picker is honest and makes the demo smaller. | Show all 5, mark the unused three as "no dishes yet". |
| Q4 | Is `low` ever degraded by time or a heuristic, or only by the cook's explicit usage-review choice? | A3/A4: the only writer is the cook's review choice (`have` + **Used it** → `low`); time- or heuristic-driven decay would be a hidden quantity model. | transitions are driven only by the cook's explicit usage-review choice; no time-, heuristic-, or background-driven degradation |
| Q5 | Is the one destructive exception (Reset demo data, A7) acceptable given 02 R16 / 01 §5? | The demo needs a repeatable reset (R8); otherwise the same effect needs a dev-only debug path. | Accept the single exception, confirmation-gated. |
| Q6 | Is the demo on a physical Android phone or an emulator? | Timer/relaunch (criterion 12), keep-awake, and risk R3/R9 depend on it. | Physical phone, emulator plus recording as fallback. |
| Q7 | Do the 9 designed-only dishes stay in the repo as a plan (04 §4) or get trimmed to a one-paragraph backlog? | Affects whether 04 is amended (A9) or left as the design record. | Keep them in 04 as designed-only; trim only the ingredient list to what the 3 dishes need. |
