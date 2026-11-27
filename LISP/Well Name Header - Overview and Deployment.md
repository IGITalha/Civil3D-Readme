# WNH: Overview and Deployment

This page explains **what WNH is for and how to roll it out**. For the detail of each step, layer and setting, see [Well Name Header.md](Well%20Name%20Header.md). For the official naming rules, see [Well-Naming-Rules.md](../Well-Naming-Rules.md). Decisions made along the way are in [DECISIONS.md](../DECISIONS.md).

---

## 1. The problem it solves

Page 1 of every wellsite plan starts with one line per well:

```
TOURMALINE HZ SMOKY 16-36-60-4
TOURMALINE 102 HZ SMOKY 5-31-60-3
```

Before WNH, a drafter typed these by hand. Each line needs:

| Part | Where the drafter had to get it |
|---|---|
| Operator | The client, and whether they abbreviate (CVE, WCP …) |
| UWI (100 / 102 / 103) | Checking whether another well, new or existing, already ends in the same LSD |
| HZ / DD | The well type |
| Strike area | The AER strike area map, per bottom hole. A pad can span two strike areas (e.g. SMOKY and RESTHA). |
| LS-SEC-TWP-RGE | Reading the bottom-hole location off the drawing for each well |

It also has to stay within 36 characters. The drawing properties (filled by UDP) only ever held one bottom hole, so multi-well pads were always typed by hand. The usual mistakes were a wrong LSD, a missing or extra 102, the wrong strike area for one leg, an existing well left off for Tourmaline, and a line over 36 characters.

**WNH does all of that from the drawing in one command** and shows you the result to check before it writes anything.

---

## 2. What it does, in plain terms

1. **Finds the wells.** New wells come from the `Drill Path` lines (pad end = well centre, far end = bottom hole). Existing wells on the same pad come from the AER survey lines.
2. **Works out each bottom hole's legal location** from the section labels on the drawing (4 × 4 LSD grid).
3. **Numbers the UWIs.** Wells ending in the same LSD get 100, 102, 103…, with existing wells first.
4. **Looks up the strike area** of each bottom-hole section from AER data.
5. **Builds each name** following the client's style (show 100 or not, short form if over 36).
6. **Shows a window** with the names, a Notes box of warnings, and Move Up / Move Down to set the order.
7. **Writes the names onto page 1.** It replaces the old lines, moves the lines below, and fixes WELL/WELLS. It also fills in the Sur/BH drawing properties so the LS line updates.

One `U` undoes the whole thing.

---

## 3. Where it looks for answers

