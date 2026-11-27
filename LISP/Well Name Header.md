# WNH: Well Name Header

`Well Name Header.lsp` adds one command, **`WNH`**, that writes the well name lines at the top of wellsite **page 1**:

```
PLAN SHOWING SURVEY OF PAD SITE (MSL 231046)
TOURMALINE HZ SMOKY 16-36-60-4            <- new wells (blue)
TOURMALINE HZ RESTHA 4-21-60-3
TOURMALINE 102 HZ SMOKY 5-31-60-3
TOURMALINE HZ RESTHA 2-21-60-3            <- existing wells on the pad (black)
...
WELLS HORIZONTALLY DRILLED FROM A SURFACE LOCATION WITHIN THEORETIC
LS 5 Sec 29 Twp 60 Rge 3 W6M
```

It works out the wells from what's drawn in model space. You don't need to run UDP or pick the bottom holes.

The naming rules it follows (36 characters, UWI 100/102, strike area abbreviations) are explained in [Well-Naming-Rules.md](../Well-Naming-Rules.md).

---

## 1. Loading and running

**Load it once:**
1. Type `APPLOAD`.
2. Under **Startup Suite**, click **Contents…**, then **Add…**, and pick `Well Name Header.lsp`.

It then loads automatically in every drawing.

Also copy **`Well Name Header - Strike Areas.txt`** into a folder on the AutoCAD support path (Options → Files → Support File Search Path). Without it, WNH still works, but the strike area comes from the drawing property (see section 7).

**Run it:**
1. Open the job drawing. You can be on any tab, including Model.
2. Type `WNH`.
3. Answer any questions about properties that are still on their template values (see section 2).
4. A **Well Name Header** window opens with:
   - the names, top to bottom, with their character counts. Existing wells are marked `existing`.
   - a **Notes** box with any **!** warnings, the date of the strike data, and the surface LS.
5. To change the order, click a name and use **Move Up** / **Move Down**.
6. Click **Write to page 1**, or **Cancel** (or Esc) to stop without changing anything.
7. Check page 1. One `U` (undo) reverses everything WNH did.

If the window can't open for some reason, WNH falls back to an alert and asks for the order on the command line instead: type the numbers, e.g. `3 1 2`, or press Enter.

Next time you run WNH, the list starts in page 1's current order, so your order is kept.

---

## 2. What it does, step by step

| Step | What happens |
|---|---|
| 1. Check properties | If **Operator** is still the template placeholder (`OPERATOR`), it asks for it. A placeholder **Strike Area** (`STRIKE`) is looked up from the first bottom hole; it only asks if the lookup finds nothing. A full strike name such as "Berland River West" is changed to its AER abbreviation (`BERLRW`). On a fresh drawing (Sur LS = `X`) it also asks HZ / DD / Vertical. |
| 2. Find the new wells | Reads every **Drill Path** polyline. The end at the pad is the well centre, and the other end is the bottom hole. |
| 3. Work out legal locations | Uses the **section labels** to turn each well centre and bottom hole into LS-SEC-TWP-RGE-MER (see section 4). |
| 4. Find existing wells | Reads the AER survey lines that start on the pad (see section 3). They always count for 100/102 numbering, but they're only listed on page 1 for clients set to list them (Tourmaline). |
| 5. Assign UWIs | Wells that end in the same LSD get 100, 102, 103, with existing wells first. |
| 6. Build names | Looks up the strike area of each bottom-hole section (see section 7), then joins Operator + UWI + HZ/DD + strike area + LS-SEC-TWP-RGE. It counts the characters and flags anything over 36. |
| 7. Suggest an order | If page 1 already lists every well, it uses that order. Otherwise new wells come first, in ELEVATIONS note order, then existing wells. |
| 8. Show the window | Names with character counts, plus a Notes box (warnings, strike data date, surface LS). You set the order with Move Up / Move Down, then Write to page 1 or Cancel. |
| 9. Find page 1 | Uses the current tab if it's a page 1, else the only page 1. If the drawing has several (a fresh template has Crown/Freehold, Single/Multi …), it lists them and asks you to pick a number, once per run. |
| 10. Write | Replaces the name lines in page 1's current height and spacing, moves the lines below to suit, and fixes WELL/WELLS. Fitting to the space can be turned on (see "Fitting the header" below). |
| 11. Update properties | Fills in the Sur and BH drawing properties and runs `UPDATEFIELD`, so the LS line and other fields match. |

