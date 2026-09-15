# Civil 3D 2026 — LISP / Add-in Load Flow (Exploration Notes)

Notes from exploring `O:\IGI\Cad Support\AutoCAD 2026\` — read-only exploration, nothing in that folder was changed. This documents what auto-loads when Civil 3D 2026 starts and where everything lives.

## Startup Chain (in order)

1. **`O:\IGI\Cad Support\AutoCAD 2026\acad.lsp`**
   Loaded once when AutoCAD/Civil 3D application starts.
   → loads `acaddoc.lsp` via hardcoded absolute path.

2. **`O:\IGI\Cad Support\AutoCAD 2026\acaddoc.lsp`**
   Loaded once per drawing/document. Runs, in order:
   1. `(load "Integrated Geomatics-2026.lsp")` — the main custom routine library (same folder). **This file itself also auto-loads two ARX modules at its very top** (see below) — easy to miss since they're `arxload`, not `load`, calls.
   2. `(command "_.NETLOAD" "C:/Integrated CAD/IntegratedGeomatics.dll")` — .NET add-in, local `C:` drive, outside this repo.
   3. `(command "_.NETLOAD" "C:/Integrated CAD/IGI.CivilTools.dll")` — second .NET add-in.
   4. `(load "acetutil")`, `acetutil2`, `acetutil3`, `acetutil4` — Autodesk **Express Tools** support files. Loaded by name only (no path), so they resolve through AutoCAD's Support File Search Path (profile-based), not from this folder. Could not locate them under `C:\Program Files\Autodesk` in this environment.
   5. `(load "O:/IGI/Cad Support/Visual LISP Development/FixGridScale.lsp")` then immediately calls `(c:FIXGRIDSCALE)`.

### ARX modules loaded from inside `Integrated Geomatics-2026.lsp` (lines 5–7)

Found on closer inspection — these run automatically every time the main lsp file loads (i.e. every document open), since they're the first 3 lines of the file, before any `defun`:

```lisp
(vl-load-com)
(arxload "ctextapp.arx")
(arxload "O:\IGI\Cad Support\Visual LISP Development\DOSLib 9.0\DOSLib26x64.arx")
```

- **`ctextapp.arx`** — loaded by name only, resolved via AutoCAD's support file search path (not present in either explored folder — likely a bundled/Express Tools ARX for curved/arc text).
- **`DOSLib26x64.arx`** — a third-party ARX (file/OS utility function library for AutoLISP, from a well-known independent add-on) loaded by full absolute path from `Visual LISP Development\DOSLib 9.0\`. That folder also contains older versions (`DOSLib17` through `DOSLib22`, both 32-bit and x64) plus a `.chm`/`.chw` help file and a `V9.0.1` subfolder — only the `26x64` build is actually wired into the load chain, consistent with a 2026 AutoCAD version bump.

## What `FIXGRIDSCALE` does

Runs automatically on every document open. Connects to the running Civil 3D `AeccApplication` COM object (tries several ProgID version strings, `13.8` noted in comments as "likely for C3D 2026"), then:
- Pulls `ActiveDocument.Settings.DrawingSettings.TransformationSettings`
- Forces `ApplyTransformSettings = True`
- Runs `REGENALL`

Net effect: every drawing silently gets its coordinate-transformation/grid-scale settings reapplied at load time.

## The Two LISP Libraries

| Library | Location | Role |
|---|---|---|
| `Integrated Geomatics-2026.lsp` | `O:\IGI\Cad Support\AutoCAD 2026\` | **Active/production** library, auto-loaded by `acaddoc.lsp`. 11,462 lines, 546 `defun`s. Defines dozens of short `c:` command aliases (`c:an`, `c:cpe`, `c:cbr`, `c:hwc`, `c:fts`, etc.) plus a large `igl-*` helper function set (geometry / ActiveX COM utility wrappers). |
| `Visual LISP Development\` folder | `O:\IGI\Cad Support\Visual LISP Development\` | Older, much larger sprawl of **individual standalone tool** `.lsp` files (Well Coordinates Table, Pipeline Right-of-Way, Crossing Box, Section Selection, etc.), plus an older non-"2026" `Integrated Geomatics.lsp` and `Integrated Geomatics Library.lsp`. **Only `FixGridScale.lsp` from this entire folder is actually wired into the auto-load chain** — everything else here appears to be loaded manually/on demand (e.g. via `APPLOAD`), not at startup. |

## Other Supporting Resources (in `AutoCAD 2026` folder)

- **`Required Postgres DLLs\`** — `libpq.dll` + OpenSSL deps (`libeay32.dll`, `ssleay32.dll`, `libintl.dll`) for a Postgres-backed data connection. Includes a `Postgres DLL Pathing.png` screenshot documenting required path placement.
- **`pedata\`** — geodetic support data (`gdaldata`, `geographic`, `geoid`, `vertical`) — standard folder pattern for Civil 3D's GDAL-based geolocation/coordinate transformation engine.
- **`VB.NET\`** — separate VB.NET command source projects (Global_coordinates_system, Roper2014, Tiger2014, cleanPCS2014, CopyDLL) — likely source for one/both of the NETLOAD'd DLLs, or older/alternate builds.
- **`mvsetup.dfs`** — Map/mvsetup defaults file.
- **`AutoCAD 2026 Pathing.pdf`** — could not render (no PDF tooling available in this session), but the filename strongly suggests it documents the required Support File Search Path entries needed for the `acetutil*` loads and the two external DLL paths (`C:\Integrated CAD\...`) to resolve correctly.

## `C:\Integrated CAD\` — the NETLOAD'd DLL folder (contents confirmed)

This is where the two `NETLOAD`ed DLLs actually live, along with their config and supporting data:

| File | Purpose |
|---|---|
| `IntegratedGeomatics.dll` (+ a `- Copy.dll` backup, identical size) | Main custom .NET add-in, loaded via `NETLOAD` in `acaddoc.lsp`. |
| `IGI.CivilTools.dll` | Second custom .NET add-in, loaded via `NETLOAD`. Notably the newest file in the whole tree (Feb 27 2026), so it's under active development. |
| `IntegratedGeomatics.ini` | **Config file read by the DLL at runtime** — see contents below. |
| `Client Name.ini` | Maps ~20 full client/operator legal names (e.g. "Cenovus Energy Inc") to short codes (e.g. "CVE") — used by the add-in for project/title-block setup per client. |
| `BitMiracle.LibTiff.NET.dll` (+ `.xml`) | Third-party TIFF image library dependency, used by the add-in for raster/GeoTIFF handling. |
| `INIFileParser.dll` | Third-party library the add-in uses to read the `.ini` files above. |
| `FINAL_CLEANUP.csv`, `LTO_CLEANUP.csv`, `PARCEL_CLEANUP.csv`, `PCS_CLEANUP.csv`, `find_replace.csv`, `rounding_widths.csv`, `nr_gcs.txt` | Data/lookup tables the add-in reads for its cleanup and rounding routines. |

### `IntegratedGeomatics.ini` contents (confirms cross-links back to `O:\IGI\Cad Support\`)

```ini
[ATS Coordinates]
ATSCoordPath=O:\IGI\Cad Support\Visual LISP Development\ATS COORDINATES
UTM8311Csv=O:\IGI\Cad Support\Visual LISP Development\ATS COORDINATES\ASCM\UTM83-11.csv
UTM8312Csv=O:\IGI\Cad Support\Visual LISP Development\ATS COORDINATES\ASCM\UTM83-12.csv
NEof36CompiledListCsv=O:\IGI\Cad Support\Visual LISP Development\ATS COORDINATES\NE of 36\Compiled_List.csv

