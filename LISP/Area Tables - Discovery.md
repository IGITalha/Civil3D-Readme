# Area Tables: Discovery (2026-11-26)

**Status:** discovery only. Nothing has been built or changed yet; we start building tomorrow. Decisions are logged in [DECISIONS.md](../DECISIONS.md) §B.

**Sources looked at:**
- **Manual:** the IGI Drafting Procedure Manual ("Calculating Areas", "Wetland / Upland Areas").
- **Routines on O:** `Area Required Timber Salvage.lsp` (ARTS), `Area Within Upland-Wetland.lsp` (AWUW), `Incidental Activities Table 2026.lsp` / `Label 2026.lsp` (IAT/IAL), `Freehold Area Text.lsp` (FAT), `DAREA.lsp`, and `Integrated Geomatics Library.lsp`.
- **Drawings:** jobs 26345, 26133, 23022, 23033, and the Well Site template.
- **Method:** every table read back, and every area polyline re-measured (shoelace with arcs, divided by CSF²).

---

## 1. How many area tables are there?

Page 1 of a **Crown** wellsite has **five area tables**. A **Freehold** page 1 has only the first.

| # | Table | Columns | Made by | On which plans |
|---|---|---|---|---|
| 1 | **AREA REQUIRED** | Hectares · Acres · Length | `ARTS` (Freehold: `FAT` text / `ARTS`) | All wellsite plans |
| 2 | **DISPOSITION AREAS (APPROXIMATE)** | Outside Existing (ha, ac) · Within Existing (ha, ac) | `ARTS` (same run) | Crown |
| 3 | **TIMBER SALVAGE (APPROXIMATE)** | New Cut (ha, ac) · Existing Cut (ha, ac). Tourmaline pipeline variant: New Cut · Existing Cut · Total, hectares only. | `ARTS` (same run) | Crown |
| 4 | **AREA WITHIN UPLAND / WETLAND** | Hectares · Acres for Upland, Wetland, Total | `AWUW` | Crown ("All Crown plans require a Wetland Upland table") |
| 5 | **INCIDENTAL ACTIVITIES** | ID · Activity · Latitude · Longitude · Hectares | `IAL` labels each workspace, `IAT` builds the table | When there are workspaces (TWS, campsite, borrow pit, log deck …) |

In the template, Crown Single / Multi Well and Crown-Hybrid have all five as placeholders; the Freehold Single / Multi Well layouts only have AREA REQUIRED.

**Other tables on the plans that are *not* area tables** (out of scope, but they sit next to them):
- **Well coordinate table:** one per well, with NAD83 / NAD27 / Local coordinates for the well centre, start of horizontal and bottom hole. Made by `ERCB` and the coordinate routines.
- **ROAD USE:** road, owner (disposition) and length in km, on the access map page.
- **ACTIVITY / CLIENT:** referral list (CLR, DTLE, FMA, TPA …) on page 2.

---

## 2. What each table tells us

| Table | Answers | Rows |
|---|---|---|
| AREA REQUIRED | How much land the new disposition needs, by component, and how long the access road / right-of-way is | Site (Pad / Well / Riser Site), each Access Road width (e.g. `10.00 Access Road`), Right-of-Way, Road Allowance (length only), **Total** |
| DISPOSITION AREAS | How much of each component is on **new** land vs inside an **existing** disposition | Site, Access Road, TWS, Campsite, Borrow Pit …, Total |
| TIMBER SALVAGE | How much of each component needs **new tree cutting** vs ground **already cut** (timber salvage for the forestry holder) | As above |
| UPLAND / WETLAND | How much of the proposed area falls in AER/ABMI wetland vs upland | Upland, Wetland, Total |
| INCIDENTAL ACTIVITIES | Each workspace outside the main disposition: an ID, what it is, its position and its area. `*` means entirely within a disposition. | IA1, IA2 … |

---

## 3. Where the values come from

All values are **calculated once from closed polylines in model space** and **typed into the table as plain text**. They are *not* fields, so they do **not** update when the shapes change. In 4 of the 5 jobs the tables had also been **exploded** into loose text and lines.

### 3.1 The formula (all routines except DAREA)

```
ground hectares = polyline area (m², grid) / 10 000 / CSF²
acres           = hectares × 2.4710538146717        (igl-convert-ha->ac)
hectares shown  = rounded to 0.001     acres shown = rounded to 0.01
length          = centreline length / CSF, rounded UP to the next metre
```
- **CSF** (combined scale factor) is taken from the `USERR1` system variable (set by CSFSHOW). The routines warn if it differs from the drawing property **CSF**. Example CSFs: 23022 0.999502 · 26345 0.999436 · 26133 0.999606 · template 1.0.
- **DAREA** (2025, fills `<Pad Area>` placeholders) does **not** divide by CSF², so it gives **grid** area. On 23022 that's 3.804 ha instead of 3.808 ha, which is enough to change the 3rd decimal.

