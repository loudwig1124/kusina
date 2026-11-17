# tool/ — sandbox-runnable Flutter toolchain

`Final Project/` is the Flutter app root. The machine's system Flutter at
`/opt/homebrew/share/flutter` **cannot be used from this sandbox**: the tool must
write `bin/cache/lockfile`, artifacts and pub state, which the sandbox blocks
outside the workspace. This directory holds a workspace-local copy plus a thin
wrapper so every phase can verify itself with the same commands the user runs.

## Files

| Path | Purpose |
| --- | --- |
| `tool/fv` | Wrapper: runs `.flutter-sdk/bin/flutter` with sandbox-contained caches. Falls back to `flutter` on `PATH` when the local SDK is absent (e.g. the user's machine). |
| `.flutter-sdk/` | Verbatim copy of `/opt/homebrew/share/flutter` (gitignored), carrying one local patch — see below. |
| `.pub-cache/` | Seeded from `~/.pub-cache`, then extended by `pub get` (gitignored). |
| `.tool-home/` | `HOME` for the tool so analytics/analyzer state stays inside the workspace (gitignored). |

`tool/fv` sets `FLUTTER_SUPPRESS_ANALYTICS=true`, `PUB_CACHE=<repo>/.pub-cache` and
`HOME=<repo>/.tool-home` only when `.pub-cache/` exists, so on a normal developer
machine it is a plain passthrough to the local SDK (or system `flutter`).

## Recorded versions (2026-11-17)

- Flutter **3.47.5** stable, revision `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`
- Dart **3.13.4**, DevTools 2.60.0, engine `af7e796e16`
- `flutter_tools` tool crash-artifact downloads on first run: iOS USB helper
  artifacts (`libimobiledevice`, `libplist`, `openssl`) into `.flutter-sdk/bin/cache/artifacts/`.
  Package + native-asset downloads: `pub get` resolved 96 packages into `.pub-cache/`;
  the `sqlite3` build hook downloaded a prebuilt `libsqlite3.dylib` into
  `.dart_tool/hooks_runner/shared/sqlite3/build/`, and `objective_c` compiled its
  dylib with clang.

## Commands

```bash
cd "Final Project"
./tool/fv --version
./tool/fv pub get
./tool/fv analyze
./tool/fv test
```

## Local patch in the SDK copy (required for `flutter test` here)

The repo path contains parentheses: `.../School Project (AppDev)/Final Project`.
Flutter 3.47.5's `parseOtoolArchitectureSections`
(`packages/flutter_tools/lib/src/isolated/native_assets/macos/native_assets_host.dart`)
parses `otool` output with `^[^(]+( \(architecture (.+)\))?:$`; the `[^(]+` path
part cannot match a path containing `(`, so the `.dylib` header line falls into the
content branch and `flutter test` dies with
`Oops; flutter has exited unexpectedly: "Null check operator used on a null value"`
(the native-assets copy step for `flutter_tester`). Route: `copyNativeCodeAssetsMacOSFlutterTester`
→ `getInstallNamesDylib` → `parseOtoolArchitectureSections`.

The one-line patch applied to the SDK copy:

```dart
// before
final architectureHeaderPattern = RegExp(r'^[^(]+( \(architecture (.+)\))?:$');
// after (same capture groups: 1 = " (architecture x)", 2 = "x")
final architectureHeaderPattern = RegExp(r'^.+?( \(architecture (.+)\))?:$');
```

`bin/cache/flutter_tools.snapshot` was rebuilt from the patched source, and the
unpatched snapshot is kept as `bin/cache/flutter_tools.snapshot.orig`.

Rebuild after changing the SDK copy:

```bash
cd .flutter-sdk/packages/flutter_tools
../../bin/cache/dart-sdk/bin/dart --verbosity=error \
  --snapshot="$PWD/../../bin/cache/flutter_tools.snapshot" \
  --snapshot-kind=app-jit \
  --packages=.dart_tool/package_config.json \
  --no-enable-mirrors bin/flutter_tools.dart
```

This patch is sandbox plumbing, not app code: it is gitignored with `.flutter-sdk/`
and is unnecessary on a paren-free checkout or on a Flutter release that carries the
upstream fix. Report it if a future task sees `flutter test` crash with a null check
in native assets.

## Hand-off to another machine

The app does not depend on the patch; it is tooling only. If another machine checks
out this repo at a path containing parentheses and runs Flutter 3.47.5, `flutter test`
crashes (see above) while `pub get`, `analyze` and `flutter run` still work.

Options, in order of preference:

1. Apply the same one-line patch to that machine's SDK and rebuild the snapshot
   (recipe above). This is the least disruptive.
2. Upgrade Flutter once the upstream fix ships; drop the patch then.
3. Move or rename the checkout so no parent directory contains `(`. Do this only
   before opening a session in the repo: changing the workspace path while a session
   is running breaks its working directory and the team tooling's project resolution.

Keep `.flutter-sdk/`, `.pub-cache/` and `.tool-home/` out of version control; they
exist only because this sandbox blocks writes outside the workspace.
