# Kusina mockups

Six generated pixel-art wireframes for the Flutter pivot. They exist so a reviewer can **see** the
three availability badges, the four tri-state stock chips, the tap-to-continue guide, the explicit
**Pan-fry / Air-fry** method control and the number-free usage review before any Dart is written.

Specification: [`docs/07-pixel-ui-spec.md`](../../docs/07-pixel-ui-spec.md).
Colour source: [`design/palette.json`](../palette.json).
Locked product decisions and copy: [`docs/06-flutter-product-scope.md`](../../docs/06-flutter-product-scope.md) §2-§5.

## Run

```bash
# from the repository root (Final Project/)
python3 design/mockups/generate.py
```

- Pure Python 3 + Pillow (tested with Python 3.9.6 / Pillow 11.3.0). No network, no randomness,
  no downloaded or copied artwork. Two consecutive runs produce byte-identical PNGs.
- Prints a **tap-target floor check** before it writes anything: every interactive control is at
  least 24 au (48 dp) in both dimensions and the single primary action is 28 au (56 dp). If a
  control were recorded under the floor the script would exit non-zero; today it prints
  `tap-target floor: ... all controls pass` and exits 0.
- Writes the six PNGs next to the script and prints their sizes. Exit code 0.
- Optional contact sheet of the bitmap font, sprites, icons, chips, availability badges, the method
  button (selected/unselected), review choices, status tags, timer rings (running and done) and
  buttons:

```bash
python3 design/mockups/generate.py --sheet /tmp/kusina_sheet.png
```

- `--outdir <dir>` writes the six PNGs elsewhere (default: this directory).

The script reads `../palette.json` relative to its own location, so it works from any working
directory, but the documented command is from `Final Project/`. No time or day estimate is attached
to the asset budget: the phase exits in `docs/08` §8 are the only milestone language.

## Output

All six images are **540 × 960 px** = the 180 × 320 art-unit canvas at 3×. The **art layer is
pixel-exact**: every frame, sprite, icon and ring is drawn in integer 3-px blocks, which is
byte-for-byte what nearest-neighbour upscaling of a 180 × 320 artwork produces. The **text layer is
drawn at final resolution on purpose** (see "The typography demonstration"), so the images are RGB
PNGs with no alpha and no fractional art scaling, but with anti-aliased prose by design.

| File | Screen | What it proves |
|---|---|---|
| `01_cook_now.png` | Cook now | Three recipe cards with the three availability badges: Chicken Adobo **Missing** (bay leaf out), Sinangag **Ready**, Crispy Pork Belly **Ready** (locked dish names). Kitchen name + equipment line, tab bar, no numbers. |
| `02_recipe_detail.png` | Recipe detail | The **P0 method control**: Pan-fry **Probably have** / Air-fry **Missing** as per-method badges, Air-fry selected (illustrative), so the availability panel reads **Missing** and the primary is **Guide me anyway** with its confirm note. Also required chips (Have, Probably have), the collapsed optional line that is not clipped, and the fixed tap-target sizes. |
| `03_guide_prep.png` | Guided cook, step 1 (prep) | Step card anatomy (order badge, title, instruction, detail, timer row, next-step hint), mascot bubble, **Continue** primary, "It waits for your tap" — the no-auto-advance rule. Progress is `(k−1)/N` = **0/7**. |
| `04_guide_timer.png` | Guided cook, step 2 (heat) | Order badge, progress **1/7** (the `(k−1)/N` formula), and **one timer phase only**: the running ring (`4:24` of 8 min, title-case **Running** badge), dark timer panel, "No auto-advance", keep-awake line. No finished panel is shown at the same time. |
| `05_review.png` | Usage review | One line per ingredient: a 72 × 24 tappable **status tag** (the `+` mark is the **I have it** restock control) above three 48 × 24 choices. One **Used it** disabled on the `out` line, selected states, the decay note and the restock hint. **8 lines**; four fit at the floor, so the list scrolls (count + clipped row + scrollbar). No numeric input. |
| `06_stock_setup.png` | Inventory | A **2 × 2 grid** of 76 × 24 chips per ingredient (**Have / Low / Out / Probably have**) with all four chip designs; three rows show the four states in context (Have, Low, Out) and the list scrolls ("3 OF 15"). Toast: "Saved. No numbers to type." |

