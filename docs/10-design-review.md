Status: review complete - Owner: design-reviewer - Reviewed: docs/06-09, design/

# Cross-Document Consistency and Feasibility Review

**Verdict: `approve-with-conditions`** — 0 blockers, 6 high, 8 medium, 12 low; 10 edits applied; 8 conditions; 13 open decisions for the user.

**Basis of precedence used here.** `docs/06` §2 (L1-L6) and §3 (A1-A10) are the locked MVP contract; `docs/06` §10 makes it win over `docs/01-05` for the MVP. `docs/08` is normative for the Flutter stack and for persistence fields (DDL is the enforcement point). `docs/07` is normative for the pixel layer, `docs/09` for engine behavior. Where documents disagree this review does not average them — it cites both sides and rules.

**Method and evidence.** Read `GLOSSARY.md`, `docs/01`-`05`, then `docs/06`-`09`, `db/schema-sqlite.sql`, `AGENTS.md`, `design/palette.json`, `design/mockups/README.md` and all six PNGs (inspected visually; art is 3 px per art unit so dp values below are derived at 1 au = 2 dp). Grepped the `docs/06` §3.9 banned-term list, the locked label sets, the six reason values, the table names and the step/asset counts across `docs/06-09` and `design/`. **Nothing was executed**: no Flutter/Dart run, no `sqlite3`, no generator re-run, no network; the mockups were judged as delivered.

---

## 0. Verdict summary