[AutoCAD]
AcadLin=O:\IGI\Cad Support\Linetypes\acad.lin

[Tiger]
PathToBlocksFolder=O:\IGI\Cad Support\Blocks
```

So the .NET add-in itself depends on three more shared folders back on the `O:` drive: `Visual LISP Development\ATS COORDINATES\` (Alberta Township System coordinate CSVs, e.g. `TWP 1 - RGE 1 - W4M.csv`), `O:\IGI\Cad Support\Linetypes\` (custom `.lin`/`.shx` files), and `O:\IGI\Cad Support\Blocks\` (shared block library, e.g. titleblocks, well/AER license blocks).

## `Integrated Geomatics-2026.lsp` — full command inventory

546 `defun`s total. Beyond the first batch of `c:` commands already noted, the file also defines (non-exhaustive, second half of file):
- **XML/report parsing helpers**: `plsActivityLand_Load`, `plsCriteria_Load`, `plsGeoAdminArea_Load`, `plsPlan_Load`, `plsRegRemark_Load`, `plsRequestedLand_Load`, `plsReservationException_Load`, `XmlEx-Get*` — parse PLSR (Public Lands Standing Report) XML exports and freehold title XML data.
- **`c:rut`** — Road Use Table generator.
- **`ig_select_section` / `igss_*` / `igss2_*`** — a large section-selection subsystem that interactively finds township/section/quarter boundaries, unsurveyed boundary lines, section labels, and wellhead blocks from screen picks.
- **`c:slt`** — Slope Line Ticks.
- **`c:sdb`** — Surface Development Blocks.
- **`c:ta`** / `ta_*` — Target Areas (drilling target boundary generation, incl. Schedule 13A logic).
- **`c:tlc`** — TWP Layer Cleanup.
- **`c:udf`** / **`c:udp`** / `udf_*` / `udp_*` — Update Date Field / Update Drawing Properties (pulls county from PLSR or freehold XML).
- **`update_local_files`** / `ulf_*` — syncs local support files from a source path (file copy + timestamp compare).
- **`c:wct`** / `wct_*` — **Well Coordinates Table** (the largest subsystem here): builds NAD27/NAD83 coordinate tables, handles block attribute population, and can export to CSV and SP1 (seismic permit) file formats.
- **`c:wns`** — Wellsite Notes.
- **`c:wro`** / `wro_*` — Well Radius Outline (draws 100m/200m regulatory setback circles with tangent-line construction geometry — this is the single biggest function cluster in the file).
- **`c:wsn`** / `wsn-*` — Wildlife/setback notes.
- **`c:wod`** — Workspace Object Data.
- **`c:didslayers`** — bulk-reassigns dozens of legacy layer names into three consolidated "Dids-Activities-*" layers (Leases, RW, Other) — a layer-standardization cleanup command.

## The `Visual LISP Development` Folder — Full Picture

This folder is far bigger than just individual tool files; it's effectively a full **development archive**, not just a tool library:

| Subfolder | Contents |
|---|---|
| **`Don Dev\`** | Dated development snapshots (e.g. `2017-01-06 Well Coordinates`, `2017-01-20 Target Areas`, `2017-01-24 Section Selection`, `2017-01-27 Powerline Crossing`, `2017-02-16 Public Land Standing Report`, etc.) — each a folder of daily-dated `.lsp` revisions, essentially manual version control predating any use of git. Also contains `Don Dev\Utils\acaddoc.lsp` and `Function Hunt.lsp` (a dev utility, presumably for locating function definitions across files). |
| **`Archive\`** | Pre-update backups of production files (`*_Beforeupdate.lsp`, `Integrated Geomatics(beforeARTSupdate).lsp`, `Integrated Geomatics(CopyBeforeDIDSLAYERS).lsp`, old versions of tables/docs). |
| **`Angel\`** | Unrelated/legacy generic AutoLISP utility scripts (`algvec.LSP`, `change.LSP`, `search.LSP`, etc.) with a manual doc — looks like a separate contributor's toolkit, not part of the load chain. |
| **`ATS COORDINATES\`** | Alberta Township System coordinate reference CSVs (per township/range/meridian, e.g. `TWP 1 - RGE 1 - W4M.csv`), plus `10TM`, `3TM`, `ASCM`, `NE of 36` subfolders — this is the data referenced by `IntegratedGeomatics.ini` above. |
| **`DOSLib 9.0\`** | Third-party DOSLib ARX add-on, multiple version builds (17–22, 32/64-bit) plus the actively-loaded `DOSLib26x64.arx` and a `V9.0.1` subfolder and `.chm` help file. |
| **`acmaplisp\`** | Just AutoCAD Map 3D LISP reference help files (`.chm`/`.chw`) — documentation only, not loaded. |
| **`EnviroInventoryData\`**, **`InventoryData\`** | Esri file geodatabases (`.gdb`) and related inventory data (`IGI_Enviro_Inventory*.gdb`, `IGI_Inventory.gdb`, logs, `pylog` backups) — GIS data stores, unrelated to the LISP load chain but used by the broader workflow. |
| **`WildlifeQuarterSections\`** | Just a `readme.txt` stating files were moved to `O:\IGI\Cad Support\HRV` (folder now effectively empty/deprecated). |
| **`LAT CSV Archives\`** | Old dated backups of `LAT.csv` (`LAT.csv.old1`, `.old2`). |
| **`analyze_lisp.py`** | A Python script sitting in this folder (May 2026) — likely a personal/ad hoc tool for analyzing the LISP codebase (e.g. extracting function lists), separate from the AutoCAD load chain itself. |
| Two old **`acaddoc - Copy*.lsp`** files and one **`acaddoc._ls`** | Backup/renamed copies of an older acaddoc — not active, but confirm this folder used to have its own acaddoc at some point before the current `AutoCAD 2026\acaddoc.lsp` became the authoritative one. |

None of the above subfolders are referenced by the current `acad.lsp` → `acaddoc.lsp` → `Integrated Geomatics-2026.lsp` chain except **`FixGridScale.lsp`**, **`DOSLib 9.0\DOSLib26x64.arx`**, and (indirectly, via the .NET add-in's ini file) **`ATS COORDINATES\`**.

## Summary — Every Time a Drawing Opens

1. `acad.lsp` → `acaddoc.lsp` chain fires.
2. `Integrated Geomatics-2026.lsp` loads, which itself immediately `arxload`s `ctextapp.arx` and `DOSLib26x64.arx` (546 `defun`s become available, including ~35+ `c:` commands).
3. Two .NET DLLs load via `NETLOAD` (`IntegratedGeomatics.dll`, `IGI.CivilTools.dll`) — these read `IntegratedGeomatics.ini` and `Client Name.ini` from `C:\Integrated CAD\`, which in turn point back to three more shared folders on `O:\IGI\Cad Support\` (ATS Coordinates, Linetypes, Blocks).
4. Four Express Tools `acetutil` files load from the AutoCAD support path.
5. `FixGridScale.lsp` loads and `FIXGRIDSCALE` runs immediately, silently reapplying coordinate transformation settings and regenerating the drawing.

The bulk of actual production tooling lives in `Integrated Geomatics-2026.lsp`. The `Visual LISP Development` folder is really a **development archive** (dated daily snapshots under `Don Dev\`, pre-update backups under `Archive\`, GIS geodatabases, coordinate reference data, and a third-party DOSLib ARX toolkit) — of all of it, only `FixGridScale.lsp` and `DOSLib26x64.arx` are actually wired into the live auto-load chain; the rest is either reference data (consumed by the .NET add-in via its ini file) or tools loaded manually/on demand.

---
*Generated from a read-only exploration on 2026-09-15 (updated same day with deeper pass). No files in `O:\IGI\Cad Support\` or `C:\Integrated CAD\` were modified.*