| Question | Where WNH finds the answer | If it isn't there |
|---|---|---|
| Who's the operator? | Drawing property **Operator** | Asks once and saves it |
| HZ or DD? | Drawing property **HZ or DD** | Asks on a fresh drawing (Sur LS = `X`) |
| Where are the new wells? | `Drill Path` polylines in Model | Falls back to `Bottom Hole 100/5-18` labels, then the BH drawing properties |
| Which sections are where? | `10-Section Labels` MTEXT (section number over TWP-RGE-MER) | Twp/Rge from `ATS Labels Quarter` or the BH properties (marked `*`) |
| Existing wells on the pad? | `ERCB Wells - Directional_Lines` and `well_bore` polylines starting within 100 m of a new well centre | None listed |
| 100 or 102? | Other wells (new and existing) ending in the same LSD; a `Bottom Hole 102/…` label overrides | 100. Also warns if an AER `bottom_hole` point from another pad is in the LSD |
| Strike area? | `Well Name Header - Strike Areas.txt` (the AER's strike area for each section) | Page 1's existing names, then the **Strike Area** property |
| Client style? | `WNH_CLIENTS` table at the top of the `.lsp` | Defaults (no 100, new wells only), with a note |
| Order of the lines? | Page 1's current order; else the ELEVATIONS note; else wellhead position | You set it in the window |
| Where is page 1? | A layout with a `PLAN SHOWING…` title and name lines ending in a location | Asks you to pick if there are several; select by hand if none |

**It never uses:** UDP, the **UWI** drawing property (one value can't describe a pad), or the company Postgres `strike_region` table.

## 4. What it asks you

| When | Question |
|---|---|
| Operator property still `OPERATOR` | "Operator abbreviation (e.g. CVE, TOURMALINE):" |
| Strike Area still `STRIKE` and the lookup finds nothing | "Field / Strike Area name or abbreviation:" (lists nearby areas as a hint) |
| Fresh drawing (Sur LS = `X`) | "Well type [HZ/DD/Vertical] <HZ>:" |
| Several page 1 layouts (fresh template) | "Which one gets the well names? [1-n] <1>:" |
| Always | The window: set the order, then **Write to page 1** or **Cancel** |

## 5. What it changes

- **Page 1:** the well name lines, the position of the WELL(S) DRILLED / LS / county lines, and WELL ↔ WELLS. New wells use the template colour (blue); existing wells are ByLayer (black).
- **Drawing properties:** Sur LS/Sec/Twp/Rge, Mer, BH LS/Sec/Twp/Rge (from the first well), Strike Area (the first well's), and Operator / HZ or DD if it asked. Then `UPDATEFIELD`.
- **Nothing else.** Model space isn't touched.

---

## 6. Deploying it

### 6.1 Files

| File | What it is | Needed? |
|---|---|---|
| `LISP/Well Name Header.lsp` | The command. Also contains the AER Map-94 strike-area name list. | **Yes** |
| `LISP/Well Name Header - Strike Areas.txt` | The strike area for each section in Alberta (~200 KB, readable) | Strongly recommended. Without it, the strike area comes from the property. |
| `tools/build_strike_tracts.py` | Rebuilds the `.txt` from the AER's monthly download | For the person who maintains it |
| `LISP/Well Name Header.md`, this file, `Well-Naming-Rules.md`, `DECISIONS.md` | Documentation | For reference |

### 6.2 Option A: one person or tester (no shared changes)

1. Copy `Well Name Header.lsp` and `Well Name Header - Strike Areas.txt` into **one folder**, e.g. `C:\IGI LISP\`.
2. Add that folder to the support path: **Options → Files → Support File Search Path → Add**. Also add it to **Trusted Locations** if AutoCAD warns when loading.
3. `APPLOAD` → **Startup Suite → Contents → Add** → `Well Name Header.lsp`. It loads in every drawing from then on.
4. Open a **copy** of a job, type `WNH`, and check the Notes box says "Strike areas looked up … (date)".

### 6.3 Option B: everyone (shared drive), *not done yet; needs approval*

The office already loads shared routines from `O:\IGI\Cad Support\AutoCAD 2026\acaddoc.lsp` (ARTS, Crossing Box, DLD …).
1. Copy both files to `O:\IGI\Cad Support\Visual LISP Development\`. WNH already looks there for the `.txt`.
2. Add one line to `acaddoc.lsp` in **both** `AutoCAD 2026\` and `AutoCAD 2027\`:
   ```lisp
   (load "O:/IGI/Cad Support/Visual LISP Development/Well Name Header.lsp")
   ```
3. Open Civil 3D on one PC, check `Loaded... Well Name Header - type WNH` appears, and run the checks in 6.5.
4. Tell the team: "type `WNH` on page 1 jobs; read the Notes before clicking Write".

> Writing to `O:` affects everyone, so it's only done once the tester signs off and the manager agrees.

### 6.4 Rolling back

- **Option A:** remove it from the Startup Suite.
- **Option B:** delete or comment out the `acaddoc.lsp` line (`;` at the start) and restart Civil 3D.
- In a drawing, `U` straight after WNH undoes it.
- Every version is in git (`feature/well-name-header`), so an older `.lsp` can be restored at any time.

### 6.5 Checks before rollout

| Job | Expected |
|---|---|
| 26345 (Cenovus, 4 wells) | `CVE 100 HZ BERLRW 5-18-59-24`, `4-18`, `12-18`, `13-18`, all `-59-24` |
| 23022 (Tourmaline, 3 new + 5 existing) | Same 8 lines as the issued PDF: SMOKY/RESTHA, 102 on new 5-31 and the second 4-25, existing wells in black |
| A fresh Well Site template | Asks which page 1, fills it, removes the placeholder |
| Operator set to WHITECAP on 23022 | 3 new wells only; 5-31 still 102 |

### 6.6 Keeping it current

| What | How often | How |
|---|---|---|
| Strike area per section (`… Strike Areas.txt`) | Monthly, or when a job's strike area looks wrong | Download https://www.aer.ca/data/shapefiles/AER_Order_System_SHP.zip, unzip, run `python tools/build_strike_tracts.py <folder> "LISP/Well Name Header - Strike Areas.txt"`, then replace the `.txt` where people load it from |
| Strike area names (Map-94 list in the `.lsp`) | Yearly | AER Map-94 download; see Well-Naming-Rules.md §4 |
| Client styles (`WNH_CLIENTS`) | When a new client starts | Add one line at the top of the `.lsp` |
| Code changes | As needed | Edit on the `feature/well-name-header` branch, test on 23022 and 26345, commit, push, then redeploy the `.lsp` |

---

## 7. Known limits

- **Vertical existing wells** (no survey line) aren't listed; add them by hand.
- **Road allowance bottom holes** (S/W UWI codes) aren't detected; there's a warning within 25 m of an LSD line.
- **"Next to a field"** isn't checked. The strike area is the one the bottom-hole section is in.
- **Header size** isn't adjusted (`WNH_FIT nil`). If many wells push the header into a table, move the table.
- **Existing-well order** on a brand-new page 1 is a guess (wellhead south to north); fix it in the window.
