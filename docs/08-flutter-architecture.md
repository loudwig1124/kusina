# Flutter Architecture and SQLite Data Layer

**Status: draft for review - Owner: flutter-architect - Depends on: docs/01-05, docs/06 (proposed)**

**Target:** Flutter 3.47.5 stable (Android/iOS phone, installed and verified), offline-only. **Schema:** [`db/schema-sqlite.sql`](../db/schema-sqlite.sql). **UI:** [`docs/07-pixel-ui-spec.md`](07-pixel-ui-spec.md). **Engine:** [`docs/09-guided-cooking-engine.md`](09-guided-cooking-engine.md).

**Precedence.** [`docs/06-flutter-product-scope.md`](06-flutter-product-scope.md) §2 L1-L6 and §3.2-3.4 are the authoritative MVP decisions. This document owns the Flutter stack, package layout, SQLite DDL, repository contracts, fixture strategy, testing, and phases. `docs/01-05` remain the design record and the MySQL contingency (L1); they are not the runtime architecture. Where this document and `docs/09` name the same persistence field, the DDL here is normative; `docs/09` is normative for engine behavior.

**Captain correction applied (turn 3).** The stock-event reason enum is `initial | restock | used_some | used_up | waste | correction`; `consume` and `adjustment` are rejected. The locked table names are `stock_status` (current state) and `stock_event` (append-only ledger). `docs/06`'s handoff note suggested `ingredient_stock`; this package uses `stock_status` for GLOSSARY alignment. `stock_event` has no `kitchen_id` because there is exactly one local kitchen.

---

## 1. Locked decisions and what they force

| ID | Decision | Architectural consequence |
|---|---|---|
| L1 | Flutter is the delivery target; React/Express/MySQL is not built. | One Dart codebase, no server, no API client, no auth. The MySQL DDL stays as the documented contingency; the repository interfaces are the swap seam. |
| L2 | Offline-first, one local kitchen, SQLite on device, no accounts/network. | The database file is the source of truth; no sync, no login screens. Uninstall loses data; Reset demo data is the only destructive action (`docs/06` A7). |
| L3 | Tri-state presence `unknown \| have \| low \| out`; no quantities, no conversion, no deduction on the acceptance path. | `stock_status.status` is the only stock field. Availability is a presence test. `recipe_ingredients.quantity`/`unit_id` are display-only prose. |
| L4 | Ship 3 dishes: Chicken Adobo, Sinangag, Crispy Pork Belly; 15 ingredients. | Fixtures and seed contain exactly these; 9 designed-only dishes stay in `docs/04`. Dish 3 is the variant proof (pan-fry vs air-fry). |
| L5 | Availability is advisory; "Guide me anyway" must exist. | A blocked recipe is startable with `started_without_availability = 1` and a persistent missing-code snapshot. Availability is never a gate. |
| L6 | No economy. | No gold/EXP/streak tables, no scoring services. Game feel is pixel UI, progress, timers, and one completion celebration. |

Screens: the 10 locked screens in `docs/06` §5 (`docs/07` §6); `All recipes` and `Ingredient detail` are P1, the rest are P0. No auth screen, no serving selector, no numeric stock entry.

---

## 2. Stack decisions

### 2.1 Flutter channel and version

| Item | Decision | Rationale / evidence |
|---|---|---|
| Channel | `stable` only | The course demo needs a boring, reproducible toolchain; beta/main are not acceptable for a graded build. |
| Version | **Flutter 3.47.5** | Verified on the installed stable SDK by running `./tool/fv --version`: Flutter 3.47.5 stable (rev 6a19cca564), Dart 3.13.4, DevTools 2.60.0, engine af7e796e16. The 3.50.0 research target was not the installed stable release; the scaffold runs on 3.47.5 and this architecture assumes it. |
| Platforms | Android phone (primary demo) + iOS phone | `docs/06` Q6 defaults to a physical Android phone; iOS is kept buildable but is not the demo target. No web/desktop in P0. |
| App root | `Final Project/` (pubspec, `lib/`, `test/`, `assets/`, platform folders) | Keeps `docs/` and `db/` as shared design artifacts; `db/schema-sqlite.sql` is bundled as an asset so the CLI and the app validate the same file. |
| Orientation | Portrait only in P0 | `docs/07` §1.3; avoids a second art-layout pass. |

The toolchain is documented, not exercised, in this sandbox: `flutter` exits 1 here, so this phase produces no build. On a writable machine, `flutter doctor -v` must pass and the version must be recorded before Phase A starts.

### 2.2 SQLite access: `drift` vs `sqflite`

| Criterion | `drift` | `sqflite` | Winner for Kusina |
|---|---|---|---|
| Typed queries | Generated typed tables, joins, companions | Raw `Map<String, Object?>` rows + hand mappers | drift on typing, but the app has 15 tables and ~10 queries |
| Migrations | Schema versioning helpers, migration steps, schema verifier | Hand-written `onConfigure`/`onCreate`/`onUpgrade`, `PRAGMA user_version` | drift on tooling; sqflite is enough for one v1 schema + one P1 migration |
| Codegen cost | `build_runner` + generated files on every schema change | None | **sqflite** |
| SQL visibility for a school rubric | DSL/generated code hides the SQL | Raw SQL in `migrations.dart` and repositories; the DDL is executable evidence | **sqflite** |
| Testability | `sqflite_common_ffi` possible | `sqflite_common_ffi` first-class | tie |
| Native dependency | `sqlite3_flutter_libs` bundles a modern SQLite | Uses the platform SQLite (Android ≥ 3.8 needed for partial indexes; satisfied by minSdk 24) | sqflite slightly lighter |
| Runtime footprint | ORM layer + generated code | Thin plugin + mappers | **sqflite** |

**Decision: `sqflite` + hand-written mappers.** Rationale: the rubric grades the SQL, the schema is small, and codegen adds a build step with no product payoff. The migration path is one file and two DB-version bumps. Rejected: `drift` (codegen cost and hidden SQL), raw `sqlite3` FFI (platform setup for no gain), `sembast`/JSON file (loses relational constraints, which are the point of the project).

### 2.3 State management

**Decision: no state-management package.** Each feature has a `ChangeNotifier` controller; an `AppScope` `InheritedWidget` exposes the composition root (repositories + pure services + controllers). Rebuilds use `AnimatedBuilder`/`ValueListenableBuilder`. Resume hooks use one `AppLifecycleListener` in `lib/app/lifecycle.dart`. A fixed-clock function (`DateTime Function() nowUtc`) is injected into the engine and controllers for tests.

| Need | How it is met |
|---|---|
| Async reads | Controller exposes `LoadState<T> { idle, loading, ready, error }`; `load()` is async and updates state once |
| Resume correctness | `AppLifecycleListener` calls `guideController.onPause/onResume`; engine derives the timer; no timer ticker in the widget |
| Testability | Controllers take repository interfaces + `nowUtc` in the constructor; no `BuildContext`; testable in `flutter test` |
| Cross-screen state | `AppScope` is the only way a widget obtains a controller/repository; no globals |
| Ceremony | ~30 lines of scope plumbing, one familiar pattern for the rubric |

Rejected: **Bloc** (event/state classes for 7 flows, pure overhead), **Riverpod** (new mental model + provider graph for a 3-dish app), **provider** (a package to do what one `InheritedWidget` does), **GetX** (service locator + hidden magic), **setState-only** (cannot share an active session across tabs).

### 2.4 Navigation: `go_router` vs Navigator 2.0

| Criterion | `go_router` | raw Navigator 2.0 |
|---|---|---|
| Route table | Declarative, one file, path/query params | `RouterDelegate` + `RouteInformationParser` + `RouterConfig` by hand |
| Deep-ish links / restore | Path routes, redirects, query params (`/recipes/:slug?method=pan_fry`) | Custom parsing and URL state |
| Boilerplate | ~80 lines for 10 screens + a tab shell | ~150+ lines and easy to desync |
| Dependency | Official Flutter-team package | none |
| Fit | 10 screens, one shell, one setup redirect | overkill without URL requirements |

**Decision: `go_router`.** Routes: `/setup`, `/` (Cook now), `/recipes`, `/recipes/:slug`, `/guide/:sessionId`, `/guide/:sessionId/review`, `/stock`, `/stock/:ingredientCode`, `/history`, `/settings`. A `ShellRoute` draws the Cook/Recipes/Stock/History tab bar. The router redirects to `/setup` when the kitchen profile is missing; resume is a Cook-now card, not an automatic redirect (avoids navigation loops mid-cook). Rejected: raw Navigator 2.0 (boilerplate, no benefit), Navigator 1.0 pushes (no declarative route table, harder widget tests), `auto_route` (codegen for 10 routes).

### 2.5 Flutter vs Flame, and the pixel-rendering layer

**Decision: plain Flutter widgets, no Flame.** The app is a form/list/step application: text input, long scroll, accessibility, routing, and platform plugins are core requirements. Flame is a game engine with its own game loop and rendering model; nothing here needs physics, collision, sprite batching, or a 60 fps world update. `docs/07` already specifies the whole visual layer as `CustomPainter`/`AnimationController` + a `PixelCanvas` widget. There is no cited evidence that Flame is required; adding it would create a second lifecycle and render path beside Flutter's text layer.

`docs/07` §1-§3 is normative for the pixel layer. Architecture points only:

| Concern | Decision |
|---|---|
| Canvas | 180 × 320 art units; art layer only, centred; dp text layer above it |
| Scale | `k = max(1, floor(screenWidthPx / 180))` device px per art unit; integer only; no `FittedBox`, no fractional `Transform.scale` |
| Sampling | `FilterQuality.none` for every art image; pixel-snapped `Offset((au * k) / dpr, ...)`; `RepaintBoundary` around the art layer |
| Text | Real system sans for all prose (≥ 18 sp, line height ≥ 1.35); 5×7 bitmap atlas only for chrome (headings, labels, badges, buttons, numerals); `MediaQuery.textScaler` respected up to 1.3× then clamped, frame grows not font |
| Assets | Flat PNGs in `assets/pixel/` from the `docs/07` §11.3 manifest; no @2x/@3x, no network fonts; generated by `design/mockups/generate.py` |
| Widgets | `lib/ui/pixel/`: `PixelCanvas`, `PixelPanel` (9-slice), `PixelButton`, `PixelChip` (status), `PixelProgress`, `PixelRing`, `PixelSprite`, `PixelText` (bitmap atlas) |
| Motion | One `AnimationController` per guide card; timer ring redraws once/second; reduce-motion skips slides/scales (`docs/07` §10) |

