# AGENTS.md — Kusina (Flutter pivot)

## Stack (locked: docs/06 L1-L6, docs/08)
- Flutter 3.47.5 stable (workspace SDK copy; run it via `./tool/fv`). Android + iOS phone, portrait, offline-only. No auth, network, or economy.
- `sqflite` + hand-written SQL/mappers. No drift, ORM, or codegen. Tests use `sqflite_common_ffi`.
- State: `ChangeNotifier` controllers + `AppScope` InheritedWidget. No Bloc/Riverpod/provider.
- Routing: `go_router`. Pixel art: plain widgets + `docs/07` `PixelCanvas`, no Flame.
- 3 shipped dishes: Chicken Adobo, Sinangag, Crispy Pork Belly. 15 ingredients.

## Layout (Flutter root = Final Project/)
- `lib/app/` composition root, router, lifecycle, platform services; `di.dart` is the only fixture→SQLite swap point.
- `lib/domain/{models,guide,rules,ports}/` pure Dart: no Flutter, sqflite, dart:io, or rootBundle.
- `lib/data/{db,repositories,seed,fixtures}/` SQLite, contracts, seed, JSON content; only `sqlite/` imports sqflite.
- `lib/features/{kitchen,recipes,guide,stock,history,settings}/` screens + controllers.
- `lib/ui/pixel/` presentation-only kit; `assets/pixel|font|sfx/`; `db/schema-sqlite.sql` is a bundled asset.

## Data conventions
- Stock is tri-state presence: `unknown | have | low | out`. No quantity, unit conversion, or serving scale in MVP (P1).
- Reasons: `initial, restock, used_some, used_up, waste, correction`. Never `consume`/`adjustment`.
- Tables: `stock_status` (current) and `stock_event` (append-only, no kitchen_id).
- `out` = missing; `unknown` = not blocking but flagged; `have`/`low` = available, `low` warns.
- Availability is pure Dart; no SQL in widgets; no stored `can_cook` flag.
- One stock event + status update per transaction; from_status must equal current; no-ops write no event.
- Timers: persist absolute UTC `timer_started_at` + duration; never a ticking counter or paused state.
- Timestamps: ISO-8601 UTC TEXT; set `updated_at` explicitly.

## Commands (from Final Project/)
In this sandbox always use the wrapper: bare `flutter`/`dart` fail because the system SDK cache is outside the workspace.
- `./tool/fv pub get` · `./tool/fv analyze` · `./tool/fv test`
- `./tool/fv test test/domain` · `./tool/fv test test/data` · `./tool/fv test --update-goldens test/ui/pixel`
- Format: `.flutter-sdk/bin/cache/dart-sdk/bin/dart format --set-exit-if-changed lib test`
- `sqlite3 :memory: ".read db/schema-sqlite.sql"` (schema smoke test; no .db file committed)

On a normal machine the commands are `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`.

## Sandbox note
- The system SDK at `/opt/homebrew/share/flutter` cannot run here: writes outside the workspace are blocked, and the repo path's parentheses trip a Flutter 3.47.5 otool parser bug. `.flutter-sdk/` is a gitignored copy carrying the one-line patch; `tool/README.md` holds the recipe and revert path.
- Never invoke bare `flutter`/`dart` here. Never delete `.tool-home/` (it holds `enable-native-assets: true`) or `.pub-cache/`.
- The app itself does not depend on the patch; only `flutter test` on a parenthesised path breaks on 3.47.5.
- Docs 01-05 and `db/schema.sql` are the MySQL contingency; `docs/06/07/08/09` are the Flutter contract. Do not edit them without an owner pass.