---

## 3. Layers it reads

All of these are in **model space** unless noted.

| Layer | Objects | What WNH uses it for |
|---|---|---|
| **Drill Path** | LWPOLYLINE, LINE | **New wells.** One polyline per well, from the well centre (through the start of horizontal) to the bottom hole. The end that is close to the other paths' ends is taken as the pad (surface) end. With only one path, the first vertex is the surface. |
| **10-Section Labels** | MTEXT | **Legal location.** Each label sits at a section centre and reads the section number over `TWP-RGE-MER` (e.g. `18` / `59-24-5`). |
| **ERCB Wells - Directional_Lines** | LWPOLYLINE | **Existing wells** on the pad (AER directional surveys). A line counts if one end is within 100 m of a new well centre. |
| **well_bore** | LWPOLYLINE | Also read for existing wells, the same way (AER well bore data imported from SDF). |
| **bottom_hole** | POINT | AER bottom holes. If one falls in the same LSD as a new well that would be 100, WNH warns that it may need to be 102. |
| **Drill Path Text** | MTEXT / TEXT | `Bottom Hole 102/5-18` labels. If one is near a bottom hole, its UWI is used. If the label's LS-SEC differs from the calculated one, WNH warns you. These labels are also a fallback source of wells when there are no Drill Paths. |
| **ATS Labels Quarter** | MTEXT | Fallback only: Twp/Rge for label-only wells (`SE 1/4 Sec 36 60-2-6`). |
| *(any)* paper space MTEXT containing `ELEVATIONS` | MTEXT | **Order of the new wells.** The "Ground at Well Centres" list on page 1 (`16-36 = 1294.5`, `102/5-31 = …`). |

### Page 1 (paper space)

WNH does **not** rely on layer names on page 1. It finds the header like this:

1. It looks for a TEXT starting with **`PLAN SHOWING`** that sits inside a layout's paper area. Template examples parked off the sheet are ignored. The current tab is searched first.
2. The **name lines** are the TEXT objects centred under the title, in the same text style as the first one (`IGI Ex Bold`), each within about one line gap of the one above. The list stops at the first line in a different style, which is the `WELL(S) … DRILLED` line.
3. The **lines below** are any TEXT/MTEXT centred on the same x, within 3.5 line gaps under the last name: the WELL(S) DRILLED line, the LS line and the county. They are moved to suit the new number of names.

The new lines copy the old top line's layer, style, height and justification. On the Well Site template that's layer `Titleblock`, style `IGI Ex Bold`, height 5, middle-centred.
- **New wells** keep the template's colour (160, blue).
- **Existing wells** are set to **ByLayer** (black).

The template's placeholder field is removed, so the names are plain text.

A line only counts as a name line if it ends in a location (`5-18-59-24`) or the template placeholder (`X-XX-XX-XX`). That keeps WNH off other `PLAN SHOWING` pages, such as the Participant Involvement Map.

### Fitting the header into the space (switched off for now)

**Fitting is off by default (`WNH_FIT nil`).** The new name lines keep page 1's current text height and line spacing, and the lines below move down to make room. If the header runs into the legend or a table, move them by hand.

To turn fitting on, set `WNH_FIT` to `T` at the top of the `.lsp`. WNH will then size the names to fit:

1. It starts at the **standard size**: 5.0 high, 7.919 apart (`WNH_NAME_HEIGHT`, `WNH_DEFAULT_SPACING`). The top of the first name stays where it was.
2. It finds the **floor**: the highest thing printed on the sheet below the header, such as the legend box, a table, the ELEVATIONS note or a viewport. Notes parked off the sheet and anything on a No Plot / off / frozen layer are ignored.
3. If the names plus the WELL(S) DRILLED / LS / county lines would come closer than 2 mm to the floor (`WNH_FIT_MARGIN`), it **shrinks the text height and spacing together** until everything fits.
4. It also shrinks if the widest name wouldn't fit across the sheet with 12 mm either side (`WNH_SIDE_MARGIN`).
5. It never goes below **60%** (3.0 high, `WNH_MIN_SCALE`). If it still doesn't fit at that size, a pop-up tells you to move the table or legend down, or to use the Multi Well page 1, and run WNH again.