Rejected: Flame (no game loop needed; accessibility/text/routing stay simpler in widgets), a single `FittedBox` scale (fractional, blurry), SVG/vector pixel art (fractional rendering), one sprite per step (asset budget explicitly rejected in `docs/07` §11.4).

### 2.6 Packages and platform services

Versions are resolved with `flutter pub add` at scaffold and pinned by `pubspec.lock`; no version is guessed in this document.

| Concern | Choice | Phase | Why / rejected alternative |
|---|---|---|---|
| DB | `sqflite` | A/B | §2.2. Rejected `drift`, `sembast`. |
| DB tests | `sqflite_common_ffi` (dev) | B | Real SQLite in `flutter test`; same DDL. |
| DB path | `path`, `path_provider` | B | App-private DB directory; no hard-coded paths. |
| Routing | `go_router` | A | §2.4. |
| Screen wake | `wakelock_plus` | A | `docs/07` §9.6 + `docs/09` §6.6: keep awake only while guide focused and timer running. Rejected: manual platform channel. |
| Local notifications | `flutter_local_notifications` + `timezone` | P1 (Phase D, optional) | One-shot "timer done" notification when the app is backgrounded; **never correctness-bearing** (`docs/09` §6.5: denied permission is not an error, delivery may be late). Rejected: push/FCM (no network), background isolate timers (battery/OS-killed), a notification package for every SFX. |
| Sound | `audioplayers` | P1 (Phase D, optional) | Short SFX from `docs/07` §10; mute toggle in Settings. Rejected: `just_audio` (music streaming overkill). |
| Haptics | Flutter `HapticFeedback` (SDK) | A | `docs/07` §9.6 light/medium/heavy cues; no package. |
| UI settings | `shared_preferences` | P1 | Mute toggle / motion preference only; **never** domain state (stock, sessions, events live in SQLite). |
| JSON | `dart:convert` + hand mappers | A/B | No `json_serializable`/`freezed`; fixture and row shapes are small. |
| Clock | injected `DateTime Function() nowUtc` | A | Deterministic engine tests; no clock package needed. |

Not added: HTTP client, auth, FCM, analytics, ad SDK, ORM, state-management package, i18n package (English UI; Tagalog is P1 copy, not a runtime translator).

### 2.7 OS baselines and platform setup