### State coverage

| State / element | Where it is visible |
|---|---|
| `Ready` badge | 01 (Sinangag, Crispy Pork Belly); 02 (Pan-fry method button, when confirmed) |
| `Probably have` badge | 02 (Pan-fry method button) |
| `Missing` badge | 01 (Chicken Adobo); 02 (Air-fry method button + availability panel) |
| `Have` chip | 02 (Pork belly), 05, 06 |
| `Low` chip | 06 (Spring onion) |
| `Out` chip | 05 (Bay leaf tag), 06 (Bay leaf) |
| `Probably have` chip (unknown) | 02 (Salt), 06 (unselected chip in each grid) |
| Disabled control | 05 (Used it on an `out` line) |
| Method control | 02 (Pan-fry / Air-fry, one selected) |
| Restock control (`+` tag) | 05 (Bay leaf `out` row) |
| Progress `(k−1)/N` | 03 (0/7), 04 (1/7) |
| Timer phase | 04 (`running` only); `done` / `overrun` rings on the `--sheet` contact sheet |
| Scroll cue | 05 (4 of 8 lines + scrollbar), 06 (3 of 15 + count) |
| Locked dish names | 01 (all three), 02 (Crispy Pork Belly) |

## The typography demonstration

The brief requires the mockups to demonstrate **"readable body text, pixel chrome"**:

- Screen headings, section labels, tab labels, action-button labels and numerals are drawn with a
  hand-built **5 × 7 bitmap font** implemented in `generate.py` (glyph table for A-Z, 0-9 and
  `.:!?/-%+()'`). The bitmap face has no lowercase, so it never renders a locked label.
- The four stock statuses (**Have / Low / Out / Probably have**), the three availability badges
  (**Ready / Probably have / Missing**) and the three review choices (**Didn't use / Used it /
  Used it up**) are drawn in a **real TrueType face** in the locked title case, so the strings
  appear verbatim (`docs/06` §3.4, F-18).
- All prose — instructions, ingredient names, hints — and every locked status label is drawn with the same **TrueType face**
  loaded from the OS (`/System/Library/Fonts/Supplemental/Arial.ttf`, with a list of fallbacks down
  to `ImageFont.load_default()`). It is anti-aliased and stays legible at arm's length.
- The reason is in the spec: the phone sits on a counter, the cook has wet hands and a dim
  kitchen; a 5 × 7 pixel font has no lowercase and no word shapes, so instruction text must not
  use it.