### 3.2 Which layers feed which table

| Layer (model space, closed polylines) | AREA REQ. | DISPOSITION | TIMBER | UPLAND/WETLAND | INCIDENTAL |
|---|---|---|---|---|---|
| `Prop-WS` | Site row ("Pad / Well / Riser Site", asked) | ✓ | ✓ | ✓ (Prop-*) | |
| `Prop-AR` | Access Road row(s). **Width prefix** from text inside the polyline (e.g. `20.00`); **length** from the centreline inside it | ✓ | ✓ | ✓ | |
| `Prop-RW`, `Prop-Riser` | Right-of-Way / Riser Site | ✓ | ✓ | ✓ | |
| `Workspace` (TWS), `Workspace Log Deck`, `… Borrow Pit`, `… Bank Stabilization`, `… Temp Industrial Access` (TIA) | — | ✓ | ✓ | | ✓ (via the `Incidental Activities Label` block) |
| `Areas Linework-Existing Disposition` | | **Within Existing** = area of these polylines lying inside each Prop/Workspace polyline | | | `*` on the label |
| `Areas Linework-Existing Cut` | | | **Existing Cut** = area of these inside each Prop/Workspace polyline | | |
| `Areas Linework-Road Allowance` | Road Allowance row (length only, no area) | | | | |
| `Areas Linework-Text and Centreline` | Width text and centreline polylines (length) | | | | |
| `Areas Linework-Wetland` | | | | **Wetland** = these polylines (drawn from the Postgres wetland layer); **Upland** = Prop total − Wetland | |
| `Areas Linework-Freehold` + text | Freehold "Area Required for …" text by quarter (`FAT`) | | | | |

Rules worth knowing:
- **Outside Existing** = component area − Existing Disposition inside it. **New Cut** = component area − Existing Cut inside it.
- "Inside" means the cut polyline lies **wholly within** the component (offset 0.5 m). A cut shape that crosses the component edge is **ignored** silently.
- Width breakdown: the manual says to break `Prop-AR` into separate polylines per width **off to the side**, run ARTS, then delete them. So the per-width rows usually **can't be recalculated later**; only their total (= the `Prop-AR` area) can be.
- Rows are often **edited by hand** afterwards, e.g. Campsite split from TWS (26133), or Pad Site (Existing) / (Extension) (23022).

### 3.3 What feeds what (cross-table relationships)

```
AREA REQUIRED total (Prop-*)  ─┬─ = UPLAND + WETLAND total
                               ├─ = DISPOSITION (Outside + Within), Prop rows only
                               └─ = TIMBER (New + Existing), Prop rows only
Workspace areas ── DISPOSITION / TIMBER extra rows (TWS, Campsite…) ── = INCIDENTAL ACTIVITIES hectares
Access Road length (AREA REQUIRED) ≈ ROAD USE "proposed" length (km)
```

---

## 4. How we can validate them

### 4.1 Checks that need no geometry (the table alone)

| # | Check | Rule |
|---|---|---|
| V1 | Row sums | Each table's **Total** = sum of its rows (ha) |
| V2 | Acres | Each acres cell = its hectares × 2.4710538, rounded to 0.01 (±0.01) |
| V3 | Total acres convention | Total acres = converted total ha (what ARTS/AWUW do). See question Q2: jobs use both conventions. |
| V4 | Split rows | Per row: Disposition Outside + Within = Timber New + Existing = that row's area |
| V5 | Across tables | AREA REQUIRED total = UPLAND + WETLAND total = Disposition (Prop rows) = Timber (Prop rows) |
| V6 | Incidental | Each INCIDENTAL ACTIVITIES hectares value matches its row in Disposition / Timber (summed per activity) |
| V7 | Length | Sum of per-width lengths = Total length; Access Road length ≈ ROAD USE proposed length |

### 4.2 Checks against the drawing (recompute from the polylines)

| # | Check | Rule |
|---|---|---|
| G1 | Site area | `Prop-WS` area / CSF² = Site row |
| G2 | Access road | `Prop-AR` total / CSF² = sum of Access Road rows |
| G3 | Workspaces | Each workspace polyline = its IA label hectares and its Disposition / Timber row |
| G4 | Existing | Existing Disposition / Existing Cut inside each component = Within Existing / Existing Cut |
| G5 | Wetland | `Areas Linework-Wetland` total = Wetland row |
| G6 | CSF | `USERR1` = drawing property CSF (and ≠ 1.0 on a real job) |
| G7 | Shapes | All area polylines closed; no cut polyline crossing a component edge (it would be ignored) |