- Android `minSdk` 24 (verify against the installed SDK's defaults; the scaffold now exists); SQLite ≥ 3.8 is required for partial unique indexes. No exact-alarm guarantee (Android 12+ restrictions are explicitly tolerated).
- iOS deployment target: whatever `flutter create` selected at scaffold; record it. Notifications permission requested only when the P1 notification path is enabled.
- Android manifest work in Phase A/D: notification permission (P1), no internet permission is needed for MVP (offline claim), orientation portrait.
- Haptics/wakelock need no runtime permission.

---

## 3. Package layout

Flutter project root is `Final Project/`. Feature-first; layer rules are enforced by review, not by a tool.

```text
Final Project/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart                 # MaterialApp.router + theme
│   │   ├── app_scope.dart           # InheritedWidget: dependencies + controllers
│   │   ├── di.dart                  # composition root; the ONLY fixture <->
│   │   │                            # SQLite swap point
│   │   ├── router.dart              # go_router table + setup redirect
│   │   ├── lifecycle.dart           # AppLifecycleListener -> guide pause/resume
│   │   └── services/
│   │       ├── wake_lock_service.dart
│   │       ├── notification_service.dart   # P1 / Phase D only
│   │       └── sound_service.dart          # P1 / Phase D only
│   ├── domain/                      # PURE DART: no flutter, no sqflite, no I/O
│   │   ├── models/
│   │   │   ├── kitchen.dart
│   │   │   ├── catalog.dart          # Ingredient, Equipment, Unit
│   │   │   ├── stock.dart            # StockStatus, StockReason, StockEvent
│   │   │   └── recipe.dart           # RecipeDetail + display lines
│   │   ├── guide/                    # docs/09 owns these three files
│   │   │   ├── guide_models.dart
│   │   │   ├── guide_rules.dart
│   │   │   └── guide_engine.dart
│   │   ├── rules/
│   │   │   ├── availability_service.dart
│   │   │   └── stock_rules.dart      # reason/transition legality for manual edits
│   │   └── ports/
│   │       ├── wake_lock_port.dart
│   │       ├── timer_notification_port.dart  # P1
│   │       └── sound_port.dart               # P1
│   ├── data/
│   │   ├── db/
│   │   │   ├── app_database.dart      # open, PRAGMAs, DDL asset, seed hook
│   │   │   ├── migrations.dart        # v1 DDL load + P1 migration functions
│   │   │   ├── mappers.dart           # row <-> model; int id <-> stable code
│   │   │   └── schema_asset.dart      # asset key constant for db/schema-sqlite.sql
│   │   ├── repositories/              # contracts (pure Dart) + implementations
│   │   │   ├── recipe_repository.dart
│   │   │   ├── stock_repository.dart
│   │   │   ├── equipment_repository.dart
│   │   │   ├── kitchen_repository.dart
│   │   │   ├── session_repository.dart
│   │   │   ├── guide_store.dart       # docs/09 §11.4 seam
│   │   │   ├── fixture/               # Phase A; pure Dart bundle + repos
│   │   │   └── sqlite/                # Phase B; sqflite implementations
│   │   ├── seed/
│   │   │   ├── seed_loader.dart       # seed/version/reset contract
│   │   │   └── seed_source.dart       # fixture JSON -> rows (single source)
│   │   └── fixtures/                  # content source (JSON, app assets)
│   │       ├── ingredients.json
│   │       ├── equipment.json
│   │       ├── recipes.json
│   │       └── kitchen.json
│   ├── features/                      # widgets + ChangeNotifier controllers
│   │   ├── kitchen/                   # first run, kitchen name/equipment modal
│   │   ├── recipes/                   # cook now, all recipes, detail, variant picker
│   │   ├── guide/                     # guided cook, usage review, celebration
│   │   ├── stock/                     # inventory, ingredient detail
│   │   ├── history/                   # sessions + session-linked events
│   │   └── settings/                  # name, equipment, reset demo, safety note
│   └── ui/pixel/                      # docs/07 widget kit (no repositories)
├── assets/
│   ├── pixel/                         # flat PNGs: backgrounds, 7 step sprites,
│   │                                  # dish stamps, equipment icons, mascot, frames
│   ├── font/                          # bitmap 5x7 atlas + glyph metrics (chrome only)
│   └── sfx/                           # P1 short SFX, licence in assets/README
├── test/                              # mirrors lib/; see §7
├── db/schema-sqlite.sql               # design artifact AND bundled schema asset
├── docs/                              # 01-09 (read-only except 08)
└── design/mockups/                    # mockups + generator (docs/07 deliverable)
```

**Layer rules**

1. `lib/domain/**` is pure Dart: no `package:flutter`, no `package:sqflite`, no `dart:io`, no `rootBundle`. It may use `dart:async`, `dart:convert`, `dart:math`.
2. `lib/data/repositories/*.dart` contracts are pure Dart too; only `sqlite/` imports sqflite.
3. Widgets never execute SQL and never construct repositories; they read through controllers and `AppScope`.
4. `lib/app/di.dart` is the only file that names a concrete repository set. Nothing else imports `repositories/fixture/` or `repositories/sqlite/` except tests and `di.dart`.
5. `lib/ui/pixel/**` is presentation-only: no data imports, no navigation decisions beyond callbacks.

### 3.1 Phase A file list (exact)

`[P]` = pure Dart, unit-testable with no widgets/DB; `[F]` = Flutter/widget/file-system dependent. Phase A is the fixture-backed vertical slice; `[B]` files are created in Phase B.

| Path | Kind | Purpose |
|---|---|---|
| `lib/main.dart` | F | `runApp`; binding init; load fixtures; build root |
| `lib/app/app.dart` | F | `MaterialApp.router`, pixel theme, `AppScope`, lifecycle |
| `lib/app/app_scope.dart` | F | Inherited dependencies + controllers |
| `lib/app/di.dart` | F | **Swap point**: fixture repositories → SQLite repositories |
| `lib/app/router.dart` | F | 10 routes + tab `ShellRoute` + setup redirect |
| `lib/app/lifecycle.dart` | F | pause/resume hooks to `GuideController` |
| `lib/app/services/wake_lock_service.dart` | F | `wakelock_plus` port implementation |
| `lib/domain/models/kitchen.dart` | P | `Kitchen` (uid, name) |
| `lib/domain/models/catalog.dart` | P | `Ingredient`, `Equipment`, `Unit` |
| `lib/domain/models/stock.dart` | P | `StockStatus`, `StockReason`, `StockEvent`, `StockEventDraft` |
| `lib/domain/models/recipe.dart` | P | `RecipeDetail`, `RecipeLine` (display quantities) |
| `lib/domain/guide/guide_models.dart` | P | Per `docs/09` §11.1 |
| `lib/domain/guide/guide_rules.dart` | P | Per `docs/09` §11.2 (`evaluateAvailability`, `planPath`, timer, completion, progress) |
| `lib/domain/guide/guide_engine.dart` | P | Per `docs/09` §11.3 |
| `lib/domain/rules/availability_service.dart` | P | Batch facade over `evaluateAvailability` for recipe lists |
| `lib/domain/rules/stock_rules.dart` | P | Manual-edit reason mapping, legal transitions, no-op detection |
| `lib/domain/ports/wake_lock_port.dart` | P | `enable()` / `disable()` |
| `lib/domain/ports/timer_notification_port.dart` | P | P1 interface only |
| `lib/domain/ports/sound_port.dart` | P | P1 interface only |
| `lib/data/repositories/recipe_repository.dart` | P | Contract |
| `lib/data/repositories/stock_repository.dart` | P | Contract; task-required methods |
| `lib/data/repositories/equipment_repository.dart` | P | Contract |
| `lib/data/repositories/kitchen_repository.dart` | P | Contract (supporting profile screen) |
| `lib/data/repositories/session_repository.dart` | P | Contract; persistence for the engine |
| `lib/data/repositories/guide_store.dart` | P | `docs/09` §11.4 seam |
| `lib/data/seed/seed_loader.dart` | P | Seed/version/reset contract |
| `lib/data/seed/seed_source.dart` | P | Fixture JSON → deterministic seed rows |
| `lib/data/repositories/fixture/fixture_bundle.dart` | P | Parse the four JSON files into immutable data |
| `lib/data/repositories/fixture/fixture_recipe_repository.dart` | P | Implements recipe contract |
| `lib/data/repositories/fixture/fixture_stock_repository.dart` | P | In-memory tri-state + event list |
| `lib/data/repositories/fixture/fixture_equipment_repository.dart` | P | Owned equipment |
| `lib/data/repositories/fixture/fixture_kitchen_repository.dart` | P | Demo kitchen profile |
| `lib/data/repositories/fixture/fixture_session_repository.dart` | P | In-memory sessions + pinned path + completion |
| `lib/data/repositories/fixture/fixture_guide_store.dart` | P | Composes the fixture repos for the engine |
| `lib/data/fixtures/ingredients.json` | asset | 15 ingredients |
| `lib/data/fixtures/equipment.json` | asset | 5 appliances |
| `lib/data/fixtures/recipes.json` | asset | 3 dishes, steps, variants, display quantities |
| `lib/data/fixtures/kitchen.json` | asset | Profile, owned equipment, tri-state demo stock, seed version |
| `lib/features/kitchen/first_run_screen.dart` | F | Screen 1 |
| `lib/features/kitchen/kitchen_controller.dart` | F | Profile/equipment state |
| `lib/features/kitchen/equipment_picker_sheet.dart` | F | Modal (not an 11th screen) |
| `lib/features/recipes/cook_now_screen.dart` | F | Screen 2 + resume card |
| `lib/features/recipes/all_recipes_screen.dart` | F | Screen 3 (P1; shell in A) |
| `lib/features/recipes/recipe_detail_screen.dart` | F | Screen 4 + variant picker + availability panel |
| `lib/features/recipes/recipes_controller.dart` | F | Loads guides + availability states |
| `lib/features/recipes/recipe_detail_controller.dart` | F | Variant choice, start action |
| `lib/features/guide/guide_screen.dart` | F | Screen 5 |
| `lib/features/guide/usage_review_screen.dart` | F | Screen 6 |
| `lib/features/guide/guide_controller.dart` | F | Engine calls, timer UI state, wakelock |
| `lib/features/stock/inventory_screen.dart` | F | Screen 7 |
| `lib/features/stock/ingredient_detail_screen.dart` | F | Screen 8 (P1; shell in A) |
| `lib/features/stock/stock_controller.dart` | F | Status map + set status |
| `lib/features/history/history_screen.dart` | F | Screen 9 |
| `lib/features/history/history_controller.dart` | F | Sessions + linked events |
| `lib/features/settings/settings_screen.dart` | F | Screen 10 + reset demo |
| `lib/features/settings/settings_controller.dart` | F | Name/equipment/reset |
| `lib/ui/pixel/pixel_canvas.dart` | F | 180×320 art-layer scaling (`docs/07` §1.2-1.3) |
| `lib/ui/pixel/pixel_theme.dart` | F | Palette tokens, text styles |
| `lib/ui/pixel/pixel_panel.dart` | F | 9-slice panel |
| `lib/ui/pixel/pixel_button.dart` | F | Primary/secondary button |
| `lib/ui/pixel/pixel_chip.dart` | F | Status/availability chips |
| `lib/ui/pixel/pixel_progress.dart` | F | Progress bar + timer ring |
| `lib/ui/pixel/pixel_sprite.dart` | F | `Image` + `FilterQuality.none` |
| `lib/ui/pixel/pixel_text.dart` | F | 5×7 atlas text (chrome only) |

Phase A has **zero SQL and zero sqflite imports**; every `[P]` file is tested under `flutter test` without a database. Phase B adds `lib/data/db/**` and `lib/data/repositories/sqlite/**` and changes `lib/app/di.dart`; no screen file changes are expected.

---

## 4. SQLite data layer

### 4.1 The tri-state model

The brief says "tri-state"; the storage uses four values because `low` is a warning face of presence, not a separate presence level:

| Stored `status` | Presence | Availability effect for a **required** ingredient | UI (`docs/07` §5.1) |
|---|---|---|---|
| `have` | present | available | **Have** |
| `low` | present, warning | available + "you may run short" | **Low** |
| `out` | absent | **missing**; recipe `blocked`; Guide anyway available | **Out** |
| `unknown` | untracked | **not blocking**; recipe `needs_confirmation`; flagged "Probably have — confirm" | **Probably have** |

Optional ingredients never affect any availability state, whatever their status. A missing `stock_status` row reads as `unknown` defensively; `unknown` is also stored explicitly. Every catalog ingredient used by a shipped recipe gets a row from seed (engine `SeedMissing` guard).

### 4.2 Table map

`db/schema-sqlite.sql` has **15 tables**; `docs/03`'s 13-table MySQL schema is the contingency, not this DDL.

| Group | Tables |
|---|---|
| Meta | `schema_meta` |
| Local profile | `kitchens` |
| Reference/catalog | `units`, `ingredients`, `equipment` |
| Kitchen | `kitchen_equipment`, `stock_status` |
| Recipes | `recipes`, `recipe_ingredients`, `recipe_equipment`, `recipe_steps`, `recipe_step_variants` |
| Guided cooking | `cooking_sessions`, `session_step_choices` |
| Ledger | `stock_event` |

Naming: `stock_status`/`stock_event` are locked by the captain correction; `docs/06`'s suggested `ingredient_stock` is intentionally not used. `stock_event` has no `kitchen_id` (single kitchen); `stock_status` does, with `kitchen_id = 1`. `docs/09` §3.6 now checks this DDL against the engine contract field by field; the two residual deviations are `timer_step_number` (not persisted; the timer always belongs to `current_step_number`) and the `ingredient_stock` → `stock_status` name.

### 4.3 `stock_event`: reasons, transitions, writes

`reason` is exactly `initial | restock | used_some | used_up | waste | correction` (no `consume`, no `adjustment`). `from_status <> to_status` is a CHECK; a no-op writes no event.

| Reason | Legal transition | Written by |
|---|---|---|
| `initial` | `unknown → have` / `low` / `out` | First stock declaration (inventory screen or demo seed) |
| `restock` | `unknown` / `out` / `low` → `have` | "I have it" / restock action; the usage-review correction also uses `restock`, unlinked |
| `used_some` | `have` / `unknown` → `low` | Usage review "Used it" (`have→low` or `unknown→low`) or a manual quick-use |
| `used_up` | `have` / `low` / `unknown` → `out` | Usage review "Used it up" (`*→out`); `low + Used it` is a no-op under `docs/06` §3.4 |
| `waste` | `have` / `low` → `out` | Spoiled/discarded action (if exposed) |
| `correction` | any → any **different** | Inventory direct status edit that has no more specific reason |

Write rules (repository contract, one transaction):

1. Read the current status; verify `from_status` equals it. If not, reject (`StaleStockEvent`) — a mismatch is never written.
2. Insert the `stock_event` row and update `stock_status` in the same `BEGIN IMMEDIATE` transaction; the conditional update guard is `UPDATE stock_status SET status = :to WHERE ingredient_id = :id AND status = :from` and must affect exactly one row.
3. `cooking_session_id` is non-null only for `used_some`/`used_up`, and only the completion transaction writes those. Manual edits leave it NULL. The review's `restock` correction is **unlinked** (the `note` may name the session for audit) so it cannot collide with the usage unique index.
4. Engine completion writes at most one usage event per ingredient per session; the partial unique index `(cooking_session_id, ingredient_id)` is the last-line guard for `used_some`/`used_up`. The unlinked review `restock` is outside that index; the terminal pre-check and the conditional session update stop a repeated completion (`docs/09` §8.6).
5. Corrections are new events; no UPDATE/DELETE path exists for `stock_event` in the app. Reset demo data is the only explicit deletion (user-confirmed).

`docs/06` A3's reason labels match this enum. `docs/09` §3.3/§3.6 now uses the same table and reason names (it writes `used_some`, `used_up`, and the unlinked review `restock`; the engine never writes `waste` or `correction`). The DDL is the enforcement point; the engine is the only writer of `used_some`/`used_up`.

No-op mapping rule: `setStatus` is idempotent and returns no event when `to == current`; the UI still shows the tapped chip selected.

### 4.4 Equipment variants, pinned paths, and recipe content

`recipe_steps` carries the engine's authored fields (`docs/09` §2.2): `kind`, `instruction`, `detail`, `duration_seconds`, `equipment_id`, `ingredient_refs_json`, `caution`, `sprite_key`, `variant_group`. The DB encodes the row-level lint L6/L7 as CHECKs (wait must have a duration; prep/finish are equipment-free; heat/cook require equipment); contiguous `1..N`, one `finish` at step N, and the variant rules are loader lint, not cross-row CHECKs.

`recipe_step_variants` holds the delta (`instruction_override`, `duration_override`, `sprite_override`), `priority ≥ 1`, one per `(step_id, equipment_id)`, and can only override, never add/remove steps. There is **no automatic path choice**: the cook picks the method (Pan-fry / Air-fry) on the recipe detail, the pick is passed to `planPath` as the requested method for each `variant_group`, and `priority` is stored but is **not** a selection input (`docs/09` §4.2). For the Crispy Pork Belly dish `recipe_equipment` is **empty** and each method declares its appliance through its variant rows: `pan_fry` → `stovetop`, `air_fry` → `air_fryer`. Equipment feasibility therefore comes from `planPath`/`evaluateAvailability`, never from `recipe_equipment` alone.

`session_step_choices` pins one row per step at start (`equipment_id`, `is_variant`, `variant_id`). Equipment edits in Settings never rewrite an active cook. `cooking_sessions.started_without_availability` + `missing_requirements_json` record a Guide-anyway start; the snapshot is immutable for the session.

`missing_requirements_json` format (DB): a JSON array of stable codes — `["equipment:air_fryer","ingredient:bay_leaf"]`; a `group:<id>` code remains possible for a recipe whose requested method has no implementation (a seed error, not a kitchen state). The unowned appliance on the chosen method's path is reported as `equipment:<code>`, so dish 3 reports `equipment:stovetop` for a Pan-fry pick and `equipment:air_fryer` for an Air-fry pick. Path alternatives are not duplicated in the snapshot; the pinned path already records the cook's choice. `docs/09` §3.1 proposes objects with alternatives; the code form is the captain's locked format and is sufficient for the guide banner and history. T5 should pick one; the repository mapper can read either.

### 4.5 Session and timer persistence

`cooking_sessions` relevant fields:

| Field | Rule |
|---|---|
| `status` | `in_progress \| completed \| abandoned`; terminal sessions are never written except by an idempotent completion returning `alreadyCompleted` |
| `current_step_number` | `1..N+1`; `N+1` is the review sentinel; only a `CHECK ≥ 1` exists (N is app-enforced) |
| `started_at`, `completed_at`, `updated_at` | ISO-8601 UTC TEXT; `completed_at` non-null iff completed |
| `timer_started_at` | absolute UTC instant of the running timer; NULL = no timer |
| `timer_duration_seconds` | effective duration snapshot (variant override applied); both timer fields null or both non-null |
| `last_seen_at` | last known foreground instant; distinguishes `done` from `overrun` |
| `started_without_availability` | 0/1; DB CHECK ties it to the missing snapshot |
| `missing_requirements_json` | NULL iff the session started available |
| `servings` | base yield, never scaled |

Remaining time is derived, never persisted as a counter (`docs/09` §6.2): `remaining = clamp(timer_duration_seconds - (nowUtc - timer_started_at), 0, duration)`; `last_seen_at ≥ deadline` means `done`, otherwise `overrun`. There is no paused state — a pot cannot be paused (`docs/09` §6.8).

| Event | Behaviour |
|---|---|
| App killed/backgrounded | Timer fields survive; on relaunch derive; if the deadline passed while away, `overrun`; step unchanged; no auto-advance |
| Clock moved backward | Remaining capped at duration, `clockSkewDetected`; `timer_started_at` never rewritten |
| Clock moved forward | May read `overrun` early; accepted, advisory timer |
| Session older than 24 h | `stale` is derived from `started_at` (not stored); UI offers Resume/Abandon; never auto-abandons; the one-active-session index still applies |
| Advance / complete / abandon | Timer fields cleared in the same UPDATE; notification (P1) cancelled |
| Double completion | Pre-check returns `alreadyCompleted` with zero writes; conditional `UPDATE ... WHERE status='in_progress'` must affect one row; the partial unique index on usage events is the final guard |

### 4.6 Database-enforced vs application-enforced

| Invariant | Enforced by |
|---|---|
| One local kitchen row | `kitchens.id = 1` CHECK + `kitchen_uid UNIQUE` |
| One current status per kitchen+ingredient | `PRIMARY KEY (kitchen_id, ingredient_id)` + `kitchen_id = 1` CHECK |
| Valid status values | `CHECK (status IN (...))` on `stock_status` and both status columns in `stock_event` |
| No-op stock events | `CHECK (from_status <> to_status)` |
| Reason/transition pairings | `CHECK` matrix in `stock_event` (§4.3) |
| Session link only on usage events | `CHECK (cooking_session_id IS NULL OR reason IN ('used_some','used_up'))` |
| One usage event per ingredient per session | Partial `UNIQUE (cooking_session_id, ingredient_id)` |
| One active session per kitchen | Partial `UNIQUE (kitchen_id) WHERE status = 'in_progress'` |
| Completed timestamp consistency | `CHECK` on `status`/`completed_at` |
| Timer both-or-none, terminal clears timer | `CHECK`s on `cooking_sessions` |
| Guide-anyway flag/snapshot pairing | `CHECK` on `started_without_availability`/`missing_requirements_json` |
| Step numbering uniqueness | `UNIQUE (recipe_id, step_number)` |
| Step kind/equipment/duration row rules | CHECKs on `recipe_steps` |
| Variant priority/override/unique | CHECKs + `UNIQUE (step_id, equipment_id)` |
| Pinned path coherence | CHECKs + `UNIQUE (session_id, step_number)` |
| Event `from_status` equals current status at write | Repository transaction: conditional UPDATE must affect 1 row (§4.3); not a SQL CHECK |
| Event and current status written together | Repository transaction |
| Append-only event log | Repository design (no UPDATE/DELETE paths); reset is explicit deletion |
| Contiguous `1..N`, exactly one `finish` at N, variant lint | Seed loader lint (`docs/09` §2.4) |
| Inventory row exists for every seeded ingredient | Seed loader + engine `SeedMissing` guard |
| Missing-requirements snapshot immutable | Engine/repository writing only at start |

Integrity diagnostics (run after any stock test; both return zero rows in a valid chain; validated §11):

```sql
-- 1. Every event continues the previous event's to_status (or unknown first).
SELECT e.id AS broken_chain_event
FROM stock_event e
WHERE e.from_status <> COALESCE((
  SELECT prev.to_status FROM stock_event prev
  WHERE prev.ingredient_id = e.ingredient_id AND prev.id < e.id
  ORDER BY prev.id DESC LIMIT 1), 'unknown');

-- 2. Every current status equals the newest event's to_status (or unknown).
SELECT s.ingredient_id AS status_mismatch
FROM stock_status s
WHERE s.status <> COALESCE((
  SELECT e.to_status FROM stock_event e
  WHERE e.ingredient_id = s.ingredient_id ORDER BY e.id DESC LIMIT 1), 'unknown');
```

### 4.7 MySQL → SQLite differences

One line per deviation from `db/schema.sql`:

| MySQL | SQLite MVP | Consequence |
|---|---|---|
| `users` table, login columns | dropped; `kitchens` row with `kitchen_uid` | No auth; stable string id for the future sync tier |
| `inventory_items.quantity DECIMAL(12,3)` | `stock_status.status TEXT` (4 values) | No arithmetic, no non-negative check; presence only |
| `inventory_transactions.quantity_delta` signed ledger | `stock_event` from/to status + reason | Append-only presence history; no balance |
| `ENUM(...)` | `TEXT` + `CHECK (x IN (...))` | Same closed vocabulary, portable |
| `TIMESTAMP DEFAULT CURRENT_TIMESTAMP / ON UPDATE` | `TEXT` ISO-8601 UTC via `strftime(...)`; writers set `updated_at` | No automatic update; string comparisons are chronological |
| `BIGINT UNSIGNED AUTO_INCREMENT` | `INTEGER PRIMARY KEY` (rowid alias, signed 64-bit) | Ids are internal; domain uses stable string codes |
| `BOOLEAN` / `TINYINT(1)` | `INTEGER` 0/1 + CHECK | Same behavior |
| `DECIMAL` | `NUMERIC` affinity (display-only `quantity`) | Exact decimals are not guaranteed; P1 must use integer minor units or TEXT |
| `ENGINE=InnoDB`, `utf8mb4_unicode_ci` | no engine; UTF-8 DB; `COLLATE NOCASE` where uniqueness is case-insensitive | Same intent |
| `CREATE DATABASE` / `USE kusina` | one file database, no namespaces | Path handled by `path_provider` |
| inline `KEY`/`INDEX` clauses | separate `CREATE INDEX` statements | Same query support |
| FK actions (`CASCADE`, `RESTRICT`, `SET NULL`) | supported, but **`PRAGMA foreign_keys` is OFF by default per connection** | `sqflite` `onConfigure` must run `PRAGMA foreign_keys = ON` |
| `NOW()` / `CURRENT_TIMESTAMP` | `strftime('%Y-%m-%dT%H:%M:%fZ','now')` | Millisecond UTC; app writes explicit times for session transitions |
| `SELECT ... FOR UPDATE` | no row locks; single-writer SQLite | Use one transaction + conditional UPDATE + `changes()` guard |
| `LAST_INSERT_ID()` | `last_insert_rowid()` / `insert()` return | Mapper detail |
| default rollback journal | `PRAGMA journal_mode = WAL` on the file DB | Better concurrent read/write; `:memory:` reports `memory` |
| no partial unique index concept | partial unique indexes supported | One active session and one usage event per session/ingredient |
| `ROW_NUMBER()` seed query | same function available (SQLite ≥ 3.25) | Seed validation only; runtime uses none |

### 4.8 Indexes

| Index | Purpose |
|---|---|
| `stock_status` PK `(kitchen_id, ingredient_id)` | One current status row; completion update target |
| `idx_stock_status_status` | Inventory grouped by status |
| `idx_ingredients_category` | Inventory/catalog grouping |
| `idx_kitchen_equipment_equipment` | Equipment reverse lookup |
| `idx_recipe_ingredients_ingredient`, `idx_recipe_ingredients_unit` | Reverse requirement lookup |
| `idx_recipe_equipment_equipment` | Equipment → recipes |
| `idx_recipe_steps_equipment` | Step scene keys / equipment usage |
| `idx_recipe_step_variants_equipment` | Path planner reverse lookup |
| `uq_cooking_sessions_one_active` (partial) | One active session per kitchen |
| `idx_cooking_sessions_status_started` | History newest-first |
| `idx_cooking_sessions_recipe` | Per-recipe history |
| `idx_session_step_choices_equipment`, `idx_session_step_choices_variant` | Pinned-path lookups |
| `idx_stock_event_ingredient_created` | Per-ingredient history |
| `idx_stock_event_session` | Session receipts |
| `uq_stock_event_session_ingredient` (partial) | Double-completion guard |

Auto-indexes from UNIQUE constraints: `unit.code`, `ingredients.code`, `ingredients.name`, `equipment.code`, `equipment.name`, `recipes.name`, `recipes.slug`, `recipe_steps (recipe_id, step_number)`, `recipe_step_variants (step_id, equipment_id)`.

### 4.9 Deferred exact quantities (P1)

The MVP intentionally has no quantity column, no unit conversion, and no serving scale. The documented extension is additive: `stock_status` gains nullable `quantity NUMERIC` + `unit_id`; `ingredients` gains `canonical_unit_id`; `units` gains `factor_to_base`; availability then compares amounts and applies `chosen_servings / recipe.servings`. Do not implement this now, do not add the columns "for later", and do not reintroduce decimal arithmetic into availability tests; the schema version bump (v2) is the only place it belongs. Exact storage must avoid SQLite `REAL` drift (integer minor units or decimal TEXT), because the availability boundary test in `docs/03` requires exactness.

### 4.10 Opening, migrations, seeding, reset

0. **First run:** `Repositories.sqlite()` reads whether a `kitchens` row exists *before* seeding. On a brand-new database it does not, so `kitchenConfigured` is false and the router opens `/setup`; the demo seed then creates Maria's Kitchen. Every later launch finds the row and opens Cook now. (The fixture bundle always reports configured, so `/setup` is test-only there.)
1. **Open:** `AppDatabase.open()` resolves the app-private DB path, loads `db/schema-sqlite.sql` as a bundled asset, and opens via sqflite. `onConfigure` runs `PRAGMA foreign_keys = ON` and `PRAGMA busy_timeout = 5000`; the first file open runs `PRAGMA journal_mode = WAL`.
2. **Create/upgrade:** `onCreate` executes the DDL asset and writes `schema_meta(schema_version=1, seed_version=0)`. `onUpgrade` switches on `PRAGMA user_version`; a migration is a new function in `migrations.dart`, never an edit to the v1 DDL. `schema_meta.schema_version` and `PRAGMA user_version` are written together.
3. **Seed:** after schema creation, `SeedLoader.seedIfNeeded()` reads the same four fixture JSONs (`ingredients`, `equipment`, `recipes`, `kitchen`), inserts reference rows with deterministic integer ids, inserts one `stock_status` row per ingredient (`unknown` by default), applies the demo kitchen profile/equipment/statuses, and writes the matching `initial` events. `seed_version` is bumped whenever fixture content changes.
4. **Content updates:** if a bundled seed version is newer, reference tables (`ingredients`, `equipment`, `recipes`, children) are rebuilt in one transaction only when no `in_progress` session exists; otherwise the rebuild is deferred to the next launch after the session ends. User data (stock statuses, events, sessions) is never silently rewritten by a content update.
5. **Reset demo data:** the only destructive action (`docs/06` A7). **Blocked while any session is `in_progress`** (offer Resume or Abandon first; the guard is re-checked inside the transaction so a mid-reset start cannot slip through). One transaction: delete `stock_event`, delete `cooking_sessions` (`session_step_choices` cascades), restore the demo `stock_status` values, and rewrite the demo `initial` events. Confirmation dialog names what is lost.
6. **Data lifetime:** tied to app storage; uninstall wipes it (accepted L2 risk). No export, no backup, no scheduled jobs. No `.db` file is ever committed; the repo contains only the DDL.

---

## 5. Contracts

### 5.1 Ids and models

The database keeps integer surrogate keys; the domain and engine use stable string ids, so widgets never see a rowid and the future sync tier keeps identities (`docs/06` §4).

| Domain id | DB source | Example |
|---|---|---|
| ingredient | `ingredients.code` | `bay_leaf` |
| equipment | `equipment.code` | `air_fryer` |
| recipe | `recipes.slug` | `chicken-adobo` |
| kitchen | `kitchens.kitchen_uid` | UUID generated at first run |
| cooking session | `cooking_sessions.id` as a decimal string | `"42"` (P2 may add a UUID) |
| missing requirement | stable code string | `equipment:air_fryer`, `ingredient:bay_leaf`, `group:cook_method` |

Models (Dart shapes; engine models are owned by `docs/09` §11.1 and are not redefined here):

| Model | Fields |
|---|---|
| `Kitchen` | `uid`, `name`, `createdAt`, `updatedAt` |
| `Ingredient` | `code`, `name`, `category` |
| `Equipment` | `code`, `name`, `description?` |
| `Unit` | `code`, `name`, `dimension` (display only) |
| `StockStatus` (enum) | `unknown`, `have`, `low`, `out` |
| `StockReason` (enum) | `initial`, `restock`, `usedSome`, `usedUp`, `waste`, `correction` (DB strings: `used_some`, `used_up`) |
| `StockEvent` | `id`, `ingredientCode`, `from`, `to`, `reason`, `sessionId?`, `note?`, `createdAt` |
| `StockEventDraft` | same as `StockEvent` without `id`/`createdAt` |
| `RecipeDetail` | `slug`, `name`, `description?`, `baseServings`, `ingredientLines`, `equipmentCodes`, `guide` (`RecipeGuide`) |
| `RecipeLine` | `ingredientCode`, `name`, `quantity` (display), `unitCode`, `isOptional`, `preparationNote?` |
| Guide models | `RecipeGuide`, `RecipeStep`, `StepVariant`, `GuidedSession`, `EquipmentPath`, `TimerState`, `StepView`, `MissingRequirement`, `AvailabilityResult`, `CompletionLine`, `CompletionResult`, `ResumeInfo` — per `docs/09` |

The repository mappers convert integer FKs to codes; no integer id appears in a widget, fixture, or engine test.

### 5.2 Repository interfaces (signatures only, no bodies)

```dart
// lib/data/repositories/recipe_repository.dart
abstract interface class RecipeRepository {
  Future<List<RecipeDetail>> listRecipes();
  Future<RecipeDetail?> findBySlug(String slug);
  Future<RecipeGuide?> loadGuide(String recipeId); // recipeId = slug
}

// lib/data/repositories/stock_repository.dart
abstract interface class StockRepository {
  Future<List<Ingredient>> listIngredients();
  Future<StockStatus> getStatus(String ingredientCode);
  Future<Map<String, StockStatus>> getStatuses(Iterable<String> ingredientCodes);

  /// Applies one manual status change and appends the matching event
  /// atomically. Returns null when [to] equals the current status (no-op,
  /// no event). Rejects a reason/transition mismatch.
  Future<StockEvent?> setStatus({
    required String ingredientCode,
    required StockStatus to,
    required StockReason reason,
    String? cookingSessionId,
    String? note,
  });

  /// Append-only primitive used inside a transaction. The caller must have
  /// verified draft.from equals the current status; completion uses this via
  /// SessionRepository.completeAtomically, never as a standalone write.
  Future<StockEvent> recordEvent(StockEventDraft draft);

  Future<List<StockEvent>> listEvents({
    String? ingredientCode,
    String? cookingSessionId,
    int limit = 50,
    int offset = 0,
  });
}

// lib/data/repositories/equipment_repository.dart
abstract interface class EquipmentRepository {
  Future<List<Equipment>> catalog();
  Future<Set<String>> ownedIds();
  Future<void> setOwned(Set<String> equipmentCodes);
}

// lib/data/repositories/kitchen_repository.dart
abstract interface class KitchenRepository {
  Future<Kitchen> get();
  Future<Kitchen> rename(String name);
}

// lib/data/repositories/session_repository.dart
abstract interface class SessionRepository {
  Future<GuidedSession?> loadActiveSession();
  Future<GuidedSession?> loadSession(String sessionId);
  Future<EquipmentPath?> loadPath(String sessionId);

  /// Inserts the session and its pinned path in one transaction.
  Future<void> insertSession(GuidedSession session, EquipmentPath path);

  Future<void> updateStepNumber(String sessionId, int stepNumber, DateTime nowUtc);
  Future<void> writeTimer(String sessionId, DateTime? startedAtUtc, int? durationSeconds);
  Future<void> writeLastSeen(String sessionId, DateTime atUtc);
  Future<void> abandon(String sessionId, DateTime nowUtc);

  /// The only completion write path. Implements docs/09 section 8.4: returns
  /// alreadyCompleted without writes for a terminal session; re-reads statuses
  /// inside the transaction; writes status changes + usage events + session
  /// completion atomically or rolls back everything.
  Future<CompletionResult> completeAtomically({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  });

  Future<List<GuidedSession>> history({int limit = 50, int offset = 0});
}

// lib/data/seed/seed_loader.dart
abstract interface class SeedLoader {
  Future<void> seedIfNeeded();
  Future<int> schemaVersion();
  Future<int> seedVersion();
  Future<void> resetDemoData();
}

// lib/data/repositories/guide_store.dart (docs/09 section 11.4; implemented by
// SqliteGuideStore / FixtureGuideStore, which compose the repositories above)
abstract interface class GuideStore {
  Future<RecipeGuide?> loadRecipe(String recipeId);
  Future<GuidedSession?> loadActiveSession();
  Future<GuidedSession?> loadSession(String sessionId);
  Future<void> insertSession(GuidedSession session);
  Future<void> updateStepNumber(String sessionId, int stepNumber, DateTime nowUtc);
  Future<void> writeTimer(String sessionId, DateTime? startedAtUtc, int? durationSeconds);
  Future<void> writeLastSeen(String sessionId, DateTime atUtc);
  Future<void> abandonSession(String sessionId, DateTime nowUtc);
  Future<CompletionResult> completeAtomically({
    required String sessionId,
    required List<CompletionLine> lines,
    required DateTime nowUtc,
  });
  Future<Map<String, StockStatus>> statusesOf(List<String> ingredientIds);
  Future<Set<String>> ownedEquipmentIds();
}
```

`RepositoryBundle` (in `di.dart`) holds the five repositories + `SeedLoader`; `SqliteGuideStore` and `FixtureGuideStore` bind the `GuideStore` seam so the engine never imports a repository or sqflite. `insertSession` deliberately takes the pinned path: step rows and path rows are one transaction.

### 5.3 `AvailabilityService` (pure Dart) and the presence rule

```dart
// lib/domain/rules/availability_service.dart
abstract interface class AvailabilityService {
  /// Pure: no I/O, no database, no widgets. Equipment feasibility delegates to
  /// planPath (docs/09 section 4.2); ingredient presence uses the tri-state.
  /// requestedByGroup is the cook's explicit method pick; there is no default.
  AvailabilityResult evaluate({
    required RecipeGuide recipe,
    required Set<String> ownedEquipmentIds,
    required Map<String, StockStatus> statuses,
    Map<String, String> requestedByGroup = const <String, String>{},
  });

  /// With no request for a group, reports the best method state for the list
  /// badge; this is display-only and never pins or starts a path.
  Map<String, AvailabilityResult> evaluateAll({
    required Iterable<RecipeGuide> recipes,
    required Set<String> ownedEquipmentIds,
    required Map<String, StockStatus> statuses,
    Map<String, String> requestedByGroup = const <String, String>{},
  });
}
```

Presence rule (normative for the MVP):

| Input | Treatment |
|---|---|
| Equipment required by the **selected method** not owned | `missing` (`equipment:<code>`) → recipe `blocked`; nothing is re-selected |
| Required ingredient `out` | `missing` → `blocked` |
| Required ingredient `unknown` | **not missing**; `unknownIngredients` → `needs_confirmation` (flagged "Probably have — confirm") |
| Required ingredient `have` / `low` | available; `low` adds the "you may run short" warning |
| Optional ingredient, any status | ignored for availability and the missing list |
| Any quantity/unit/serving input | **does not exist on this path** (P1) |

States: `ready` = no missing and no unknown required; `needs_confirmation` = no missing but ≥1 unknown required; `blocked` = ≥1 missing. Availability is advisory (`docs/06` L5): the start action always exists; a blocked start requires Guide anyway and persists the missing codes. `recompute` on every read; no `can_cook` column.

**Mapping to `docs/03` §7.1 (MySQL contingency query) — same intent, different mechanism:**

| `docs/03` §7.1 clause | SQLite MVP |
|---|---|
| `NOT EXISTS (missing required equipment)` | `planPath(recipe, ownedEquipment, requestedByGroup)` feasibility for the picked method; missing `equipment:<code>` entries |
| `COALESCE(ii.quantity,0) < scaled requirement` | `stock_status.status == out` for required ingredients; `unknown` prompts instead of blocking |
| `ri.is_optional = 0` filter | same static `is_optional`/optional set; optionals excluded from all sets |
| serving scale `(? / r.servings)` | removed; session `servings` = base yield (`docs/06` A6) |
| unit compatibility / conversion predicate | deleted from the MVP path (P1); units are display vocabulary |
| return only available recipe ids | `evaluateAll` returns per-recipe `AvailabilityResult` for every recipe; the list screen filters |
| "missing requirements" list | stable codes (`equipment:*`, `ingredient:*`, `group:*`) for UI and the session snapshot |

**Why pure Dart instead of SQL.** (1) One implementation runs against fixtures in Phase A and SQLite in Phase B, so availability tests do not fork. (2) The equipment path is algorithmic — resolve the cook's requested method per `variant_group`, then map each step to its chosen implementation (`docs/09` §4.2) — which is awkward and opaque in SQL. (3) The rule must be unit-testable with a fixed status map and no database (`docs/09` T-01..T-33). (4) Widgets and the engine call the same function; no SQL leaks into UI and no duplicated predicate can drift. (5) The data is 3 recipes × ≤ 8 ingredients; a query brings no performance benefit. (6) Offline-first means the rule must be available without any I/O. Rejected: a SQL availability view/query (cannot run on fixtures; hard-codes path logic; splits the rule across two languages), storing a `can_cook` flag (stale after any stock/equipment edit — `docs/02` §3).

`docs/09`'s `evaluateAvailability` is the canonical implementation; `AvailabilityService` is the batch facade used by the recipe-list controllers and is the only availability entry point outside the engine. Do not reimplement the presence table in a controller.

---

## 6. UI-first contract: fixtures now, SQLite behind the same ports

The risk in this pivot is the pixel UI and the demo path, not the DB. Phase A therefore ships the full UI against fixtures; Phase B swaps the data layer without touching screens. This is the key de-risking decision.

### 6.1 Fixture files and shapes

`lib/data/fixtures/*.json` are the **single content source**: Phase A reads them directly; Phase B's `SeedLoader` inserts the same rows into SQLite. No second seed file exists.

| File | Contents |
|---|---|
| `ingredients.json` | 15 ingredients: `code`, `name`, `category`, `displayUnit` |
| `equipment.json` | 5 appliances: `code`, `name`, `description`, `shipped` |
| `recipes.json` | 3 recipes + equipment codes + display ingredient lines + steps + variants; `seedVersion` |
| `kitchen.json` | profile (`name`, `equipment`), tri-state `stock` list, `seedVersion` |

Example shape (abridged, not full data):

```json
{
  "seedVersion": 1,
  "recipes": [
    {
      "id": "chicken-adobo",
      "name": "Chicken Adobo",
      "baseServings": 4,
      "requiredEquipment": ["stovetop"],
      "ingredients": [
        {"ingredient": "chicken_thighs", "quantity": 1.0, "unit": "kg", "optional": false},
        {"ingredient": "bay_leaf", "quantity": 3, "unit": "pc", "optional": false}
      ],
      "steps": [
        {"stepNumber": 1, "kind": "prep", "instruction": "Pat the chicken dry and season with black pepper.",
         "durationSeconds": null, "equipment": null, "caution": null,
         "spriteKey": "step_prep_none", "ingredientRefs": ["chicken_thighs", "black_pepper"]}
      ],
      "variants": []
    }
  ]
}
```

```json
{
  "seedVersion": 1,
  "kitchen": {"name": "Maria's Kitchen", "equipment": ["stovetop", "air_fryer"]},
  "stock": [
    {"ingredient": "chicken_thighs", "status": "have"},
    {"ingredient": "bay_leaf", "status": "out"},
    {"ingredient": "spring_onion", "status": "low"},
    {"ingredient": "calamansi", "status": "unknown"}
  ]
}
```

Fixture repos mutate in memory: completing Adobo in Phase A lowers the fixture status and appends an in-memory event, so the demo flow (guide → review → inventory → history) works end to end. Restarting the app reloads the JSON, which is acceptable in Phase A and called out in the demo script; Phase B makes it persistent.

### 6.2 Demo kitchen (fixtures and seed, from `docs/06` §7)

| Ingredient | Status | Ingredient | Status |
|---|---|---|---|
| chicken thighs | `have` | salt | `have` |
| pork belly | `have` | black pepper | `have` |
| rice | `have` | sugar | `have` |
| garlic | `have` | spring onion | `low` |
| soy sauce | `have` | calamansi | `unknown` |
| vinegar | `have` | eggs | `have` |
| bay leaf | `out` | banana ketchup | `unknown` |
| cooking oil | `have` | | |

Owned equipment: `stovetop`, `air_fryer` (the other three are seeded and markable "no dishes yet"). Expected states: **Chicken Adobo → blocked** (`ingredient:bay_leaf`, Guide anyway demo), **Sinangag → ready**, **Crispy Pork Belly → ready via either method** (the badge reports the best method; the cook's pick is what pins a path). This is the tri-state demo: `out` blocks, `unknown` prompts, `low` warns, `have` is available.

### 6.3 The swap point

Exactly one file names concrete repositories: `lib/app/di.dart`.

- **Phase A:** `Repositories.fixtures(FixtureBundle.fromJson(await loadAssetJson()))` returns `FixtureRecipeRepository`, `FixtureStockRepository`, `FixtureEquipmentRepository`, `FixtureKitchenRepository`, `FixtureSessionRepository`, `FixtureSeedLoader`, and `FixtureGuideStore`.
- **Phase B:** the same `Repositories` object is built from `AppDatabase` + `Sqlite*Repository` + `SqliteGuideStore`; `seedIfNeeded()` runs before the router shows `/`.
- **Tests:** inject in-memory fakes directly; no widget test reads `di.dart`.

No feature, widget, engine file, or pure rule imports a concrete repository. Swapping is a one-constructor change plus the Phase B dependency additions; a failing swap shows up in the parity test (§6.4), not in screens.

### 6.4 Parity contract

`test/data/parity_test.dart` loads the four JSON files through `FixtureBundle`, seeds an in-memory FFI database with the same data, and asserts:

1. Recipe slugs, step counts/order, step text/durations/equipment/variants, and display ingredient lines are identical.
2. `AvailabilityService.evaluateAll` returns the same per-recipe state/missing codes for the demo kitchen on both backends.
3. `StockRepository.getStatuses` matches the fixture status map.
4. Completing an identical usage review produces the same `stock_status` map and the same event tuples (ingredient, from, to, reason, session-linked) on both backends.

Phase B is not "done" until this test is green.

---

## 7. Testing strategy

### 7.1 Layers and exact paths

| Layer | Files | Tooling | Proves |
|---|---|---|---|
| Pure domain | `test/domain/guide_rules_test.dart` | `flutter test` (no binding/DB) | `docs/09` T-01..T-33: path planning, timer derivation, progress, completion transition table; fixed `nowUtc`, no widgets |
| Pure domain | `test/domain/availability_service_test.dart` | `flutter test` | `have`/`low`/`unknown`/`out`, optional ignored, variant-group equipment feasibility, demo-kitchen states |
| Pure domain | `test/domain/stock_rules_test.dart` | `flutter test` | manual reason mapping (`initial`/`restock`/`used_some`/`used_up`/`waste`/`correction`), no-op detection, illegal transitions |
| Fixture contract | `test/data/fixture_repositories_test.dart` | `flutter test` | fixture repos honor the repository contracts; in-memory completion path |
| Parity | `test/data/parity_test.dart` | `flutter test` + `sqflite_common_ffi` | fixtures ≡ SQLite (§6.4) |
| DB schema | `test/data/db/schema_constraints_test.dart` | `sqflite_common_ffi` | every CHECK/FK/partial index from §11 probe table |
| DB stock | `test/data/db/stock_repository_test.dart` | `sqflite_common_ffi` | event chain, from-mismatch rejection, conditional update, no-op, integrity queries |
| DB session | `test/data/db/session_repository_test.dart` | `sqflite_common_ffi` | one active session, pinned path, timer round-trip, double completion, stale/resume, guide-anyway snapshot |
| DB seed | `test/data/db/seed_loader_test.dart` | `sqflite_common_ffi` | idempotent seed, demo statuses/initial events, reset demo |
| Widget | `test/features/guide/guide_screen_test.dart`, `test/features/stock/inventory_screen_test.dart`, `test/features/recipes/cook_now_screen_test.dart` | `flutter_test` + fake repos | flow wiring, tri-state chips, no numeric inputs, resume card |
| Golden | `test/ui/pixel/pixel_components_test.dart` + `test/ui/pixel/goldens/*.png` | `flutter test --update-goldens` | `PixelCanvas` integer scale, chips, panels, button states |
| DDL CLI | manual/CI command (below) | `sqlite3` | the shipped DDL parses and its constraints hold |

`sqflite_common_ffi` setup: call `sqfliteFfiInit()` and set `databaseFactory = databaseFactoryFfi` in the test's `setUpAll`; open `inMemoryDatabasePath` with the same `onConfigure` pragmas; load the DDL from `db/schema-sqlite.sql` with `File` so the test proves the shipped artifact, not a copy. Widget tests inject `FixtureRepositories` fakes; they never hit the DB.

### 7.2 Exact commands (run on the user's machine; `flutter` exits 1 in this sandbox)

| Command | Purpose |
|---|---|
| `flutter pub get` | Resolve packages / write `pubspec.lock` |
| `dart format --set-exit-if-changed lib test` | Formatting gate |
| `flutter analyze` | Lints (including `avoid_print`, `use_build_context_synchronously`) |
| `flutter test` | All suites |
| `flutter test test/domain` | Pure-Dart rules only (fast) |
| `flutter test test/data` | Fixture + DB + parity |
| `flutter test test/features` | Widget flows |
| `flutter test --update-goldens test/ui/pixel` | Regenerate goldens after an intentional visual change (review the diff) |
| `sqlite3 :memory: ".read db/schema-sqlite.sql"` | DDL smoke test; exit 0, no DB file |
| `flutter run -d <android-device>` | Demo build; verify kill/relaunch timer and airplane mode |

### 7.3 Boundary cases that must stay green

| Case | Expected |
|---|---|
| Required `have` | available; no flag |
| Required `low` | available + "you may run short" |
| Required `unknown` | `needs_confirmation`; **never blocked**; flagged |
| Required `out` | `blocked`; missing code; Guide anyway available and recorded |
| Optional `out`/`unknown` | never blocks, never in the missing list |
| Every required ingredient `unknown` | recipe `needs_confirmation`, not `blocked` |
| Unowned equipment on the chosen method's path | `blocked` with `equipment:*`; Guide anyway (a `group:*` code only appears for a seed error) |
| Method path | the cook's pick is the only input; no priority ranking, no canonical-first fallback, no silent re-selection; unpicked copy and unpicked appliance never appear (`docs/09` T-05..T-10) |
| `low` + "Used it" | no event; status stays `low` ("already low"); `Used it up` writes `low→out` (`used_up`) |
| `unknown` in review | default "Didn't use" writes nothing; explicit "Used it" writes `unknown→low` (`used_some`); "Used it up" writes `unknown→out` (`used_up`) |
| `out` + "Used it" | no event; status stays `out`; session completes |
| Double completion | second call `alreadyCompleted`; event count unchanged; no second status write |
| Duplicate usage event | rejected by the partial unique index if code is wrong |
| Stale session (> 24 h) | `stale` derived; resume/abandon offered; never auto-abandoned; one-active still enforced |
| Timer after kill | remaining derived from `timer_started_at`; `overrun` if deadline crossed while away; step unchanged |
| Clock rollback | remaining capped at duration; `clockSkewDetected`; start instant unchanged |
| Timer at review/terminal | cleared on advance/completion/abandon; DB CHECK rejects terminal+timer |
| Stock `from` mismatch | event rejected inside the transaction; nothing written |
| No-op correction | rejected (`from_status <> to_status`) |
| Guide-anyway snapshot | `started_without_availability = 1` iff missing JSON present; immutable |
| Reset demo | events/sessions deleted, demo statuses restored, deterministic twice |

---

## 8. Phased build plan

Each phase is independently demoable; nothing waits for all phases. Phase A is what the user tests first.

| Phase | Demoable outcome | Main areas touched | Blast radius | Exit gate |
|---|---|---|---|---|
| **A. Pixel shell + fixtures + Adobo e2e** | App opens on Cook now with the demo kitchen; 3 recipes show tri-state availability (Adobo blocked on bay leaf, Guide anyway); cook Adobo through 7 steps (docs/09 splits docs/04's step 2 into `heat` + `cook`) with advisory timer, lock/unlock, usage review, in-memory stock change, history | All new: `lib/app`, `lib/domain`, `lib/data/repositories/fixture`, `lib/data/fixtures`, `lib/features`, `lib/ui/pixel`, `assets/pixel`; engine per `docs/09` | Greenfield UI + engine; **no SQL/DB**; fixture state resets on relaunch | **Gate A** (§8.1): Adobo end-to-end on fixtures, tests green |
| **B. SQLite + Adobo persistence** | Kill mid-cook, relaunch, resume same step/timer; completion persists status/events/history; double completion safe; reset demo works (blocked mid-session) | `lib/data/db/**`, `lib/data/repositories/sqlite/**`, `lib/app/di.dart`, `pubspec` deps, `test/data/db/**`, parity test | Composition root + data layer only; screens/engine untouched by contract | **Gate B** (§8.1): the Gate A flow on SQLite with fixture-vs-DB parity, tests green |
| **C. Dishes 2-3 + explicit methods** | Sinangag and Crispy Pork Belly fully cookable; the cook's Pan-fry / Air-fry pick changes the missing list, copy, duration, sprite and is pinned at start; the unpicked method is never shown or substituted; equipment removal blocks/Guide anyway; pinned path survives Settings edits | `lib/data/fixtures/*.json` (seed v2), `lib/features/recipes` method control, `lib/features/guide` method banner, `assets/pixel`, tests | Content + method presentation; **no schema change** (path/variant tables already exist) | **Gate C** (§8.1): 3 dishes + explicit methods + celebration + history, tests green |
| **D. Polish and demo** | Full 2:30 script twice from Reset demo; P1 screens/sound/notifications/settings; accessibility pass; goldens green; airplane mode; recorded backup | `lib/features/**` polish, `lib/app/services/**` (notifications/sound), `lib/features/settings`, tests/goldens, docs/demo notes | UI-wide + optional plugins; no domain/schema change | Not a gate: demo rehearsal only, on content frozen after Gate C |

Dependencies and parallel work: A → B is the critical path. C can start on fixtures as soon as A's recipe/method model is stable, even while B is in progress, because C touches content and presentation, not `data/db/`. D never blocks B/C completion; it consumes their results.

### 8.1 Gates A, B, C and the content freeze

A gate is a **phase exit**, not a calendar date: the user owns scheduling, so nothing here is expressed in dates, days, or hour ceilings. Each gate is pass/fail by running the listed checks, and the `docs/06` §5 cut order may only fire at a gate.

| Gate | Passes when |
|---|---|
| **Gate A — Adobo end-to-end on fixtures** | Cook Now → 7-step guide (advisory timer) → usage review → inventory and history reflect the transitions, all on fixtures; `dart format --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test` are green; no numeric stock input exists; the timer never advances a step; one manual Adobo run on the demo device. |
| **Gate B — the same flow on SQLite, with parity** | The Gate A path runs on `sqflite` (kill mid-cook → relaunch → same step and timer; completion persists status/events/history; double completion safe; Reset demo data reproduces the demo kitchen and is blocked while a session is `in_progress`); the fixture-vs-DB **parity test** (§6.4) is green, as are the DB constraint suite and `docs/09` T-34..T-54; `flutter test` is green. |
| **Gate C — 3 dishes, explicit methods, celebration, history** | Sinangag and Crispy Pork Belly are cookable; the cook's Pan-fry / Air-fry pick pins the path, drives the missing list/copy/duration/sprite, and is never auto-selected or silently swapped; the completion celebration and the history screen are complete; goldens updated; `flutter test` is green. |

**Content freeze begins after Gate C.** From that point recipe copy, step copy, ingredient lists, methods, and asset keys stop changing; only defect fixes and the Phase D polish (sound, notifications, settings niceties) are allowed. Cut triggers are gate-relative: "before Gate B" (screens and assets not demo-ready), "at Gate B" (a dish's content is not authored, reviewed, and seeded), "at Gate C" (methods, celebration, history, or the device build are not green). The cut hedge is recorded in `docs/06` §5: if Gate C is unhealthy the **method picker** may be cut in favour of one pinned pan-fry path, while the methods data and the engine seams stay and stay tested. Never cut tri-state stock, Guide anyway, the usage review, or the celebration.

---

## 9. Files created by this task

| File | Content |
|---|---|
| `Final Project/docs/08-flutter-architecture.md` | this document |
| `Final Project/db/schema-sqlite.sql` | SQLite MVP DDL, design artifact and bundled schema |
| `Final Project/AGENTS.md` | ≤ 40-line agent/onboarding contract for the Flutter build |

No existing file was modified; no Flutter/Dart application code, `pubspec.yaml`, or generated database was created.

---

## 10. Decisions recorded

| # | Decision | Rejected alternative |
|---|---|---|
| 1 | Flutter 3.50.0 stable (verified against official docs), Android demo target, portrait P0 | Beta/main channel, web/desktop target |
| 2 | `sqflite` + hand-written SQL/mappers, `sqflite_common_ffi` tests | `drift` (codegen, hidden SQL), ORM, JSON store |
| 3 | `ChangeNotifier` controllers + `AppScope`; fixed-clock injection; no state package | Bloc, Riverpod, provider, setState-only |
| 4 | `go_router` with one route table and a tab shell | Raw Navigator 2.0, Navigator 1.0, auto_route |
| 5 | Plain Flutter widgets + `docs/07` `PixelCanvas`; no Flame; 180×320 au, integer `k`, separate dp text layer | Flame game engine, FittedBox/fractional scaling |
| 6 | Tri-state `stock_status` + append-only `stock_event`; reason enum `initial/restock/used_some/used_up/waste/correction`; no `consume`/`adjustment`; no `kitchen_id` on the event | Signed-quantity ledger; `ingredient_stock` naming; no-op events |
| 7 | Engine persistence: `session_step_choices`, `timer_started_at` + `timer_duration_seconds`, `last_seen_at`, `started_without_availability`, `missing_requirements_json`; no paused timer, no upper bound on `current_step_number` | Counter-based timer, phase column, generated step paths |
| 8 | Availability is pure Dart (`AvailabilityService` over `docs/09` rules), delegated equipment feasibility via `planPath`; advisory Guide anyway | SQL availability query, stored `can_cook` flag, hard gate |
| 9 | Fixture-first Phase A against the same repository contracts; one swap point in `lib/app/di.dart`; fixtures are also the Phase B seed source | Build DB first; duplicate seed files |
| 10 | DDL is both a design artifact and a bundled asset; `:memory:` CLI validation and FFI tests execute the same file | Embedded/copied DDL; committed `.db` file |
| 11 | Local notifications and sound are P1/Phase D and never correctness-bearing; wakelock in Phase A; haptics via SDK | Background timers, push notifications, bundled music |
| 12 | Session ids are integer strings in the MVP; ingredient/equipment/recipe ids are stable codes; kitchen has a UUID | Exposing rowids to UI; GUID sessions in v1 |

---

## 11. DDL validation output

Run from `Final Project/` against the shipped file. `:memory:` leaves no database file in the repo.

### 11.1 Schema load and object counts

```text
$ sqlite3 :memory: ".read db/schema-sqlite.sql"
memory
5000
$ echo $?
0
```

`memory` is the `journal_mode` result on an in-memory database (WAL applies to file databases); `5000` is the `busy_timeout` result. Neither is an error.

**Minimal probe seed** (prefixed by `.read db/schema-sqlite.sql`; used by §11.2-§11.6):

```sql
INSERT INTO kitchens (id, kitchen_uid, name) VALUES (1, '0123456789abcdef', 'Demo Kitchen');
INSERT INTO units (id, code, name, dimension) VALUES
  (1, 'g', 'gram', 'mass'), (2, 'ml', 'millilitre', 'volume'),
  (3, 'clove', 'clove', 'count'), (4, 'pc', 'piece', 'count');
INSERT INTO ingredients (id, code, name, category) VALUES
  (1, 'chicken_thighs', 'Chicken thighs', 'meat'),
  (2, 'soy_sauce', 'Soy sauce', 'condiments'),
  (3, 'garlic', 'Garlic', 'produce'),
  (4, 'bay_leaf', 'Bay leaf', 'spices');
INSERT INTO equipment (id, code, name) VALUES
  (1, 'stovetop', 'Stovetop'), (2, 'air_fryer', 'Air Fryer');
INSERT INTO kitchen_equipment (kitchen_id, equipment_id) VALUES (1, 1);
INSERT INTO stock_status (kitchen_id, ingredient_id, status) VALUES
  (1, 1, 'unknown'), (1, 2, 'unknown'), (1, 3, 'unknown'), (1, 4, 'unknown');
INSERT INTO recipes (id, name, slug, servings) VALUES (1, 'Chicken Adobo', 'chicken-adobo', 4);
INSERT INTO recipe_steps
  (id, recipe_id, step_number, kind, instruction, duration_seconds, equipment_id, sprite_key)
VALUES
  (1, 1, 1, 'prep', 'Pat the chicken dry.', NULL, NULL, 'step_prep_none'),
  (2, 1, 2, 'heat', 'Heat the oil in a wide pan.', 480, 1, 'step_heat_stovetop'),
  (3, 1, 3, 'cook', 'Brown the chicken on all sides.', NULL, 1, 'step_cook_stovetop'),
  (4, 1, 4, 'finish', 'Serve hot with rice.', NULL, NULL, 'step_finish_none');
INSERT INTO recipe_step_variants (id, step_id, equipment_id, instruction_override, duration_override, priority)
  VALUES (1, 3, 2, 'Air-fry the chicken.', 720, 10);
INSERT INTO cooking_sessions (id, kitchen_id, recipe_id, servings) VALUES (1, 1, 1, 4);
INSERT INTO session_step_choices (session_id, step_number, equipment_id, is_variant, variant_id) VALUES
  (1, 1, NULL, 0, NULL), (1, 2, 1, 0, NULL), (1, 3, 1, 0, NULL), (1, 4, NULL, 0, NULL);
```

```text
$ sqlite3 -header -column :memory: <<'SQL'
  .read db/schema-sqlite.sql
  SELECT count(*) AS tables FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';
  SELECT count(*) AS explicit_indexes FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';
  SELECT count(*) AS fk_violations FROM pragma_foreign_key_check;
SQL
tables
------
    15
explicit_indexes
----------------
              16
fk_violations
-------------
             0
exit=0
```

### 11.2 Valid lifecycle (initial → have; used_some → low; used_up → out)

```text
$ sqlite3 -header -column -bail :memory: < probe.sql   # DDL + minimal seed + lifecycle writes
ingredient_id  status
-------------  -------
            1  out
            2  unknown
            3  unknown
            4  unknown
id  ingredient_id  from_status  to_status   reason     cooking_session_id
--  -------------  -----------  ---------  ---------  ------------------
 1              1  unknown      have       initial
 2              1  have         low        used_some                   1
 3              1  low          out        used_up                     2
exit=0
```

The second usage event is linked to a different session; the partial unique index correctly rejects two usage events for one ingredient in one session (probe 23 below).

### 11.3 From-status guard (repository transaction pattern)

```text
$ sqlite3 -header -column -bail :memory: < guard.sql
applied_initial
              1
applied_with_matching_from
                         1
applied_with_stale_from
                      0
exit=0
```

`applied_with_stale_from = 0` is the repository's rejection signal: the caller must roll back; a `stock_event` with `from_status` not equal to the current status is never written.

### 11.4 Integrity diagnostics after a valid chain

Both queries from §4.6 returned **zero rows** and exit 0 (no `broken_chain_event`, no `status_mismatch` rows). The check was run after `initial` + `used_some` committed.

### 11.5 File-database pragmas

```text
$ sqlite3 -header -column /tmp/kusina_v2.db "PRAGMA journal_mode; PRAGMA integrity_check;"
journal_mode
------------
wal
integrity_check
---------------
ok
$ sqlite3 -header -column /tmp/kusina_v2.db "PRAGMA foreign_keys;"
foreign_keys
------------
           0
```

WAL persisted for the file; `foreign_keys` is **per connection**, so the app must set it in `onConfigure` on every open (the CLI's second connection did not inherit the first one's setting). The temp DB was deleted; the repo has no `.db*` artifact (`find . -name '*.db*' | wc -l` → `0`).

### 11.6 Constraint probes (all exit 1 unless noted)

| # | Probe | Observed SQLite error |
|---:|---|---|
| 1 | Invalid status `plenty` | `CHECK constraint failed: status IN ('unknown', 'have', 'low', 'out')` |
| 2 | Old reason `consume` | `CHECK constraint failed: reason IN ('initial', 'restock', 'used_some', 'used_up', 'waste', 'correction')` |
| 3 | Old reason `adjustment` | same reason enum CHECK |
| 4 | `used_some` ending `out` | reason/transition CHECK |
| 5 | `used_up` ending `low` | reason/transition CHECK |
| 6 | `initial` starting from `have` | reason/transition CHECK |
| 7 | `restock` ending `out` | reason/transition CHECK |
| 8 | `waste` ending `low` | reason/transition CHECK |
| 9 | `correction` no-op (`unknown → unknown`) | `CHECK constraint failed: from_status <> to_status` |
| 10 | Session link on `initial` | `CHECK constraint failed: cooking_session_id IS NULL OR reason IN ('used_some', 'used_up')` |
| 11 | Duplicate `stock_status` row | `UNIQUE constraint failed: stock_status.kitchen_id, stock_status.ingredient_id` |
| 12 | Second `in_progress` session | `UNIQUE constraint failed: cooking_sessions.kitchen_id` |
| 13 | `completed` without `completed_at` | completed-timestamp CHECK |
| 14 | One-sided timer field | timer both-or-none CHECK |
| 15 | Terminal session with timer | “only a live session may hold a timer” CHECK |
| 16 | Guide-anyway flag without snapshot | guide-anyway pairing CHECK |
| 17 | Snapshot without guide-anyway flag | guide-anyway pairing CHECK |
| 18 | Duplicate step number | `UNIQUE constraint failed: recipe_steps.recipe_id, recipe_steps.step_number` |
| 19 | `wait` step without duration | step kind/duration CHECK |
| 20 | `prep` step with equipment | step kind/equipment CHECK |
| 21 | Variant priority `0` | `CHECK constraint failed: priority >= 1` |
| 22 | Variant with no override | variant override CHECK |
| 23 | Two usage events for one ingredient in one session | `UNIQUE constraint failed: stock_event.cooking_session_id, stock_event.ingredient_id` |
| 24 | Pinned variant without equipment | session-path coherence CHECK |
| 25 | Event for unknown ingredient | `FOREIGN KEY constraint failed` |
| 26 | Kitchen without `kitchen_uid` | `NOT NULL constraint failed: kitchens.kitchen_uid` |

Representative exact transcript:

```text
$ sqlite3 -bail :memory: < probe.sql
Error near line 18: CHECK constraint failed: reason IN ('initial', 'restock', 'used_some',
                                       'used_up', 'waste', 'correction')
exit=1
$ sqlite3 -bail :memory: < probe.sql
Error near line 18: UNIQUE constraint failed: cooking_sessions.kitchen_id
exit=1
$ sqlite3 -bail :memory: < probe.sql
Error near line 18: UNIQUE constraint failed: stock_event.cooking_session_id, stock_event.ingredient_id
exit=1
```

The full probe set is reproducible from the `sqlite3` commands in §11.1-§11.5 with the minimal seed used above; it is also encoded as `test/data/db/schema_constraints_test.dart` in Phase B.

---

## 12. Open questions

| # | Question | Why it matters | Default if unanswered |
|---|---|---|---|
| Q1 | `docs/06` §3.4 vs `docs/09` §8 on `low` + **Used it** and `unknown` review choices. | Earlier drafts disagreed (no event vs `low→out`; three choices vs `Not tracked` only). `docs/09` now follows `docs/06` (three choices, `low + Used it` is a no-op, `unknown + used` → `low`/`out`). | T5 should confirm the final text; the DDL supports either mapping (`used_some`/`used_up` CHECKs cover it) with no schema change. |
| Q2 | ~~Does `recipe_equipment` for Crispy Pork Belly list `stovetop` or `{stovetop, air_fryer}`?~~ **Resolved:** `recipe_equipment` is **empty**; each method declares its appliance through its variant rows. | Feasibility comes from the pinned method's path (`planPath`), so the kitchen is judged on the appliance the chosen method actually uses. | Empty `recipe_equipment`; `pan_fry` → `stovetop`, `air_fry` → `air_fryer`. |
| Q3 | ~~Cooking oil required for pan-fry and optional for air-fry (criterion 13) has no representation.~~ **Resolved (C5):** ingredients are static, cooking oil is optional in both methods, and variant-scoped ingredients are **P1**. Criterion 13 now reads "copy, duration, and sprite differ; ingredients identical". | No variant-ingredient table is needed, so no schema decision remains. | Static `recipe_ingredients.is_optional`; variant-scoped ingredients are P1. |
| Q4 | `missing_requirements_json`: array of stable code strings (captain/docs/06) vs array of objects with `alternatives` (docs/09 §3.1). | Repository serialization and resume copy. | Store code strings; group alternatives are not persisted (the pinned path records the best-effort choice). |
| Q5 | Should `kitchen.schema_version`/`seed_version` live on the kitchen row (`docs/06` §4) or in `schema_meta`? | Two sources of truth invite drift. | `schema_meta` is the single source; the kitchen row keeps profile fields only. |
| Q6 | Is the Flutter app root `Final Project/` (assumed here) or a subdirectory such as `app/`? | Changes every path in this document and the asset manifest. | `Final Project/` root; `docs/` and `db/` stay shared. |
| Q7 | Local notifications are "out" in `docs/06` §5 but assumed by `docs/07`/`docs/09` copy and timer lifecycle. | If P0 must schedule OS notifications, Phase D shrinks and permission setup enters Phase A. | P1/Phase D, optional, never correctness-bearing. |
| Q8 | `docs/06` §3.5 names `timer_step_number` and `timer_started_at_utc`; the final schema uses `timer_started_at` and no step id (a live timer belongs to `current_step_number` by construction). `docs/06` also names `ingredient_stock`; the package uses `stock_status`. | T5 records the deviations or asks for a column/rename; the engine contract already tolerates both (`docs/09` §3.6). | Keep the two-field timer and the captain's `stock_status` name; record all three naming deviations as accepted. |
| Q9 | Android `minSdk`/iOS deployment target and whether the demo device is physical (docs/06 Q6). | Wakelock/notifications/timer kill tests depend on the platform baseline. | minSdk 24, physical Android phone; emulator + recording as backup. |
| Q10 | ~~Should `docs/02`/`03` be amended now, or remain the MySQL contingency?~~ **Resolved (C1-minimal):** 02, 03, and 04 carry a two-line "superseded for the MVP by docs/06 section 3" banner; A10 is applied to GLOSSARY.md; 01 and 05 are untouched and remain the contingency record. | Readers reach the Flutter contract from the old files' headers instead of implementing against retired rules. | Banner on 02/03/04; docs/06 §3 is the implementation contract. |
| Q11 | `docs/06` §7 says the Adobo demo has six steps; `docs/09` §2.5 splits step 2 into `heat` + `cook` → seven steps. | Demo copy, progress counts, mockups ("STEP n OF 7"), and seed content must agree. | Resolved: `docs/06` §5/§7 now say 7 steps (edit recorded in `docs/10`); seed copy uses 7. |