Sizes in the images are art-canvas pixels: at the reference device (1 art unit = 2 dp) the 26-27 px
body text is ≈ 18 dp (matching the spec's 18 sp floor) and the smallest control label is 21 px
(≈ 14 dp, the spec's 14 sp control-label floor). The mockups are proportion references; the
normative type scale is §3.2 of the spec.

## Tap-target floor

One floor (`docs/07` §0 rule 6, §4; docs/10 F-05 / condition C6): **48 dp (24 au) hit rect minimum
in both dimensions; 56 dp (28 au) for the single primary action**. Controls draw at their hit size.

| Control | Size (au) | dp @ 1 au = 2 dp |
|---|---|---|
| Primary action | 168 × 28 | 336 × 56 |
| Inventory chip (2 × 2 grid) | 76 × 24 | 152 × 48 |
| Review choice | 48 × 24 | 96 × 48 |
| Review status tag / restock | 72 × 24 | 144 × 48 |
| Method button | 78 × 36 | 156 × 72 |
| Recipe-detail status chip | 68 × 24 | 136 × 48 |
| Tab target | 45 × 24 | 90 × 48 |

`generate.py` records these numbers in `CONTROL_FLOORS` and fails the run if any drops under 24 au.

## Palette

16 colours, defined once in [`design/palette.json`](../palette.json) with hex, RGB, role, the four
stock states, the three availability badges, 18 WCAG contrast pairs (all ≥ AA) and four forbidden
pairs. Warm Filipino kitchen reference: adobe clay, banig weave, calamansi green, coconut cream,
annatto — no flag colours and no caricature. The `unknown` state is described everywhere as
"unknown (Probably have)"; the retired "Not tracked" wording is gone from the metadata (F-21).

The script fails loudly if `palette.json` is missing or a colour token is renamed, so the mockups
and the spec cannot drift silently.

## Asset-budget summary (full table in the spec, §11)

| Category | P0 | P1 | Notes |
|---|---:|---:|---|
| Backgrounds | 4 | 2 | one per scene type, never per dish |
| Step scene sprites | 7 | 2 | `step_<kind>_<equipment>` keys used by the guide engine |
| Dish stamps | 3 | 0 | one per shipped dish |
| Variant icons | 2 | 0 | pan-fry / air-fry (method control) |
| Ingredient icons | 15 | 10 | exactly the 3 dishes' ingredients, not 45 |
| Equipment icons | 5 | 0 | all five seeded appliances |
| Mascot expressions | 4 | 3 | idle, waiting, caution, celebrate |
| UI chrome | 26 | 4 | frames, icons, tabs, ring, bubble |
| Bitmap font atlas | 1 | 0 | 5 × 7 |
| SFX | 7 | 2 | tap, advance, timer start/done, confirm, caution, celebrate |
| **Total** | **74** | **23** | counts only; no time estimate |

Composition rule: **scene = 1 background + at most 3 sprites + 1 text panel**. No per-step, per-dish
or per-equipment bespoke artwork in the MVP.

## Files

```
design/palette.json          colours, states, contrast table
design/mockups/generate.py   generator (Pillow; bitmap font + TrueType body, floor check)
design/mockups/01_cook_now.png
design/mockups/02_recipe_detail.png
design/mockups/03_guide_prep.png
design/mockups/04_guide_timer.png
design/mockups/05_review.png
design/mockups/06_stock_setup.png
```

## Fixes landed in this render (docs/10 findings)

| Finding | What changed |
|---|---|
| F-05 | One floor: 48 dp hit / 56 dp primary. Inventory is a 2 × 2 grid of 76 × 24 chips; review choices are 48 × 24 with a scroll cue. |
| F-15 | 04 shows one timer phase (`running`) only; the finished state is specified in `docs/07` §9.4 and sampled on the contact sheet. |
| F-16 | 05 shows 4 of Adobo's 8 lines with a count, a clipped row and a scrollbar. |
| F-17 | 03/04 use the engine formula `(k−1)/N` (step 1 empty, step 2 = 1/7). |
| F-18 | Status/availability/review labels are title-case system sans, verbatim; the bitmap face is headings/section labels/action labels/numerals only. |
| F-19 | Locked dish name "Crispy Pork Belly", the optional line is collapsed and not clipped, and 04 carries its order badge. |
| F-21 | `design/palette.json` describes `unknown` as "unknown (Probably have)"; no "Not tracked". |

## Known limits (deliberate)

- Wireframe fidelity: no shadows beyond the 2 px panel drop, no textures, no final art. Sprites are
  placeholders that fit the palette and the grid.
- The mockups do not show the celebration, Settings, History, All recipes or the equipment modal;
  they are specified in `docs/07` §7 and will be built from the same components.
- Mockup states are illustrative: 02 selects the Air-fry method as `Missing` and reads Pan-fry as
  `Probably have`; the locked demo snapshot in `docs/06` §7 keeps Chicken Adobo `Missing` and the
  other two `Ready` (docs/07 C5).
- At the 48 dp floor only three inventory rows and four review lines fit above the pinned action;
  both lists scroll, which is the trade F-05 accepted (rows per screen for kitchen-usable targets).
- The finished/overrun timer panels are not shown on screen 04 (they are mutually exclusive with
  `running`); the `--sheet` contact sheet renders the running and done rings side by side.