### 4.3 What the checks found on real jobs

| Job | Finding | Check |
|---|---|---|
| **26345** | All tables agree with each other (3.451 + 0.064 = 3.515 in every table) ✅ | V1, V4, V5 |
| 26345 | Timber "New Cut" total acres **8.57**, but 3.466 ha converts to **8.56** (8.57 is the sum of rounded rows) | V3 |
| 26345 | The current linework doesn't reproduce Timber: an `Existing Cut` polyline sits exactly on the pad (3.451 ha) but the table shows 0 existing cut for the pad, and 0.049 existing cut for the road with no matching shape. The table is from an earlier state of the linework. | G4 |
| **26133** | AREA REQUIRED ties out: width rows 0.212 + 0.286 + 0.124 + 0.062 = 0.684 = `Prop-AR` (0.6842) ✅; total 4.158 ✅; lengths 209 + 180 + 61 + 34 = 484 ✅ | V1, G2 |
| 26133 | **TWS 0.360** in Disposition/Timber, but the two TWS shapes now measure 0.1800 + 0.1808 = **0.361**. **IA3 0.180** vs shape **0.181**. The shapes were changed after the tables were made. | G3, V6 |
| 26133 | Disposition total acres **12.56** (sum of rows) vs 5.086 ha → **12.57** (converted) | V3 |
| 26133 | Upland 4.135 + Wetland 0.023 = 4.158 = AREA REQUIRED total ✅ | V5 |
| **23022** | AREA REQUIRED hand-split into Existing 3.200 + Extension 0.609, but Disposition and Timber put **all 3.809** within existing / existing cut. Should the extension be Outside Existing / New Cut? | V4 (meaning) |
| 23022 | `Prop-WS` measures **3.808** ha; the tables say **3.809** | G1 |
| **23033** | Borrow Pit 0.493 = shape 0.4932 ✅; IA `TWS*` (within disposition) agrees with Disposition "Within Existing" ✅ | G3, V6 |
| All | Tables usually **exploded** into loose text (26133, 23022, 23033) or hand-edited; only 26345 still had live table objects | — |

So on 4 real jobs, the checks found **stale values on 2**, **rounding-convention differences on 2**, and **one result worth questioning**.

---

## 5. Problems with the current process (from the code and the jobs)

1. **Values are static.** Edit a shape after ARTS and every table is silently out of date (26133, 26345).
2. **Tables get exploded or hand-edited**, so nothing can re-read them as tables; a checker has to read loose text by position under each title.
3. **Two rounding conventions** for total acres (converted total vs sum of rows) appear on real plans.
4. **Cut polylines must sit wholly inside** a component; crossing shapes are ignored without warning.
5. **Per-width access road rows** come from temporary polylines that get deleted, so they can't be re-checked later.
6. **DAREA ignores the scale factor** (grid area), unlike every other routine.
7. **ARTS asks the site type** (Pad / Well / Riser) every run, and the header via a one-item list. Small, but slows people down.
8. The ARTS dialog has a typo: "Area Required **Timer** Salvage".

---

## 6. Options for tomorrow

| Option | What it does | Effort | Risk |
|---|---|---|---|
| **A. Checker (`ATC`, read-only)** | Reads the five tables (live or exploded), recalculates from the polylines, runs V1–V7 and G1–G7, and lists every mismatch in a window like WNH's. Changes nothing. | Low–medium | Very low, since it never edits |
| B. Rebuild | Re-run the calculations and rewrite the five tables in place | Medium–high | Overwrites hand edits (Campsite, Existing / Extension rows) |
| C. Live fields | Tables whose cells are fields linked to the polylines, so they update themselves | High | Breaks when tables are exploded; CSF² can't be applied by a plain field |

**Recommendation:** start with **A (checker)**. It catches the real problems found above, can be trusted on any job without fear, and its recalculation code becomes the base for B later.

## 7. Questions to decide tomorrow

| # | Question |
|---|---|
| Q1 | Checker first (option A), or go straight to rebuilding the tables? |
| Q2 | **Total acres:** converted from total hectares (what ARTS does), or the sum of the row acres (what 26133 / 26345 show)? |
| Q3 | Tolerance: is ±0.001 ha / ±0.01 ac a mismatch, or only bigger differences? |
| Q4 | 23022: should a pad **extension** count as Outside Existing / New Cut? Who confirms (checker / manager)? |
| Q5 | Should hand-made rows (Campsite, Existing / Extension) be recognised by name, so the checker groups shapes the same way? |
| Q6 | Fix DAREA to divide by CSF², or leave it (what is `<Pad Area>` used for)? |
| Q7 | Freehold (FAT): in scope now, or Crown first? |
| Q8 | Which jobs are the test set? (Current: 26345, 26133, 23022, 23033.) |