| Item | Result |
|---|---|
| Verdict | **approve-with-conditions** |
| Blocker / high / medium / low | **0 / 6 / 8 / 12** (26 findings) |
| Edits applied by this review | 10 (all one-line or one-cell; no section rewritten) |
| Conditions | 8 (C1-C8, each tied to a gate) |
| Build first | **Chicken Adobo vertical slice on fixtures** (`docs/08` §8 Phase A): pixel shell, 7-step guide, persisted-start timer, usage review writing statuses, in-memory events, Reset |
| Why not `reject` | Every high finding is a contract *gap*, not a broken model: the tri-state model, the reason enum, the review mapping, the timer derivation and the SQLite DDL all agree across four documents and 15 tables. |
| Why not `approve` | Three demo-visible mechanics are specified three different ways (variant selection, dish-3 equipment, tap targets), one locked success criterion (docs/06 §8 #13) cannot be met by the current schema/engine, and the plan has no dated milestone the cut order can fire against. |

---

## 1. Captain addendum verification (A-E)

| # | Requirement | Where checked | Observed | Result |
|---|---|---|---|---|
| A | `stock_event.reason` exactly `initial \| restock \| used_some \| used_up \| waste \| correction` | `db/schema-sqlite.sql` §10 CHECK; docs/08 §4.3; docs/09 §3.3/§8.4; AGENTS.md | Exact six-value CHECK; docs/08 and docs/09 state "no `consume`, no `adjustment`"; the retired names appear only as historical labels or negative probes (docs/08 §11.6 #2-#3) | **PASS** |
| B | Exactly three usage-review choices, mapping equal to docs/06 §3.4 including the no-op rows | docs/09 §8.1, §8.2, §8.3, §8.8 vs docs/06 §3.4 | Three choices, no fourth "Not tracked"; `have`→low/out, `low`+Used it = no event ("already low"), `unknown`+used → low/out, `out`+Used it = disabled, `out`+Used it up = no event, `unknown` default = Didn't use; DDL makes all four no-ops structurally unrepresentable (`from_status <> to_status`, reason/transition CHECKs) | **PASS** |
| C | `stock_status` / `stock_event` used consistently in docs/08, docs/09 and the DDL | DDL §6/§10; docs/08 §4.2/§4.3; docs/09 §3.3/§3.6/§8.5 | Consistent in all three; no `stock_events` plural; `inventory_items`/`inventory_transactions` appear only in superseded "before" columns (docs/08 §4.7, docs/06 §1/§3.3) | **PASS**, one exception: docs/06 §3.3's handoff note still prescribes `ingredient_stock` → **F-22** |
| D | docs/06 §9 Q4 contradiction | docs/06 §9 Q4, §3.4, §7 step 6 | Contradiction stood: Q4 called `have` + **Used it** → `low` "automatic" while §3.4 and the demo require it. Q4 default replaced; §3.4 untouched | **FIXED** (edit E1) |
| E | Locked label set + 3 dishes + 15 ingredients in docs/07 and the mockups | docs/07 §5.1/§7/§8; `palette.json`; PNGs 01-06; docs/06 §5 | All four label families present and correct in docs/07 §5.1/§7/§8 (`Have/Low/Out/Probably have`, `Ready/Probably have/Missing`, `Start cooking/Start and confirm items/Guide me anyway`, `Didn't use/Used it/Used it up`); 3 dishes and all 15 ingredient icons/rows match docs/06 §5; two cosmetic deviations (mockup chip letter case, shortened dish name) → **F-18**, **F-19** | **PASS** (2 low) |

---

## 2. Locked-decision compliance (L1-L6)

| Locked | Evidence across docs/06-09 + DDL | Verdict |
|---|---|---|
| L1 Flutter, not React | Every doc is Dart/Flutter; `docs/08` §2.1-§2.7 pin stack, packages, OS baselines; 01-05 retained only as the MySQL contingency (docs/08 §4.7, AGENTS.md) | **Compliant.** No "option menu" or evaluation table re-opens the platform. `docs/06` §1 "Dropped outright" is a change log, not a proposal. |
| L2 offline / one local kitchen | `kitchens` single row `id = 1`, `kitchen_uid`; no `users`, no network package; docs/06 §4, docs/08 §4.10, DDL §2 | **Compliant.** No doc smuggles auth or sync into P0; docs/06 §4's sync paragraph is explicitly a future migration. |
| L3 stock is presence | `stock_status.status` only, zero quantity columns; docs/06 A3, docs/08 §4.1/§4.9, docs/09 §1; P1 extension documented, not built | **Compliant.** `recipe_ingredients.quantity`/`unit_id` are display-only labels in the DDL comment and are read by no rule. No availability path does arithmetic (docs/08 §5.3 table, docs/09 §1 last paragraph). |
| L4 three dishes / 15 ingredients | docs/06 §5; docs/07 §11.3 icon list = 15; docs/08 §6.1-§6.2 fixtures; docs/09 §4.3 | **Compliant.** No 10th recipe, no 16th ingredient; the 9 designed-only dishes live only in docs/04 as a design record. |
| L5 advisory availability | docs/06 A1; docs/07 §7 screen 4 + §9; docs/08 §5.3; docs/09 §5.3; DDL `started_without_availability` + snapshot CHECK | **Compliant in text.** `AvailabilityService.evaluate` is the only entry point and `guideAnywayAllowed` is always true. Gap is on the *input* side, not the gate: **F-02**. |
| L6 no economy | No gold/EXP/streak/score table, field or service anywhere; docs/06 §5 "never cut: completion celebration" | **Compliant.** The celebration and SFX are the only "reward" (see **F-14** for its scheduling). |

**No reintroduced quantity, unit or scale path.** The only quantity-like data left is `recipe_ingredients.quantity`/`unit_id` as display prose (`docs/06` A6 `Base yield: 4`), and `docs/08` §4.9 confines the exact-quantity tier to an additive v2 migration while explicitly forbidding "add the columns \"for later\"". No doc proposes a serving selector, a keypad, a unit picker or a sufficiency comparison on the acceptance path.

**Rubric risk (L1).** Recorded once as an accepted risk with a one-line REST+MySQL contingency (docs/06 L1), repeated only as a risk-register item with a mitigation (docs/06 §6 R5) and as the single open question attributed to the user (docs/06 §9 Q1). docs/08 §10 #1 and AGENTS.md treat it as settled. **This is a contingency, not an unresolved blocker; attribution to the user is explicit.** No action.

---

## 3. Tri-state consistency matrix

| Rule | docs/06 | docs/07 | docs/08 | docs/09 | DDL | Result |
|---|---|---|---|---|---|---|
| Status domain `unknown \| have \| low \| out` | L3, A2 | §5.1 | §4.1 | §1, §8.1, §11.1 | `CHECK (status IN …)` ×3 | **identical** |
| `out` = missing | A1, A2 | §5.1 | §4.1, §5.3 | §4.2(6), §8.7 | engine rule (no column) | **identical** |
| `have`/`low` available, `low` warns | A1, A2 | §5.1, §5.4 | §4.1, §5.3 | §4.2(6) | n/a | **identical** |
| `unknown` flagged, never blocking | A1, A2 | §5.1, §5.2 | §4.1, §5.3 | §4.2(6), §8.7 | n/a | **identical** |
| Decay table `have→low`, `have/low/unknown→out`, `low`+Used it = no-op, `out` blocked-from-Used it | §3.4 (4×3) | §8.3 (4×3) | §4.3, §7.3 | §8.3 (4×3), §8.4 chain | reason/transition CHECKs + `from<>to` | **identical, and enforced by the DDL** |
| Availability states `ready / needs_confirmation / blocked` | A1 | §5.1, §7 | §5.3 | §11.1 enum | n/a | **identical** (Dart spelling `needsConfirmation` only) |
| Optional never blocks, never "missing" | A1, A2 | §5.2 | §5.3 | §4.2(6), §8.2 | `recipe_ingredients.is_optional` | **identical** |
| UI chip ↔ stored status | §3.4 labels | §5.1 table + `palette.json` `states` | §4.1 table | §8.1 context tag | `stock_status.status` | **identical** |

**Conclusion: the tri-state model is the strongest part of the package.** Four documents, one palette and the DDL agree cell-for-cell, and the DDL makes the no-op rows impossible rather than merely forbidden. Nothing in this area needs a fix.

---

## 4. Conflicts with `docs/01-05` and the amendment package

| Rule (02) | Current 02 text | Amendment | Applied? | Result |
|---|---|---|---|---|
| R8 + R11 | availability is a hard precondition; "a new session may start only for an available recipe" (02 §2, §3, §6 row) | A1/A2: advisory `ready/needs_confirmation/blocked`, **Guide anyway** for `blocked`, `unknown` does not block | **No — "Proposed, not applied"** (docs/06 §3) | Implementation docs follow A1/A2 (docs/07 §9, docs/08 §5.3, docs/09 §5.3); 02 still says the opposite → **F-01** |
| R12 | "Timer state is not persisted" (02 §2, §6 "App closed during a timer") | A5: absolute UTC start + derived remaining; "elapsed by N minutes" on return | No | docs/06 A5, docs/08 §4.5/§4.7, docs/09 §6, DDL all agree; 02 §6's edge-case row is superseded but still readable as current → **F-01** |
| R4 / R5 / R6 / R14 | canonical units compared; balance + signed ledger; non-negative balance; deduct each balance atomically | A3: status + append-only event, six reasons, no balance, no non-negativity to violate | No | docs/08 §4.3 + DDL enforce the amended model; 02 §4 reason table still lists `consume`/`adjustment` → **F-01** |
| R9 | required quantities scale by `chosen_servings / recipe.servings` | A6: base yield only, scaling P1 | No | No serving selector in docs/07 §7 screen 4, no scaling in the DDL, `servings` display-only → consistent with A6, 02 unamended → **F-01** |
| R16 | "No destructive UI" (no delete screens) | A7: one exception, **Reset demo data**, confirmation-gated, one transaction | No | docs/07 §7 screen 10, docs/08 §4.10(5) and docs/06 §7 both depend on it; **Matches A7**, but 02 R16 still forbids it → **F-01**. **F-26** adds that Reset during an active session is unspecified. |
| R1 / R2 / R15 | one kitchen per user; atomic register; per-user scope | A7: single on-device kitchen, atomic first run, no access scope | No | DDL has no `users`, no `owner_user_id`; docs/08 §4.10(1) makes first run one transaction; **matches A7**, but 02 R1/R2/R15 have no operand → **F-01** |
| R7 / R10 / R3 | curated 5-appliance list; recipe immutability; closed catalog | survives unchanged | n/a | DDL seeds 5 equipment rows; no recipe write path; docs/09 §2.1 declarative steps; **compliant** |
| R13 | consume on confirmation only | survives in principle; A4 changes the *form* of the confirmation (status choice, not amount) | No | docs/09 §8.5 finishes with a confirmation-driven write and nothing changes stock before Confirm; **compliant in behaviour** |

**Finding F-01 is the governance issue, not a modeling issue.** `docs/06` §10 supplies the precedence rule that lets implementation proceed ("this document wins for the MVP; implementation should follow the §3 text now"), so Phase A is not blocked. But a reader who opens `docs/02` for the rules will get the pre-pivot contract, and `GLOSSARY.md` still defines `Inventory transaction` and `Stock level` — the two terms docs/06 §3.9 retires. Applying A1-A10 is a documentation task the owner owes before freeze (condition C1).

---

## 5. Cross-document checks that pass (and the one exception each)

| Check | Evidence | Observed | Result |
|---|---|---|---|
| Engine persisted fields ↔ SQLite columns | docs/09 §3.1-§3.4 vs DDL §8-§10 | `status`, `current_step_number` (no upper bound), `timer_started_at`, `timer_duration_seconds`, `last_seen_at`, `started_without_availability`, `missing_requirements_json`, `session_step_choices`, `recipe_step_variants` and the step columns are all present | **all engine-side fields present**; 2 naming deviations (docs/06 §3.5's `timer_step_number`/`timer_started_at_utc` vs the DDL's two timer fields) → **F-22** |
| UI screens ↔ engine states | docs/07 §6/§7 (10 screens + modal) vs docs/09 §5.1/S1-S9, §6.3 | 10/10 map; timer phases idle/running/done/overrun identical in docs/07 §9.4 and docs/09 §6.3; review sentinel `N+1` matches docs/07 §9.4's "Continue from the final step opens the review" | **Consistent**; 1 gap: History's "Open a session (read-only)" has no route/screen → **F-13** |
| Asset budget ↔ screens | docs/07 §11 vs docs/09 §4.4; 10 screens | 74 P0 assets = 4 backgrounds + 7 step sprites + 3 stamps + 2 variant icons + 15 ingredient icons + 5 equipment icons + 4 mascot + 26 chrome + 1 atlas + 7 SFX; counts re-add to 74 and ≈17 h (15-20 h); composition rule 1 background + ≤3 sprites + 1 panel; no per-dish/per-step art (§11.4) | **Consistent**; 2 exceptions: the budgeted `step_wait_air_fryer` is on no shipped path while docs/09 §4.4 allows "6 composites + ≤2 overrides"; SFX priority → **F-14** |
| Repository interfaces ↔ UI needs | docs/08 §5.2 vs docs/07 §7 screen requirements | Every screen is served (`listRecipes`/`findBySlug`/`loadGuide`, `getStatuses`/`setStatus`/`listEvents`, equipment catalog/owned, kitchen get/rename, session history, `resetDemoData`, `GuideStore`) | **Complete except one input**: no repository or engine parameter carries the cook's variant choice → **F-02** |
| Fixtures ↔ 3-dish cut line | docs/08 §6.1-§6.2 (4 JSON files) vs docs/06 §5/§7 | 3 slugs, 15 ingredient codes, demo statuses and equipment match; `bay leaf out` reproduces the demo's Guide-anyway moment; 15/15 codes match docs/07 §11.3 | **Consistent** |
| Tests ↔ phases | docs/09 §12 (T-01..T-59) vs docs/08 §7.1/§8 | docs/09 assigns T-01..T-33 to Phase A and T-34..T-59 to Phase B; docs/08's Phase B gate cites only T-34..T-54 and Phase C's cites only T-05..T-10 | **Gap**: T-55..T-59 are ungated → **F-23** |
| Fixtures-first swap | docs/08 §6.3-§6.4: one swap point `lib/app/di.dart`, parity test with 4 assertions | No screen, widget or engine file imports a concrete repository; Phase A has zero SQL | **Compliant.** This is the strongest feasibility decision in the package. |

---

## 6. Vocabulary audit

| Term | Banned by | Occurrences in `docs/06-09` normative text | Verdict |
|---|---|---|---|
| `balance` | docs/06 §3.9 | only in superseded-rule quotes, change-log "before" cells and docs/09 §0's "old rule" column (all exempt per §3.9 scope note) | **Clean** |
| `quantity_delta`, `inventory_items`, `inventory_transactions` | §3.9 / naming addendum C | only in docs/06 §3.3/A8 (before), docs/08 §4.7 (MySQL column), docs/06 §1 (change log) | **Clean** (before-columns) |
| `deduct` | §3.9 | docs/06 change log + L3 residual risk ("cannot auto-deduct"); docs/07 §5.3 "No numbers, anywhere on the acceptance path"; docs/08 §4.7 "no balance" note | **Clean** (exempt contexts) |
| `sign in` | §3.9 | docs/06 §5 screen 1 "Replaces: Sign in / Register" (change log) only | **Clean** |
| `inventory transaction` | §3.9 | docs/06 §3.9 (the retirement itself) and docs/09 §1 definition note | **Clean** |
| `stock level` | §3.9 | docs/09 §1 line 44 used it as a retained term and then redefined it as the presence state | **Fixed** (edit E5) |
| `Not tracked` | docs/07 §5.1: internal state name only, never displayed beside "Probably have" | docs/07 §5.1/§13.3 (as a rejected concept), docs/09 §8.1/§8.8/E10/§14 (as a *rejected fourth choice*), `design/palette.json` role strings ×3 + one contrast `use` | **Clean in docs**; **F-21** on the palette metadata |
| `ingredient_stock` | naming addendum C | docs/06 §3.3 handoff note (prescribes it); docs/08 §4.2/§12 Q8 + docs/09 §3.6 (flag it as superseded) | **F-22** |
| `stock_events` (plural) | addendum C | none | **Clean** |
| Locked UI labels | docs/06 §3.4 | docs/07 §5.1/§7/§8 verbatim; `palette.json` `states`/`availability` labels verbatim; mockups 01/02/05/06 verbatim (letter case differs — see **F-18**) | **Compliant** |

---

## 7. Mockup review (`design/mockups/`, six PNGs)

All six are **540 × 960 RGB** = 180 × 320 art units at 3×, art drawn in integer 3-px blocks, all colours taken from the 16-token palette, headings/labels/badges/numerals in the 5×7 bitmap face and all prose in a TrueType face at ≈18 dp equivalent. No numeric input, keypad, decimal field or unit picker appears on any screen; numbers are limited to timers, step counters, servings, item counts and read-only instruction text. No caricature, no flag iconography; the mascot is a palayok.

| PNG | Must show (per docs/07) | Observed | Verdict |
|---|---|---|---|
| `01_cook_now` | 3 cards, availability badges only, equipment line, tab bar, no chips on cards | `MISSING` (Adobo) + `READY` ×2, "Maria's Kitchen \| 3 dishes", "STOVETOP + AIR FRYER", 4-tab bar, gear | **Pass**; dish named "Crispy Pork Belly" (**F-19**) |
| `02_recipe_detail` | hero, base yield, MISSING panel, `Guide me anyway`, no serving selector, variant control, optional line | MISSING panel + "Bay leaf is out. / 1 MISSING ITEM", 5 status rows (4 Have, 1 Out), `GUIDE ME ANYWAY` + "Starts anyway and records: bay leaf missing", footer card with `PROBABLY HAVE` + `PAN-FRY / AIR-FRY`, no serving selector | **Pass**; optional line clipped by the panel edge (**F-19**); "Probably have" footer is a state sample, not the demo snapshot (docs/07 C5 — accepted) |
| `03_guide_prep` | step card anatomy, no-auto-advance, tap to continue | `STEP 1 OF 7`, progress bar, prep scene + mascot bubble "I wait for your tap.", [1] badge, instruction, detail, "No timer on this step", `CONTINUE`, "IT WAITS FOR YOUR TAP" | **Pass**; progress fill ≈1/7 at step 1 (**F-17**) |
| `04_guide_timer` | waiting mechanic: timer + tap to continue | `STEP 2 OF 7`, running ring `4:24 LEFT` / `RUNNING` / `OF 8 MIN`, caution "Hot oil.", "TIMER FINISHED / Timer done. / Tap to continue. / THE STEP WAITS FOR YOUR TAP", "SCREEN STAYS AWAKE / TAP ADVANCES - NO AUTO" | **Pass on the required mechanic**; running and finished states are shown simultaneously (**F-15**); order badge missing (**F-19**) |
| `05_review` | three-way checklist, one choice per line, disabled no-op, decay note, no numbers | `Didn't use / Used it / Used it up` per line, selected states, `Used it` disabled greyed on the `out` line, status tags, decay note "Used it: Have -> low. Used it up: -> out." | **Pass**; 5 of Adobo's 8 lines shown with no scroll cue (**F-16**); choice buttons ≈19 au / 38 dp (**F-05**) |
| `06_stock_setup` | four chips per ingredient, all four states, unknown hint, no keypad | `INVENTORY / 15 ITEMS`, search, category chips, 5 rows showing Have / Low / Out / Probably have, "tap to confirm" on calamansi, toast "Saved. No numbers to type." | **Pass**; chips ≈15 au / 30 dp with no room for a 24 au hit rect (**F-05**) |

`design/palette.json`: 16 colours, `states` and `availability` label sets identical to docs/06 §3.4, 18 contrast pairs all AA+ and 4 forbidden pairs, matching docs/07 §2.1-§2.2. The only defects are metadata strings (**F-21**).

**Rulings on the conflicts `docs/07` §13.3/§13.4 referred to this review:**

| Item | Ruling |
|---|---|
| `docs/07` C1 "Not tracked" chip | **Closed.** `docs/09` §8.1/§9 already say **Probably have**; "Not tracked" survives only as an internal state name. Label set stands. |
| `docs/07` C2 review mapping | **Closed.** `docs/09` §8.3 matches `docs/06` §3.4 row-for-row, including `low` + Used it as a no-op and the disabled `out` + Used it. No table needs picking. |
| `docs/07` C3 six vs seven steps | **Closed by edit** (E3/E4): the shipped Adobo is 7 steps; the mockups were already right. |
| `docs/07` C4 equipment picker vs screen 8 | **Confirmed:** the picker is a modal inside screens 1 and 10 (P0), the 10 screens are `docs/06` §5's. Screen count stays 10. |
| `docs/07` C5 mockup 02 footer at **Probably have** | **Accepted as-is.** Mockups illustrate states; the demo snapshot (Adobo Missing, Sinangag Ready, Crispy Pork Belly Ready) is the locked one. No re-render required; the README already says so. |
| `docs/07` C6 44/48/56 dp | **Open, decided here as a condition:** one floor, 48 dp hit / 56 dp primary → **F-05**, condition **C6** in §11. |
| `docs/07` C7 asset keys used by the engine | **Checked:** every key `docs/09` §2.5/§4.3 derives (`step_prep_none`, `step_heat_stovetop`, `step_cook_stovetop`, `step_wait_stovetop`, `step_finish_none`, `step_cook_air_fryer`, the pan-fry override `step_cook_stovetop`) exists in `docs/07` §11.3; `step_wait_air_fryer` is budgeted but unused → folded into **F-14**. |
| `docs/07` C8 celebration art | **Accepted:** reuse the dish stamp's 4-frame animation; no new sprite and no extra hour. |
| `docs/07` §13.4 Q1 unknown choices | **Closed:** three choices (docs/06 §3.4). |
| `docs/07` §13.4 Q2 visible control vs hit rect | **Answered by F-05:** the 48 dp floor is a *hit rect*; visible size may be smaller only where it does not overlap a neighbouring target. |
| `docs/07` §13.4 Q3 a fourth mockup | **Not required.** Six images cover the three badges, four statuses, both guide states and the review; the celebration is specified in §10 #6 and needs no screenshot for the report. |
| `docs/07` §13.4 Q4 mute toggle | **Confirmed P1** and not needed for the demo (same ruling as **F-14**). |

---

## 8. Feasibility for one semester

| Question | Finding |
|---|---|
| Is the 3-dish MVP achievable? | **Yes, with margin if the sequence holds.** The cut removes 75 % of the content (3 of 12 dishes, 15 of 45 ingredients) and 100 % of the server (no auth, no API, no network). What remains is 10 screens, ~50 Dart files (docs/08 §3.1), 15 tables, 59 engine tests and 3 recipes. The fixtures-first Phase A (docs/08 §6) means the demoable slice never waits on SQLite, and Phase B is a one-file swap plus a parity test. |
| Is the P0 asset budget realistic? | **Yes at placeholder quality.** 74 assets ≈ 17 h (range 15-20 h) with a composition rule (1 background + ≤3 sprites + 1 panel), 7 step sprites instead of 19 step illustrations, and one celebration reused by all dishes. The count and the hours re-add correctly. Caveat: 7 of the 74 are SFX that docs/08 schedules as optional Phase D (**F-14**), so the demo-critical floor is 67 assets ≈ 15.6 h. |
| Does any doc smuggle in auth, sync, economy, a recipe editor, or the other 9 dishes? | **No.** Auth/sync appear only as a future migration paragraph (docs/06 §4) and a documented contingency (L1); there is no economy field, table or copy anywhere; no write path for recipes (`docs/02` R10 survives); the 9 designed dishes exist only in docs/04 as a record. `docs/07` §12's Tagalog `instruction_tl` is marked P1 but has no schema field (**F-25**). |
| Is the plan schedulable? | **Not yet.** `docs/06` §5's cut order fires on `freeze − Nd` where `freeze` is "the demo-content freeze date set by T3", and `docs/06` §6 R1/R4/R9's early-warning signals use the same date — but `docs/08` §8 defines no freeze date, no dated milestone and no per-phase hour ceiling (**F-06**). The plan's *shape* is right; its *clock* is missing. |
| Anything that cannot survive the semester? | One locked success criterion: docs/06 §8 #13 (cooking oil required for pan-fry, optional for air-fry) has no representation in the engine or schema (**F-03**). Recommended: re-scope it rather than build a variant-ingredient table. |
| Toolchain evidence | "Flutter 3.50.0" is asserted from two official URLs (docs/08 §2.1) and could not be verified here (`flutter` exits 1 in this sandbox, no network used). docs/08 already requires recording `flutter --version` at scaffold, which closes it. |

---

## 9. Findings

Severity: **blocker** = downstream work must not start; **high** = contract gap that must close before the named gate; **medium** = ambiguity that will produce rework or a demo surprise; **low** = hygiene.

| ID | Sev | File / section | Issue | Required fix | Owner |
|---|---|---|---|---|---|
| **F-01** | high | `docs/06` §3, §10; `docs/02` §2-§6; `GLOSSARY.md` | A1-A10 are "Proposed, not applied", so `docs/02` still normatively states the opposite of every implementation doc: R8/R11 hard gate, R12 "timer state is not persisted", R4 canonical-unit comparison, R5/R6 balance + non-negativity, R14 decimal deduction, R9 scaling, R16 "no destructive UI". GLOSSARY still defines `Inventory transaction` and `Stock level`. docs/06 §10 supplies the precedence rule, so Phase A can start, but the rule source is pre-pivot. | Apply A1-A10 to `docs/02`, A10 to `GLOSSARY.md`, A8/A9 to `docs/03`/`docs/04`; add one "superseded by docs/06 for the MVP" line to the 02/03/04 headers. | user (via domain-analyst) |
| **F-02** | high | `docs/09` §4.2, §11.3; `docs/07` §4, §7 screen 4; `docs/06` §7 step 3; `docs/08` §2.4, §5.3 | The cook's variant choice has no way into the engine. The demo requires toggling Pan-fry/Air-fry and seeing the required-equipment chip and first step change (docs/06 §7 step 3); docs/07 §7 screen 4 ships a "variant segmented control" and docs/08 §2.4 routes `/recipes/:slug?method=pan_fry`. But `planPath(recipe, ownedEquipment)` and `start({recipeId, guideAnyway, nowUtc})` take no variant input, and §4.2 step 1 gives the canonical path absolute priority — so an explicit pan-fry pick silently reverts to air-fry at start, and `AvailabilityService.evaluate` cannot preview the picked path. | Add an optional requested-variant / per-group equipment map to `planPath`, `start` and `AvailabilityService.evaluate`; pin it in `session_step_choices`; reject an unowned requested appliance with the matching `equipment:`/`group:` code. Alternatively delete the picker and document it as read-only. Re-baseline T-05..T-10. | engine-designer + flutter-architect |
| **F-03** | high | `docs/06` §5 (ingredient table), §8 #13; `docs/09` §4.1; `docs/08` §4.4, §12 Q3; DDL `recipe_ingredients` | One locked success criterion is unimplementable: cooking oil is `R` for pan-fry and `O` for air-fry (docs/06 §5), and criterion #13 tests exactly that. Variants carry copy/duration/sprite deltas only and "cannot change `ingredient_refs`" (docs/09 §4.1); the schema has one static `is_optional`. docs/08 Q3 already recommends treating #13 as unmet. | Re-scope #13: static `is_optional` (recommend optional, matching the canonical air-fry path) and reword #13 to "pan-fry vs air-fry differ in instruction, duration and sprite; the unselected variant's copy is not shown". Record it in docs/06 §5's note. | user + docs/06 owner |
| **F-04** | high | `docs/06` §5 (dish 3 row), §8 #14; `docs/09` §4.3, T-06, Q1, lint L10; `docs/04` §8.3 as amended by A9 | Dish 3's equipment requirement is contradictory in three places. docs/06 §5 lists `stovetop + air_fryer` and #14 expects a `blocked` recipe with `equipment:air_fryer` when the air fryer is unowned; docs/09 §4.3 and T-06 expect a stovetop-only kitchen to silently take the pan-fry variant and be **available**. Both cannot hold. Additionally docs/09 Q1's recommended `recipe_equipment = {stovetop}` violates docs/09's own lint L10 (a canonical step's equipment must be listed in `recipe_equipment`), and 04 §8.3's weakened coverage query would not see an appliance referenced only by a variant. | Pick one: (a) recommended — `recipe_equipment = {stovetop}` only, widen L10 for canonical steps inside a `variant_group`, make 04 §8.3's coverage count `recipe_step_variants`, and rewrite #14 as "air fryer unowned ⇒ `ready` via the pan-fry variant, no missing item"; or (b) keep both rows and drop T-06's auto-pan-fry, making the picker mandatory. | user + docs/06 owner + seed author |
| **F-05** | high | `docs/06` §6 R6; `docs/07` §4, §13.3 C6; PNG 05, PNG 06 | Tap targets are three different numbers and the delivered controls miss all of them. docs/06 §6 R6 mitigates with "≥ 56 dp tap targets"; docs/07 §4 sets "hit rect ≥ 24 au (48 dp)"; docs/07 §4 sizes the ingredient chip at 15 au while C6 says chips render "22 au (44 dp)". Measured in the mockups: inventory chips ≈15 au (30 dp), review choice buttons ≈19 au (38 dp), primary button 26 au (52 dp); four chips plus a 24 au hit rect cannot share a 168 au row at the current 28 au pitch. | One floor (recommend **48 dp hit everywhere, primary 56 dp**), re-derive the inventory chip row (24 au chips, or 2×2) and the review row (24 au buttons, scroll the list), bump the primary to 28 au, and delete C6's "22 au" in favour of §4's number. Re-render 05 and 06. | pixel-designer |
| **F-06** | high | `docs/06` §5 cut order, §6 R1/R4/R9; `docs/08` §8 | The sanctioned risk control cannot fire: every cut trigger and three early-warning signals are expressed as `freeze − Nd`, and `docs/06` §5 defines `freeze` as "the demo-content freeze date set by T3" — but docs/08 §8 has no freeze date, no dated milestone, and no per-phase hour ceiling (the only estimate in the package is the art budget's ≈17 h). | Add a freeze date, four dated milestones (A/B/C/D exit gates) and a per-phase hour ceiling to docs/08 §8; cite the same date from docs/06 §5/§6. | flutter-architect + user |
| **F-07** | medium | `docs/06` A1/A2; `docs/08` §4.4, §12 Q4; `docs/09` §3.1, §5.3, T-13; DDL §8 comment | `missing_requirements_json` has three incompatible shapes: stable code strings (docs/06 A2 "list of stable codes `equipment:air_fryer`", docs/08 §4.4), an object array `{kind, id, alternatives}` (docs/09 §3.1 and the DDL's comment example), and "exactly as returned … with alternatives" (docs/09 §5.3). T-13 asserts byte-identical persistence, so the shape has to be one thing. | Adopt the code-string array (docs/06 A2 is authoritative): update docs/09 §3.1/§5.3 and the DDL comment; state that group alternatives are not persisted because the pinned path records the choice. | engine-designer + flutter-architect |
| **F-08** | medium | `docs/06` §8 #5 vs §3.6 A6; `docs/07` §5.3 | Criterion #5 says "the only numbers are read-only display strings **inside instruction text**", but the same package requires `Base yield: 4` on the recipe detail (§3.6 A6), timer digits, step counters and item counts — and the mockups show all four. docs/07 §5.3 lists them correctly; docs/06's criterion does not. | Reword #5: "zero numeric input fields on Inventory, Recipe detail and Usage review; every number shown is read-only (base yield, timer, step counter, item count, instruction text)." | user (docs/06) |
| **F-09** | medium | `docs/06` §4 (Identity row); DDL §2-§3; `docs/08` §4.2, §12 Q5 | The kitchen model promises `display_name`, `schema_version` and `seed_version` on the kitchen row; the DDL has `name` and keeps both versions in `schema_meta`. Two sources of truth for `schema_version`, and the field the domain model names (`display_name`) does not exist. | Amend docs/06 §4's Identity row to `kitchen_uid`, `name`, `created_at`, `updated_at` + "versions live in `schema_meta`" (docs/08 Q5 default). | user (docs/06) |
| **F-10** | medium | `docs/06` A4; `docs/07` §8.2, §8.4; `docs/09` §8.2, E15 | The required-line default is not locked by docs/06 (it locks only "optional defaults to Didn't use"), yet docs/07 §8.4 and docs/09 §8.2 default every required `have`/`low` line to **Used it**. Consequence: a cook who taps Confirm without touching a row demotes every required `have` to `low` against the demo script's "three taps" framing, and a tester reading docs/06 cannot tell whether that is intended. | Add one sentence to docs/06 A4 locking the required-line default, and adjust the demo script's "three taps" copy; or default every line to **Didn't use** and let N+1 taps be real. | user (docs/06) |
| **F-11** | medium | `docs/06` A4; `docs/09` §8.4; `docs/07` §8.1, §8.2 | The "I actually have it" restock correction is normative in docs/06 and docs/09 (a chained `restock` event inside the completion transaction) but has **no control** in the review layout: docs/07 §8.1's sketch shows one row of three buttons, §8.2's N+1 tap budget counts three choices only, and the affordance appears in one prose sentence. Implementers cannot build it from the spec. | Specify the control (recommend: tap the line's status tag → "I have it" confirm), its hit target, its position, and its effect on the tap count; add it to §8.1's layout. | pixel-designer |
| **F-12** | medium | `docs/08` §4.3, §5.2; `docs/07` §5.2, §7 screen 7 | Inventory's one-tap chip change must pass a `StockReason` to `setStatus`, but no document maps a chip tap to a reason. `initial`, `restock`, `used_some`, `used_up`, `waste` and `correction` overlap for the same tap (e.g. `have→out`), and `stock_rules_test` (docs/08 §7.1) is supposed to assert the mapping that does not exist. | Add a 5×5 chip-tap → reason table to docs/08 §4.3 (recommend: from `unknown` → `initial`; →`have` from `low`/`out` → `restock`; →`low` → `used_some`; →`out` → `waste`, with `correction` reserved for a non-chip correction path). | flutter-architect |
| **F-13** | medium | `docs/07` §7 screen 9; `docs/06` §5 screens; `docs/08` §2.4 routes | History's primary action is "Open a session (read-only)", but the locked 10 screens contain no session-detail screen and the router has no such route. Either an 11th screen exists (breaking the locked count) or the table describes an interaction nobody has specified. | Make it an expanding read-only row inside History (no new route), or add `/history/:sessionId` and record the screen-count change. Recommend the expandable row. | pixel-designer + flutter-architect |
| **F-14** | medium | `docs/07` §11.1, §11.3, §10; `docs/08` §2.6, §8 Phase A/D | The 7 SFX are counted inside the "74 P0 assets" and priced (~1.4 h), but docs/08 schedules sound as P1/Phase D and Phase A's file list has no `sound_service` implementation. The demo-critical floor and the published P0 total are two different numbers. | Mark the 7 SFX "P0-optional (Phase D)" and state the demo floor as 67 assets ≈ 15.6 h; or move sound into Phase A. Also fix the step-sprite count: 7 budgeted keys include `step_wait_air_fryer`, which no shipped path uses, while docs/09 §4.4 allows "6 composites + ≤2 overrides". | pixel-designer + flutter-architect |
| **F-15** | low | PNG `04_guide_timer.png`; `docs/07` §9.4 | The mockup shows two mutually exclusive timer states at once: a running ring at `4:24 LEFT` of 8 min **and** a "TIMER FINISHED / Timer done" panel. §9.4 defines four exclusive phases. | Split into 04a (`running`) and 04b (`done`/`overrun`), or caption the finished panel as the later notification moment. | pixel-designer |
| **F-16** | low | PNG `05_review.png`; `docs/07` §8.1-§8.2 | Adobo has 8 review lines (5 required + 3 optional); the mockup shows 5 and gives no scroll cue, so the spec's "8 lines → 9 taps" cost cannot be seen. | Show all 8 lines, or a clipped row plus a scrollbar, so the tap cost is visible. | pixel-designer |
| **F-17** | low | PNG `03_guide_prep.png`, `04_guide_timer.png`; `docs/07` §9.4; `docs/09` §7.1, T-30 | The progress bar is rendered as `step / N` (≈1/7 at step 1; the README states 04 is "progress bar at 2/7" for step 2), but docs/09 §7.1/T-30 and docs/07 §9.4 define `(k − 1) / N` (step 2 = 14 %, step 3 = 28 %, 100 % only at review). | Re-render with the engine formula, or change the formula and T-30 — they must agree. | pixel-designer |
| **F-18** | low | PNG `02`, `05` vs `06`; `docs/07` §3.1, §4, §5.1 | The same status information is set in two type styles: `HAVE`/`OUT` in the uppercase-only bitmap face (02, 05) and `Have`/`Low`/`Out`/`Probably have` in title-case TrueType (06). docs/06 §3.4 locks title case; docs/07 §3.1 sends "labels" to the bitmap face, which has no lowercase. | Decide per component (labels vs prose) and state it: recommend title-case system sans for status chips/badges/tags so the locked label strings appear verbatim. | pixel-designer |
| **F-19** | low | PNG `01`, `02`, `04`; `docs/07` §9.1; `docs/06` §5 | Three cosmetic defects: cards say "Crispy Pork Belly" for the locked "Air-Fried Crispy Pork Belly"; 02's "OPTIONAL: OIL, PEPPER, SUGAR" is clipped by the panel edge; 04's step card has no order badge while 03's does. | Re-render with the locked dish name, wrap/trim the optional line, restore the order badge. | pixel-designer |
| **F-20** | low | `docs/07` §13.3 (C1/C2/C3), `docs/07` §13.4 Q1; `design/mockups/README.md` "Known limits" | Stale conflict records: C1/C2 and the README still say docs/06 and docs/09 disagree on `low` + Used it and on a fourth "Not tracked" choice; C3 and docs/08 Q11 still quote docs/06 as saying six steps. docs/09 §8-§9 and docs/06 §5/§7 were corrected. | C1/C2/C3 and docs/08 Q11 are updated by this review (edits E8-E10); the mockup README lines are outside this task's edit scope and need the same one-line replacement. | pixel-designer |
| **F-21** | low | `design/palette.json` `colors.ink_soft/cream_dark/slate.role`, `contrast[3].use` | The `unknown` state is described as "Not tracked" in four metadata strings while `states.unknown.label` and the specs say "Probably have". docs/07 §5.1 forbids presenting both for one row. | Replace "Not tracked" with "unknown (Probably have)" in the role/use strings. No colour change. | pixel-designer |
| **F-22** | low | `docs/06` §3.3 handoff note, §3.5; `docs/08` §4.2, §12 Q8; `docs/09` §3.6 | docs/06's proposed A3 handoff still prescribes `ingredient_stock(kitchen_id=1, …)` and A5 still names `timer_step_number` + `timer_started_at_utc`; the locked schema is `stock_status`, `timer_started_at` + `timer_duration_seconds` with **no** step id (a live timer belongs to `current_step_number`). docs/08 and docs/09 already record the deviation, so the amendment text is the last contradicting artifact. | When A3/A5 are applied to docs/02, rename the hint to `stock_status` and drop `timer_step_number`, noting that a step change clears the timer. Record the three deviations as accepted. | user (docs/06) |
| **F-23** | low | `docs/08` §8 (Phase B gate) vs `docs/09` §12 | docs/09 assigns T-34..T-59 to Phase B; docs/08's Phase B exit gate cites only T-34..T-54, and Phase C's gate cites only T-05..T-10. T-55..T-59 (abandon-then-restart, seed-missing, denied notification, DST, review-kill) are ungated. | Change the Phase B gate to T-34..T-59. | flutter-architect |
| **F-24** | low | `docs/08` §3.1 (Phase A file list); `docs/06` L6/§5; `docs/07` §10 #6 | The completion celebration is P0 and on the "never cut" list, but the exact Phase A file list has no celebration widget (`lib/features/guide/` lists only the screen, the review screen and the controller). | Name the file (`celebration_overlay.dart`) in §3.1. | flutter-architect |
| **F-25** | low | `docs/07` §12 (Tagalog row) | P1 Tagalog needs an `instruction_tl` field per step; no other document or the DDL has it, so the row reads like a shipped requirement. | Mark it "P1, schema v2, not in this package" or remove it. | pixel-designer |
| **F-26** | low | `docs/06` A7; `docs/07` §7 screen 10; `docs/08` §4.10(5) | Reset demo data deletes `stock_event` and `cooking_sessions` unconditionally, so invoking it mid-cook silently destroys an active session. docs/08 §4.10(4) already defers content updates while a session is `in_progress`; Reset has no such guard, and the confirm dialog's content is unspecified beyond "names what will be lost". | Block Reset while a session is `in_progress` (offer Resume/Abandon first) or name the active session in the dialog; state it in docs/07 §7 screen 10 and docs/08 §4.10(5). | user + flutter-architect |

---

## 10. Edits applied

All edits are one line or one table cell. No section was rewritten, and `docs/01-05`, `README.md`, `GLOSSARY.md`, `db/schema.sql`, `db/seed-reference.sql`, `db/schema-sqlite.sql` and `design/` are untouched.

| # | File | Section | Change | Why |
|---|---|---|---|---|
| E1 | `docs/06` | §9 Q4 (question + default cells) | Question reworded to ask about time/heuristic decay; default replaced with "transitions are driven only by the cook's explicit usage-review choice; no time-, heuristic-, or background-driven degradation" | Captain addendum D: §9 Q4 called `have` + **Used it** → `low` "automatic" while §3.4 and §7 step 6 require it. §3.4 unchanged. |
| E2 | `docs/06` | Header reading conventions | `A1-A11` → `A1-A10` | Broken cross-reference: §3 and §10 define exactly A1-A10 |
| E3 | `docs/06` | §5 "why these three" (Adobo row) | "Already fully authored … 6 steps" → "already authored in 04 §5 (6 steps); docs/09 §2.5 splits 04's step 2, so the shipped recipe is 7 steps" | docs/09 §2.5 and docs/08 §8 both make the split normative; the cell claimed six shipped steps |
| E4 | `docs/06` | §7 demo script row 5 | "step 2/6" → "step 2/7" | Same split; the mockups render "STEP n OF 7" and the engine's N is 7 |
| E5 | `docs/09` | §1 closing paragraph | Removed `stock level` as a retained GLOSSARY term; the presence state is stated as **stock status** | `stock level` is on docs/06 §3.9's banned list and the sentence redefined it, which fails docs/06 §8 #17 |
| E6 | `docs/09` | §2.4 L6 | "`kind = wait` ⇔ duration" → "`kind = wait` ⇒ duration; only `wait`/`heat`/`cook` may carry a duration, `prep`/`finish` must be null" | L6 as written contradicted §2.3 (heat may time, cook expected to time), §2.5's own table (heat 480 s, cook 300 s) and the DDL's step-kind CHECKs |
| E7 | `docs/09` | §3.6 residual notes (third bullet) | Replaced the claim that `docs/08` §4.3 still names the retired reasons with "`docs/08` §4.3 now matches this section" | Broken cross-reference: docs/08 §4.3 already uses the final enum and writers |
| E8 | `docs/07` | §13.3 heading block + C1/C2 "Needs" cells | Added a one-line status note (C1/C2 were raised against earlier `docs/09` drafts; `docs/10` carries every ruling) and marked C1/C2 "Resolved" with the current `docs/09` behaviour | C1/C2 described `docs/09` content that no longer exists and still instructed a fix that is already in place |
| E9 | `docs/07` | §13.3 C3 (Needs cell) | "T5/author: update the demo script or the seed" → "Resolved: docs/06 §5/§7 now say 7 steps (edit recorded in docs/10)" | Stale after E3/E4 |
| E10 | `docs/08` | §12 Q11 (default cell) | "update the demo script copy" → "Resolved: docs/06 §5/§7 now say 7 steps (edit recorded in docs/10); seed copy uses 7" | Stale after E3/E4 |

---

## 11. Verdict, conditions, and what to build first

### Verdict: `approve-with-conditions`

The pivot package is internally coherent where it matters most — the tri-state model, the reason domain, the four-row review mapping, the absolute-UTC timer, the review sentinel, the 15-table DDL and the fixtures-first swap agree across four documents. Nothing found requires re-architecting. The conditions below are contract additions and one scope re-cut, all closable by the owners of the named documents.

### Conditions

| # | Condition | Before | Findings |
|---|---|---|---|
| **C1** | Apply the amendment package: A1-A10 into `docs/02`, A10 into `GLOSSARY.md`, A8/A9 into `docs/03`/`docs/04`, with a "superseded by docs/06 for the MVP" line on each header; add docs/06 §4's profile-column fix and §8's criteria #5 wording in the same pass. | Implementation freeze / first commit | F-01, F-08, F-09, F-22 |
| **C2** | Put a clock on the plan: a `freeze` date, four dated milestone dates for Phases A-D and a per-phase hour ceiling in docs/08 §8, cited by docs/06 §5/§6. | Phase A kickoff | F-06 |
| **C3** | Close the variant contract: a requested-variant input on `planPath`/`start`/`AvailabilityService` (or a read-only picker), re-baselined T-05..T-10 and criterion #14. | Phase C | F-02 |
| **C4** | Decide dish 3's equipment: `recipe_equipment = {stovetop}` + L10 widened for variant-group canonicals + 04 §8.3 coverage counting variants + criterion #14 rewritten (recommended), or keep both rows and make the picker mandatory. | Phase C | F-04 |
| **C5** | Re-scope criterion #13: static `is_optional` (recommend optional cooking oil), criterion reworded to copy/duration/sprite difference. | Phase C | F-03 |
| **C6** | One tap-target floor (recommend 48 dp hit / 28 au primary), re-derived inventory chip and review rows, docs/07 §13.3 C6's "22 au" deleted, mockups 05/06 re-rendered. | Phase A UI freeze | F-05, F-15, F-16, F-17, F-18, F-19, F-21 |
| **C7** | Settle the persisted shapes: `missing_requirements_json` code strings (docs/09 §3.1/§5.3 + DDL comment) and the chip-tap → reason table. | Phase B | F-07, F-12 |
| **C8** | Specify the review screen's remaining mechanics: required-line default locked in docs/06 A4, the restock control, and Reset's behaviour during an active session. | The usage-review screen | F-10, F-11, F-26 |

### What to build first

**Phase A exactly as `docs/08` §8 defines it: Chicken Adobo, fixtures only, no SQL.** One phone, one kitchen, ten screens' worth of shell, the 7-step guide, the persisted-start timer with lock/unlock, the three-choice review writing status events in memory, the guide-anyway start with a frozen missing-list, and Reset. It is the smallest slice that exercises every claim the demo makes (L3, L4, L5, L6 plus A4/A5), it needs only 67 demo-critical assets, and conditions C3-C5 do not touch it. Then Phase B (SQLite behind `lib/app/di.dart` + parity test), and only then dish 3 and the variant mechanic once C3-C5 are closed.

---

## 12. Open decisions for the user

Deduplicated; each has a recommended default. `docs/06` Q1-Q7 are still open and are folded in here.

| # | Decision | Recommended default | Source |
|---|---|---|---|
| D1 | Does the instructor accept Flutter + SQLite in place of React + MySQL, and by when? | Keep the pivot; record the deviation in README/report; ask in week 1. | docs/06 Q1 |
| D2 | Does Guide anyway cover missing **equipment** as well as missing ingredients? | Yes, both (as A1 writes it); the confirm sheet names each missing requirement. | docs/06 Q2 |
| D3 | Equipment picker: all 5 appliances or only the 2 the shipped dishes use? | All 5, the unused three marked "no dishes yet". | docs/06 Q3 |
| D4 | Is the single destructive action (Reset demo data) acceptable, and may it run mid-cook? | Accept it, confirmation-gated, and block it while a session is `in_progress`. | docs/06 Q5, F-26 |
| D5 | Demo on a physical phone or an emulator? | Physical Android phone; emulator + recorded backup as the fallback. | docs/06 Q6 |
| D6 | Do the 9 designed-only dishes stay in `docs/04`? | Keep them as the design record; only the shipped 3 get seeds. | docs/06 Q7 |
| D7 | Dish 3 `recipe_equipment`: stovetop only, or stovetop + air fryer? | Stovetop only; the air fryer is declared by the canonical variant-group step; criterion #14 becomes "ready via pan-fry". | F-04 |
| D8 | Keep variant-scoped cooking oil (criterion #13) or drop it? | Drop it: static optional oil, criterion reworded to copy/duration/sprite. | F-03 |
| D9 | Is the Pan-fry / Air-fry control a cook's choice or an automatic path? | A cook's choice, pinned at start; add the engine parameter. | F-02 |
| D10 | `missing_requirements_json`: code strings or objects with alternatives? | Code strings (`equipment:air_fryer`, `ingredient:bay_leaf`, `group:cook_method`). | F-07 |
| D11 | Usage-review defaults: pre-select **Used it** for required `have`/`low`, or start every line at **Didn't use**? | Keep **Used it** (it is what N+1 taps assumes), lock it in docs/06 A4 and fix the demo's "three taps" copy. | F-10 |
| D12 | Tap-target floor: 48 dp or 56 dp? | 48 dp hit minimum, 56 dp for the single primary action; re-derive the review and inventory rows. | F-05 |
| D13 | Are sound and local notifications P0 or P1? | P1/Phase D and never correctness-bearing; demo-critical asset floor is 67 ≈ 15.6 h. | F-14 |

---

## 13. Closing summary

**Verdict: `approve-with-conditions`.** The package is buildable as the Chicken Adobo vertical slice on fixtures today; eight conditions close the contract gaps before the gates they name.

- **Findings:** 26 total — **0 blocker, 6 high** (F-01…F-06), **8 medium** (F-07…F-14), **12 low** (F-15…F-26).
- **Addendum verification:** A reason enum **pass**, B three review choices **pass**, C table names **pass** (one docs/06 hint flagged), D Q4 **fixed**, E labels/dish/ingredient set **pass** with two cosmetic mockup deviations.
- **Edits applied:** 10 — docs/06 §9 Q4 (E1), docs/06 reading conventions A1-A10 (E2), docs/06 §5 Adobo 7 steps (E3), docs/06 §7 "step 2/7" (E4), docs/09 §1 banned term (E5), docs/09 §2.4 L6 (E6), docs/09 §3.6 cross-reference (E7), docs/07 §13.3 status note (E8), docs/07 §13.3 C3 (E9), docs/08 §12 Q11 (E10). No section rewritten; `docs/01-05`, `README.md`, `GLOSSARY.md`, `db/schema.sql`, `db/seed-reference.sql`, `db/schema-sqlite.sql` and `design/` untouched.
- **Conditions:** 8 (C1 amendments, C2 dated plan, C3 variant input, C4 dish-3 equipment, C5 criterion #13, C6 tap targets + mockups, C7 persisted shapes, C8 review mechanics + Reset).
- **Open decisions:** 13 (D1-D13), each with a recommended default.
- **Build first:** Phase A — Chicken Adobo, fixtures, 7 steps, persisted-start timer, three-choice review, guide-anyway snapshot, Reset.
