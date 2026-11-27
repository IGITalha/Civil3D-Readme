# Decisions Log

Every decision made on the page 1 automation work: what was decided, why, and who decided. Newest at the bottom of each section. **Open questions** are at the end of each section.

Who: **User** = drafter (project owner) · **Manager** = confirmed with the user's manager · **Claude** = proposed by Claude and accepted.

---

## A. Well Name Header (WNH)

| # | Date | Decision | Why | Who |
|---|---|---|---|---|
| A1 | 2026-11-25 | One command, `WNH`, fills the page 1 well name lines | The user wants "run a command and it does the thing" | User |
| A2 | 2026-11-25 | Read everything from the drawing, **not UDP** | "Nobody uses UDP right now"; UDP only ever held one bottom hole | User |
| A3 | 2026-11-25 | New wells come from `Drill Path` polylines (pad end = well centre, far end = bottom hole); locations come from `10-Section Labels` with a 4 × 4 LSD split | It's what every job already has; verified on 26345 even with labels deleted and properties wrong | Claude |
| A4 | 2026-11-25 | Find page 1 automatically (`PLAN SHOWING…` title on the sheet + name lines under it) and **replace** the lines in place; move the lines below; fix WELL/WELLS | The template has one placeholder line; jobs have several; nobody should have to select them | User / Claude |
| A5 | 2026-11-25 | Follow OGCR 13.020 (36 characters; licensee; optional particulars; field or strike area; bottom hole LS-SEC-TWP-RGE). Use the AER Map-94 list for abbreviations. | Official rule. Reference in `Well-Naming-Rules.md` | User (asked for the rules) |
| A6 | 2026-11-26 | **One `.lsp` file** for the tester (Map-94 list built in) | The tester should load one file and nothing else | User |
| A7 | 2026-11-26 | Existing wells on the pad come from AER survey lines (`ERCB Wells - Directional_Lines`, `well_bore`) starting within 100 m of a new well centre. Copies are skipped; a drawn path + survey of the same well count once. | 23022 shows them; they weren't being picked up | Claude |
| A8 | 2026-11-26 | Existing wells are **listed only for Tourmaline** (black, ByLayer); new wells keep the template colour (blue) | IGI naming sheet; **confirmed with the manager** | User / Manager |
| A9 | 2026-11-26 | Existing wells **always count** for 100/102 numbering, even when not listed | Otherwise a Whitecap well in the same LSD as an existing one lost its 102 (bug found in testing) | Claude |
| A10 | 2026-11-26 | UWI: wells ending in the same LSD get 100, 102, 103…, existing first; a `Bottom Hole 102/…` label overrides | AER UWI rules (location exception = licence order in the LSD) | Claude |
| A11 | 2026-11-26 | **Ignore the UWI drawing property** for drill-path wells | One value for the whole drawing put 102 on every well in the live test on 23022 | User approved the fix |
| A12 | 2026-11-26 | Strike area is **looked up per bottom-hole section** from the AER Order System (BOS) tract tables (field orders win over strike areas) | The user asked "is there not a way to look it up"; the drawing has no strike boundaries | User |
| A13 | 2026-11-26 | The strike lookup lives in a **separate, readable** `Well Name Header - Strike Areas.txt`, not inside the `.lsp` | The user didn't want a big encoded table in the routine | User |
| A14 | 2026-11-26 | Don't use the company Postgres `strike_region` table | No routine uses it; it would need DB credentials in LISP; the AER data gives the same answers | Claude, user agreed |
| A15 | 2026-11-26 | Client styles in one table, `WNH_CLIENTS`: CVE shows 100; Tourmaline lists existing wells; Whitecap short form WCP; Acerta short form AOC. Unknown clients get defaults plus a note. | Checked against the AER ST37 well list; **CVE always 100 confirmed with the manager** | User / Manager |
| A16 | 2026-11-26 | The short form is used **only when a name would be over 36**, per line, and flagged in the window | User decision. ST37 shows companies don't switch forms just for length, but the 36-character rule applies. | User |
| A17 | 2026-11-26 | Header fitting (shrink text to fit the space) is built but **switched off** (`WNH_FIT nil`); names keep page 1's size | "Let's not decide the height and width for now" | User |
| A18 | 2026-11-26 | Only lines ending in a location (or `X-XX-XX-XX`) count as name lines; when there are several page 1 layouts, ask which | The template's Participant Involvement Map also says "PLAN SHOWING"; the template has 6 page 1 layouts | Claude |
| A19 | 2026-11-26 | The order is chosen in a **window** (Move Up / Move Down, Notes, Write / Cancel); the Yes/No/**Strike areas** prompt is removed | The user wants to set the order in the pop-up and trusts the strike lookup | User |
| A20 | 2026-11-26 | Work on branch `feature/well-name-header`; don't write to `O:` without asking | `O:` is shared by everyone | User / Claude |

### Open questions (WNH)
1. **Order of existing wells on a new page 1.** It's currently wellhead south to north, which matches 23022. Is there a rule, such as licence date?
2. **Deployment to `O:`** and the `acaddoc.lsp` load line. When, and who approves? (See the Overview and Deployment doc §6.3.)
3. **Merge to `main`**, or open a pull request?
4. Should header fitting (`WNH_FIT`) be turned on later, and at what minimum size?

---

## B. Area Tables (discovery, 2026-11-26)

| # | Date | Decision | Why | Who |
|---|---|---|---|---|
| B1 | 2026-11-26 | Today is **discovery only**. No code changes to the area table routines. Findings are in `LISP/Area Tables - Discovery.md`. | The user: "today is the discovery phase"; build tomorrow | User |
| B2 | 2026-11-26 | Study the existing routines (ARTS, AWUW, IAT/IAL, FAT, DAREA, ERCB) and real jobs (26345, 23022, 26133, 23033, template) before designing anything | The tables already have working generators; we need to know what they do and where they go wrong | Claude |
| B3 | 2026-11-26 | Scope is the **five page 1 area tables**: Area Required, Disposition Areas, Timber Salvage, Upland/Wetland, Incidental Activities. Well coordinates, Road Use and Activity/Client tables are out of scope. | They're the ones calculated from area polylines | Claude |
| B4 | 2026-11-26 | Treat the routines' rules as the **spec**: ground ha = area / 10 000 / CSF² (CSF from `USERR1`); acres = ha × 2.4710538; ha to 0.001, ac to 0.01; length rounded up | It's what produced every table on the plans | Claude |
| B5 | 2026-11-26 | **Recommended** (not yet decided): build a read-only checker (`ATC`) first, rebuild later | Real jobs had stale and inconsistent values; a checker can't damage hand edits | Claude, pending the user |

### Open questions (Area Tables)
See `LISP/Area Tables - Discovery.md` §7 (Q1–Q8): checker vs rebuild, total-acres convention, tolerance, the 23022 extension, hand-made rows, DAREA and CSF, Freehold scope, test jobs.
