# Kusina

**A pixel-art, offline Filipino cooking guide for one phone.**  
Working title — rename before submission.

Kusina keeps one kitchen's stock in four honest states, shows which of its three
dishes the cook can make right now with the appliances they own, and walks the
cook through every step. When the cook starts a dish with something missing they
can still go ahead — the app records that choice instead of arguing. When the
cook finishes, they confirm what was used and every change is written as an
append-only stock event.

The app is **Flutter + SQLite**, runs completely offline, and was built by
pivoting an earlier MySQL/React design into a mobile-first product. That MySQL
design (`db/schema.sql`, `docs/01`–`docs/05`) is kept as the **contingency**
record; the shipped contract is `docs/06`–`docs/09`.

## Status

**Phase C shipped.** The app builds and runs: three dishes end to end, the
cook-chosen Pan-fry / Air-fry method, the guided cook with timers, the usage
review, the completion celebration and History, all on an on-device SQLite
database with no account and no network.

| Item | Status |
|---|---|
| 3 shipped dishes (Chicken Adobo, Sinangag, Crispy Pork Belly) | Shipped |
| 9 further dishes in `docs/04` | Design-only — documentation, not seeded |
| 15 ingredients | Shipped |
| 10 screens (First run, Cook now, All recipes, Recipe detail, Guided cook, Usage review, Inventory, Ingredient detail, History, Settings) + equipment picker modal | Shipped |
| SQLite schema, 15 tables, bundled as an asset | Shipped, no migrations in the MVP |
| Guided cook on fixtures (Phase A) | Shipped and tested |
| SQLite swap with fixture↔database parity (Phase B) | Shipped and tested |
| Method pick, resume card, celebration, History (Phase C) | Shipped and tested |
| Sound and haptics | Phase D — no-op seams in place |

## Run it

This README sits at the Flutter root (`Final Project/`); every path below is relative to it.

```bash
cd "Final Project"

# In this sandbox: the workspace-local SDK (a system Flutter cannot write its cache here)
./tool/fv pub get
./tool/fv analyze
./tool/fv test
./tool/fv run                  # on a connected phone/emulator

# On a normal machine with a Flutter SDK on PATH:
flutter pub get && flutter analyze && flutter test && flutter run
```

`./tool/fv` is a thin wrapper: it uses `.flutter-sdk/` when present and falls
back to `flutter` on `PATH`. See [`tool/README.md`](tool/README.md)
for the sandbox notes (including why the SDK copy exists).

## MVP at a glance

- One kitchen, kept on the phone. No auth, no sync, no network.
- **3 dishes**, **15 ingredients**, **5 appliances** (stovetop, air fryer, oven,
  grill, pressure cooker — the last three carry "No dishes yet" in the picker).
- **Stock is a presence state, not a quantity:** `unknown`, `have`, `low`,
  `out`. No keypad, no grams, no unit conversion, no serving scale. `out`
  blocks, `unknown` asks for confirmation, `low` warns, optional ingredients
  never block.
- **The cook picks the method.** Crispy Pork Belly ships Pan-fry (stovetop) and
  Air-fry (air fryer) as explicit choices; nothing is pre-selected, the pick is
  pinned per step at start in `session_step_choices`, and it cannot change
  mid-cook. A blocked pick still starts through **Guide me anyway**, recorded
  with the missing requirements.
- **Guided cook:** one step at a time, tap-to-advance only, an advisory timer
  stored as an absolute UTC instant (locking the phone loses no time), a resume
  banner after backgrounding, and no auto-advance ever.
- **Usage review:** exactly three choices per line (Didn't use / Used it / Used
  it up), one atomic confirm, append-only stock events, idempotent on repeat.
- **History:** completed and abandoned cooks, the events they wrote, and the
  full stock-event log (including review restocks that carry no session link).
- **Reset demo data** restores the demo kitchen and is blocked while a cook is
  in progress.

## Where the contract lives

The Flutter pivot is specified by these documents (read them in order):

| Document | What it answers |
|---|---|
| [`docs/06`](docs/06-flutter-product-scope.md) | Product scope, locked decisions, the 18 MVP criteria, the class demo script, the 3-dish cut line |
| [`docs/07`](docs/07-pixel-ui-spec.md) | Pixel UI spec: 180×320 art canvas, palette, the 10 screens, components, review and celebration |
| [`docs/08`](docs/08-flutter-architecture.md) | Flutter architecture, the SQLite data layer, contracts, testing strategy, phased plan |
| [`docs/09`](docs/09-guided-cooking-engine.md) | Step model, explicit method choice, session state machine, timers, usage review, engine signatures, test cases |

Supporting material: [`GLOSSARY.md`](GLOSSARY.md),
[`AGENTS.md`](AGENTS.md) (build conventions),
[`assets/README.md`](assets/README.md) (the content
contract) and [`db/schema-sqlite.sql`](db/schema-sqlite.sql)
(the executable schema — bundled as an app asset, not imported by hand).

The demo script is [`docs/06` §7](docs/06-flutter-product-scope.md#7-class-demo-script-230):
it walks Cook now → the method pick → Guide me anyway → the 7-step Chicken Adobo
→ the usage review (including an "I have it" restock) → the celebration → History.

## Repository layout

```text
.                     # Final Project/ — the Flutter app root
  lib/app/              # composition root, router, AppScope, lifecycle
  lib/domain/           # pure Dart: models, availability, the guide engine
  lib/data/             # repositories: fixtures (Phase A) and SQLite (Phase B)
  lib/features/         # screens + controllers (kitchen, recipes, guide, stock, history, settings)
  lib/ui/pixel/         # the pixel widget kit
  assets/fixtures/      # Phase A content JSON (3 dishes, 15 ingredients, demo kitchen)
  assets/seed/          # the same content as SQLite seed rows
  db/schema-sqlite.sql  # the shipped DDL (bundled asset, applied on first run)
  docs/                 # the contract documents 06-09
  design/               # palette + mockups
docs/01-05, db/schema.sql, GLOSSARY.md   # the MySQL contingency design, superseded for the MVP
```

## The MySQL design (contingency)

Before the Flutter pivot this project specified a MySQL + Node/Express + React
web app: `db/schema.sql` (13 tables), `db/seed-reference.sql`, and
`docs/01`–`docs/05` (product scope, domain model, database design, seed plan,
build roadmap). Those files are unchanged and still describe the web
contingency; `docs/06`–`docs/09` supersede them for the shipped app. Where the
two disagree about the MVP (three dishes, no quantities, presence-state stock),
`docs/06`–`docs/09` win.

## Known limitations

- One kitchen, three dishes, no serving scaling: the MVP is deliberately coarse.
- The nine other Filipino dishes in `docs/04` are design documentation only.
- Ingredient quantities are display-only prose; nothing compares or converts
  them (exact quantities are a P1 design in `docs/08` §4.9).
- Local notifications and sound are optional Phase D seams; timers are correct
  without them.
- The app is phone-only (Android/iOS, portrait) and has no sync, export or
  backup; uninstalling removes the data.
- No SQLite ERD or data dictionary yet — that is a separate documentation pass
  after the final gate.

## Verification

```bash
cd "Final Project" && ./tool/fv analyze   # static analysis
cd "Final Project" && ./tool/fv test      # domain, data, feature and pixel tests
python3 tool/validate_content.py           # fixtures ≡ seed, and both load into SQLite
```

The content validator is [`tool/validate_content.py`](tool/validate_content.py); the
pixel mockups in [`design/mockups/`](design/mockups/) were generated by
`design/mockups/generate.py`.