Running WNH again always starts from the standard size, so if you make more room, or there are fewer wells, the names grow back.

Tested on 23022:
- 8 names fit at full size (5.0).
- 11 names were set to 3.98.
- 14 names were set to 3.10, with the county line 2 mm above the legend box.
- Going back from 14 names to 8 restored 5.0.

---

## 4. How the legal location is worked out

For any point (a well centre or bottom hole):

1. It finds the **nearest section label**, which gives Sec, Twp, Rge and Mer, and the section centre.
2. It looks at the **neighbouring section labels** (1.2–2.1 km away) to find which way is east and north for this section. That handles grid rotation and sections that aren't square.
3. It measures where the point sits inside the section and splits the section **4 × 4** into LSDs, numbered:

   ```
   13 14 15 16     north
   12 11 10  9
    5  6  7  8
    4  3  2  1     south
   ```
4. It records how far the point is from the nearest LSD line. If that's **under 25 m**, it warns you to check the LS or road allowance.

The location in the name is the **bottom hole** LS-SEC-TWP-RGE. The **surface** location (the well centre) goes into the Sur drawing properties, which feed the `LS … Sec … Twp … Rge … W?M` line.

---

## 5. Existing wells: how they're picked out

The AER layer usually holds several lines per well, so WNH cleans them up before naming:

| Situation | What WNH does |
|---|---|
| Exact copies of the same line (same start and end within 1 m) | Keeps one |
| An AER line that is really one of the new wells (start within 10 m and end within 100 m of a Drill Path) | Skips it |
| Twin wells, e.g. 4-25 and 102/4-25, starting about 5 m apart | Keeps both, as two wells |
| A hand-drawn path (2–3 vertices) and an AER survey leaving the same spot in the same direction (within 15°) | Treats them as one well. Uses the **drawn path's end**, which is the licensed bottom hole, and warns if the survey ends in a different LSD. |
| Vertical existing wells (no directional line) | **Not picked up.** Add them by hand. |

Existing wells are always used for 100/102 numbering. They are only **listed** on page 1 for clients with *Existing* = `T` in the client table (section 10; currently `TOURMALINE`), because the naming sheet only calls for it there.

---

## 6. UWI (100 / 102 / 103)

1. Wells are grouped by the LSD their bottom hole is in.
2. **Existing** wells are numbered first (they were licensed first), from the south wellhead to the north: 100, then 102, 103…
3. **New** wells then take the next free number in their LSD, so a new well ending in an LSD that already has an existing well gets **102**. The list says why.
4. A `Bottom Hole 102/…` label overrides this. The **UWI drawing property is not used** for drill-path wells: it's one value for the whole drawing, so on a pad it would put 102 on every well.
5. In the name, `100` is left out, e.g. `TOURMALINE HZ …`, except for clients with *Show 100* = `T` in the client table (CVE shows `100`).

---

## 7. Strike area: looked up automatically

The AER's **field and strike area for every section in Alberta** is kept in a separate, readable file next to the routine: **`Well Name Header - Strike Areas.txt`** (about 200 KB). Each line is one township:

```
60-3-6|1-17=RESTHA|18=SMOKY|19-29=RESTHA|30-31=SMOKY|32-36=RESTHA
60-4-6|1-31=SMOKY|32-33=KAKWA|34-36=SMOKY
59-24-5|...|13=BERLR+PLACID|...        <- "+" = section split between two areas
```

For each well, WNH looks up the **bottom hole's section** and uses that area's abbreviation, so a pad with bottom holes in SMOKY and RESTHA gets both, with nothing to type.

