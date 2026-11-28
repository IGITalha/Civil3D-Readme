# ARTS review (2026-11-27)

Working copy of `O:\IGI\Cad Support\Visual LISP Development\Area Required Timber Salvage.lsp` (last changed 2026-09-17), plus `Integrated Geomatics Library.lsp` (2019), which it needs. The files in this folder start as exact copies, so `git diff` shows every change we make. **Nothing on O: has been changed.**

## What ARTS does

1. Turns off every layer except the area layers, then you select the area polylines.
2. For each polyline: ha = area ÷ 10,000 ÷ CSF². Then it groups the polylines by layer (Site, Access Road by width, RW, TWS …).
3. For each one, it finds `Existing Cut` and `Existing Disposition` shapes **wholly inside** it (inside the polyline offset 0.5 m) and subtracts them.
4. It rounds each row (ha 0.001, ac 0.01) and sums the rows. Total acres come from converting the total ha.
5. It draws 3 tables (Area Required, Disposition Areas, Timber Salvage) and you drag them into place.

## Rounding vs the manager's rule

Chase (the manager) says values are **3 decimals**:
- Hectares are already 3 decimals in all 3 tables ✅
- Acres stay at **2** decimals (confirmed 2026-11-27) ✅
- Lengths are whole metres, rounded up.

## Problems found

| # | Severity | Problem | Where |
|---|---|---|---|
| R1 | **High** | **If ARTS stops part-way, your layers stay off.** All layers are turned off at the start, but there's no error handler. The layer state is only restored at the end. Esc, "No area polylines were found", or any error leaves the drawing with almost every layer off. | `c:arts` lines 24–39, 69 |
| R2 | **High** | **Overlap shapes that cross the component edge are ignored, with no warning.** Within Existing / Existing Cut come out too small. | `arts-get-area-cuts` (WP selection) |
| R3 | Medium | **The CSF mismatch alert can fire dozens of times.** `igl-get-combined-scale-factor` alerts every time it's called if the CSF property ≠ `USERR1`, and ARTS calls it 2+ times per polyline in each of 3 passes. | Library line 495 |
| R4 | Medium | **Arc polylines.** Shapes with arcs are traced as points about 1 m apart, which "cuts off the corners" (the code's own comment). A cut shape near a corner can be missed. | `arts-get-Polyline-Coordinates` |
| R5 | Medium | **Access road width label.** The first text found inside the road is used as its width prefix. With two texts inside, the road can land in the wrong row. | `arts-get-area-prefix` |
| R6 | Low | Riser-only selections (`Prop-Riser`, no `Prop-WS`) are treated as **pipeline** and ask for the pipeline standard | `arts-selection-has-site-p` |
| R7 | Low | Tourmaline Pipeline timber table: the total row has no "Total" label and only totals the last column | lines 622–627 |
| R8 | Low | No check that the tables agree (Area Required total = Disposition total = Timber total). The converted-vs-summed acres alerts are commented out. | lines 229, 452 |
| R9 | Low | Asks the site type every run. The "Select header" list has only one choice. Typo: "Area Required **Timer** Salvage". | lines 258–262, 287 |
| R10 | Low | Values are fixed once drawn. Editing a polyline later leaves the tables out of date (see the discovery doc). | design |
| R11 | Info | `CMDECHO` and `TILEMODE` are changed and never put back. The cut search runs twice per polyline (Disposition pass and Timber pass). | lines 15–16, 398, 555 |

## How "Existing" differs between the tables (from the sample PDF, 2026-11-27)

Three different questions, so three different numbers are normal:

| Table | "Existing" means | Sample pad |
|---|---|---|
| Area Required: Pad Site (Existing) | The client's **old lease being reused/amended** | 1.436 |
| Disposition: Within Existing | Inside **any** existing disposition (old lease + a pipeline ROW, road, someone else's lease …) | 1.617 |
| Timber: Existing Cut | Ground **physically already cleared**, whatever the paperwork | 1.672 |

Checks that follow:
- Within Existing ≥ Pad (Existing). The old lease is always an existing disposition.
- The difference (1.617 − 1.436 = 0.181) sits in the new part: Pad (New) − 0.181 = Outside Existing (2.717 − 0.181 = 2.536 ✅).
- So 23022 (Q4) may be legitimate if its extension lies on another disposition. Check the drawing before calling it wrong.

## Suggested order of work

1. **R1**: add an error handler that always restores the layers. A small fix that matters every time.
2. **R3**: read the CSF once per run and warn once.
3. **R2 + R8**: warn when an overlap shape crosses an edge, and check that the 3 totals agree. This is the start of the `ATC` checker idea.
4. R5, R6, R7, R9 tidy-ups.
5. Decide the acre decimals (open question above), then change the rounding in one place.