**Where WNH looks for the file**, in this order:
1. `WNH_STRIKE_FILE` at the top of the `.lsp`, if you set a full path there.
2. Any folder on the AutoCAD support path, or the drawing's folder.
3. The folder that `Well Name Header.lsp` is in, if that folder is on the support path.
4. `O:\IGI\Cad Support\Visual LISP Development\`.

If WNH can't find the file, it says so in the alert and uses the Strike Area property as before.

For each well, the strike area is taken from the first of these that applies:
1. The **AER lookup** for the bottom-hole section. A designated **field** wins over a strike area, as OGCR 13.020 requires.
2. Page 1, if it already shows more than one strike area.
3. The **Strike Area** drawing property.

Notes:
- If the Strike Area property is still `STRIKE` on a fresh drawing, it's filled in from the lookup instead of being asked. After writing, the property is set to the first well's strike area.
- About 1,900 sections in Alberta are **split between two areas**. For a bottom hole in one of those, WNH uses page 1's choice if it's one of the two, otherwise the first one, and shows a warning. Check the strike area map. If it's the other area, fix that name on page 1 by hand; WNH keeps your choice the next time it runs.

**Where the data comes from:** the AER Order System (BOS) data, which the AER updates monthly. The alert shows the date the table was built. To refresh it:
1. Download https://www.aer.ca/data/shapefiles/AER_Order_System_SHP.zip and unzip it.
2. Run `python tools/build_strike_tracts.py <unzipped folder> "LISP/Well Name Header - Strike Areas.txt"`.
3. Replace the `.txt` wherever people's WNH reads it from. The `.lsp` doesn't change.

---

## 8. Drawing properties (DWGPROPS → Custom)

| Property | Read / Written | Use |
|---|---|---|
| Operator | Read (asked if placeholder) | First part of the name |
| HZ or DD | Read (asked on a fresh drawing) | `HZ`, `DD` or blank |
| Strike Area | Read (asked if placeholder; full name changed to its abbreviation) | Strike area in the name |
| UWI | Read only when there are no drill paths (one well from the BH properties) | Ignored for drill-path wells; see section 6 |
| Sur LS / Sur Sec / Sur Twp / Sur Rge / Mer | **Written** | Surface location of the first well, for the LS line fields |
| BH LS / BH Sec / BH Twp / BH Rge | **Written** (read as a fallback) | Bottom hole of the first well on page 1 |

After writing, WNH runs `UPDATEFIELD` so all fields in the drawing pick up the new values.

---

## 9. Warnings in the list

| Warning | Meaning / what to do |
|---|---|
| `<-- OVER 36!` | The name is too long. Use the AER abbreviation for the operator or strike area. |
| `bottom hole is only N m from an LSD line` | The LS could be either side, or it could be a road allowance (S/W UWI codes). Check it. |
| `label on the drawing says …` | A Bottom Hole label disagrees with the calculated LS-SEC. One of them is wrong. |
| `an AER bottom hole is already in this LSD - UWI may need to be 102` | Another pad's well ends in the same LSD. Check the licence. |
| `UWI 102 - an existing well on this pad also ends in …` | Information only: why it isn't 100. |
| `AER survey line ends in X, the drawn path in Y` | The licensed BH and the survey disagree. Check which one the licence uses. |
| `Strike Area "…" is not in the AER list` | A typo, or a name the AER doesn't use. |
| `Well centres are in more than one LS` | The surface line may need fixing by hand. |
| `*` after a name | Twp/Rge came from the BH properties, not the drawing. |

---

## 10. Settings (top of the .lsp file)

| Setting | Default | Meaning |
|---|---|---|
| `WNH_MAX_LENGTH` | 36 | AER limit, characters and spaces |
| `WNH_FIT` | nil | `T` = shrink the names to fit the space on page 1. `nil` = keep page 1's current height and spacing. |
| `WNH_NAME_HEIGHT` | 5.0 | Standard name text height (used when fitting) |
| `WNH_DEFAULT_SPACING` | 7.919 | Standard gap between name lines |
| `WNH_MIN_SCALE` | 0.6 | Smallest size the names are shrunk to when fitting (60%, 3.0 high) |
| `WNH_FIT_MARGIN` | 2.0 | Space kept between the header and whatever is below it |
| `WNH_SIDE_MARGIN` | 12.0 | Space kept between the names and the sheet edges |
| `WNH_PATH_LAYER` | `Drill Path` | New well paths |
| `WNH_SECTION_LAYER` | `10-Section Labels` | Section labels |
| `WNH_BH_LAYER` | `Drill Path Text` | Bottom Hole labels |
| `WNH_ATS_LAYER` | `ATS Labels Quarter` | Fallback Twp/Rge |
| `WNH_EDGE_WARN` | 25.0 | Metres from an LSD line before warning |
| `WNH_CLIENTS` | see below | Per-client naming style |
| `WNH_EXISTING_LAYERS` | `("ERCB Wells - Directional_Lines" "well_bore")` | Where existing wells come from |
| `WNH_PAD_RADIUS` | 100.0 | How close (m) an existing line must start to a new well centre |
| `WNH_STRIKE_FILE` | nil | Full path to `Well Name Header - Strike Areas.txt`, if it isn't on the support path |
| `WNH_STRIKE_ABBR` | empty | Extra strike-area shortenings, used only when a name is over 36 |

### Client table (`WNH_CLIENTS`)

One line per client. The **Operator** drawing property is matched against the client's name or its short form, ignoring case, and names are always written in capitals.

```lisp
;;  Operator       Show 100  Existing  Short
(("CVE"            T         nil       nil)
 ("TOURMALINE"     nil       T         nil)
 ("WHITECAP"       nil       nil       "WCP")
 ("ACERTA"         nil       nil       "AOC"))
```

| Column | Meaning |
|---|---|
| Show 100 | `T` = the first well in an LSD shows `100` (`CVE 100 HZ …`); `nil` = `100` left out, `102`/`103` still shown |
| Existing | `T` = existing wells on the pad are listed under the new ones, in black |
| Short | The AER-accepted short form, used only if a name would be over 36 characters. It's applied per well, and the alert marks any line that was shortened. |

**A client that isn't in the table still works.** It gets the defaults: no `100`, new wells only, no short form, and the alert says so. To add a client, add one line.

Checked against the AER **ST37 well list** (wells spudded 2022 onward, data as of November 2026):

| Client | AER licensee | What their licensed names show |
|---|---|---|
| CVE | Cenovus Energy Inc. | `CVE`. Only about half of 345 HZ wells with UWI 00 show `100` (e.g. `CVE 100 HZ PEMBINA …` vs `CVE HZ WAPITI …`). The IGI sheet says always show it, so the table follows the sheet. |
| TOURMALINE | Tourmaline Oil Corp. | `TOURMALINE`. Never shows `100` (0 of 609). `102`/`103` usually shown. |
| WHITECAP | Whitecap Resources Inc. | `WHITECAP`. Never shows `100` (0 of 471). Mostly `WHITECAP 102 HZ …`. The AER has also accepted `WCP`. Some wells keep acquired companies' names (`CPEC`, `HHR`, `VRN`). |
| ACERTA | Acerta Operating Corporation | `AOC` on 2020–2024 licences and `ACERTA` on 2026 licences. Never shows `100`. |

**Confirmed with the manager (November 2026):** Cenovus is always `CVE` and always shows `100`. **Only Tourmaline** lists existing wells on page 1. Every other client lists new wells only, but existing wells still count for 102/103 numbering.

---

## 11. Troubleshooting

| Problem | Fix |
|---|---|
| Header runs into the legend or a table | Fitting is off, so move them down by hand. Or set `WNH_FIT` to `T` to have WNH shrink the names. |
| "Couldn't find the page 1 header" | The `PLAN SHOWING…` title isn't plain TEXT on the sheet. Go to page 1 and run WNH; it will ask you to select the name lines. |
| A new well is missing | Its Drill Path isn't on the `Drill Path` layer, or isn't a polyline or line. |
| Wrong LS / Sec | Check that the `10-Section Labels` are present and placed at the section centres. |
| An existing well is missing | Check that its AER line starts within 100 m of the new well centres, or whether it's a vertical well. |
| An extra existing well appears | Another well's AER line starts on the pad. Delete that name line afterwards, or lower `WNH_PAD_RADIUS`. |
| Wrong strike area for some wells | Check whether the section is split (there will be a warning), or whether the table is out of date (refresh it, see section 7). For a one-off fix, edit the name on page 1 by hand. |
| Lines in the wrong order | Run WNH again and use Move Up / Move Down in the window. |
