# Civil 3D 2026 → 2027 — Upgrade & DOSLib Rebuild Runbook

Documents the `O:\IGI\Cad Support\AutoCAD 2027\` folder that was just stood up, and the process used to get a working DOSLib build for AutoCAD/Civil 3D 2027. Read-only exploration of `O:` and `C:\Integrated CAD\` — nothing there was changed by writing this doc.

## 1. New Support Folder — `O:\IGI\Cad Support\AutoCAD 2027\`

Mirrors the 2026 folder structure:

| Item | Notes |
|---|---|
| `acad.lsp` | **Points back at the 2026 folder**: `(load "O:/IGI/Cad Support/AutoCAD 2026/acaddoc.lsp")`. Comment header still says "AutoCAD 2026" too. ⚠️ Confirm whether this is intentional (2026 chain is the single shared entry point for both versions right now) or should be repointed at a 2027-native `acaddoc.lsp`. |
| `acaddoc.lsp` | Present in this folder, and loads `Integrated Geomatics-2027.lsp` **from the 2026 folder path** (`O:/IGI/Cad Support/AutoCAD 2026/Integrated Geomatics-2027.lsp`), not from `AutoCAD 2027\`. Same ⚠️ as above — the 2027 folder currently isn't the one actually driving the load chain; the 2026 folder is, via a new `-2027`-suffixed lsp file. |
| `Integrated Geomatics-2027.lsp` | Exists in **both** `AutoCAD 2026\` and `AutoCAD 2027\` — confirmed byte-identical (diff clean). Line 7: `(arxload "O:\IGI\Cad Support\Visual LISP Development\DOSLib 9.0\DOSLib27x64.arx")` — this is the line that was changed from `DOSLib26x64.arx` → `DOSLib27x64.arx` to pick up the new build. |
| `Required Postgres DLLs\` | Same contents as the 2026 folder (`libpq.dll` + OpenSSL deps + pathing screenshot) — copied over, not modified. |
| `VB.NET\` | Same project set as 2026 (`Global_coordinates_system`, `Roper2014`, `Tiger2014`, `cleanPCS2014`, `CopyDLL`, plus `- Converted` variants) — copied over. |
| `mvsetup.dfs` | Present, dated Jan 2026 — carried over from 2026 folder. |

**Not yet confirmed present in the 2027 folder** (existed in 2026's): `pedata\` (GDAL geodetic data), `AutoCAD 2027 Pathing.pdf`. Worth checking these got copied too, since `pedata\` is what Civil 3D's coordinate-transformation engine reads.

## 2. Updated Startup Chain (as currently wired)

Both 2026 and 2027 profiles currently route through `Integrated Geomatics-2027.lsp`, and only the DOSLib arxload line differs from the old 2026 lsp:

```
acad.lsp  →  acaddoc.lsp  →  Integrated Geomatics-2027.lsp
                                 (vl-load-com)
                                 (arxload "ctextapp.arx")
                                 (arxload ".../DOSLib 9.0/DOSLib27x64.arx")   ← new
                              → NETLOAD IntegratedGeomatics.dll
                              → NETLOAD IGI.CivilTools.dll
                              → acetutil / acetutil2 / acetutil3 / acetutil4
                              → FixGridScale.lsp → (c:FIXGRIDSCALE)
                              → Area Required Timber Salvage.lsp   ← new since the 2026 README was written
```

`Area Required Timber Salvage.lsp` is a new load added to `acaddoc.lsp` that wasn't present when the [Civil3D-2026-LISP-Config-README.md](Civil3D-2026-LISP-Config-README.md) doc was originally written — it's now loaded (but not auto-run — no `c:` call after it, unlike `FIXGRIDSCALE`) right before `FIXGRIDSCALE` fires.

## 3. DOSLib 2027 Rebuild — What Was Actually Done

`DOSLib26x64.arx` (the file wired into the 2026 chain) is a compiled ObjectARX plug-in, not LISP — it has to be rebuilt from C++ source against the AutoCAD 2027 SDK to get an ARX that loads in 2027. Steps taken:

1. **Toolchain**: Visual Studio Community **2026** (not VS Code — DOSLib's `.sln`/`.vcxproj` build needs full Visual Studio). Via Visual Studio Installer → *Modify*:
   - Workload: **Desktop development with C++**
   - Individual components: **MSVC v143 - VS 2022 C++ x64/x86 build tools (v14.44/17.14)**, matching ATL v143 and MFC v143 x86/x64 components. (x86-only ARM/ARM64/C++-CLI/Spectre variants were skipped as unneeded.) A leftover v141-toolset warning appeared but didn't block the build.

2. **AutoCAD 2027 ObjectARX SDK** (`objectarx-for-autocad-2027-win-64bit`) — provides the AutoCAD-side headers/libs the DOSLib source compiles against. Extracted to `C:\acad\arx\26` (ARX version **26** = the ObjectARX generation for AutoCAD 2027 — note the off-by-one from the product year). Had to move the SDK contents **up one level**, since the download extracted into a nested `CDROM1\` subfolder first:
   ```
   C:\acad\arx\26\CDROM1\inc, inc-x64, lib-x64, ...   → moved up to →   C:\acad\arx\26\inc, inc-x64, lib-x64, ...
   ```
   DOSLib's project files expect the SDK directly under `C:\acad\arx\<ver>\`, not nested one level deeper — this is the part most likely to bite again next year if the SDK zip structure doesn't change.

3. **DOSLib source** — rather than reuse an old, provenance-unknown local copy, cloned fresh from the official DOSLib GitHub repo into this repo at [DOSLib/](DOSLib/) (now present as an untracked folder here — see note in §5 below).

4. **Build**: Opened `DOSLib/source/DOSLib.sln` in Visual Studio, selected configuration **`Release_ARX26`**, platform **x64**, then `Build → Build Solution` (F7 — not the debugger/run button). Succeeded with `1 succeeded, 0 failed`; one harmless `LNK4099` warning (`rxapi.pdb` not found — debug symbols only, doesn't affect the ARX itself).

5. **Output** — confirmed on disk at:
   ```
   DOSLib/bin/Release/arx/DOSLib27x64.arx
   ```
   (The project's default output name convention would produce `DOSLib26x64.arx` for the `ARX26` config — it was renamed to `DOSLib27x64.arx` on output to match this shop's existing naming convention of `DOSLib<AutoCAD-year-2-digit>x64.arx`, consistent with the existing `DOSLib26x64.arx` for 2026.)

6. **Deployed** — copied into the shared library location, confirmed present at:
   ```
   O:\IGI\Cad Support\Visual LISP Development\DOSLib 9.0\DOSLib27x64.arx
   ```
   alongside the untouched `DOSLib26x64.arx` and the older 17–22 32/64-bit builds already documented in the [2026 README](Civil3D-2026-LISP-Config-README.md).

7. **Wired in** — `Integrated Geomatics-2027.lsp` line 7 updated to `arxload` the new `DOSLib27x64.arx` path (see §2). Confirmed working in Civil 3D 2027.

### Reusable pattern for the next AutoCAD upgrade

```
New AutoCAD version
   → get matching ObjectARX SDK (note the ARX-version-vs-product-year offset)
   → install matching VS C++ toolset (MSVC vNNN + matching ATL/MFC)
   → clone fresh DOSLib source (don't reuse an unknown old copy)
   → extract SDK to C:\acad\arx\<ver>\ — flatten any nested CDROM1\-style subfolder
   → open DOSLib.sln → select Release_ARX<ver> / x64 → Build Solution
   → rename output to DOSLib<year>x64.arx per shop convention
   → copy into O:\IGI\Cad Support\Visual LISP Development\DOSLib 9.0\
   → update the arxload path in Integrated Geomatics-<year>.lsp
   → test LISP routines that depend on DOSLib functions
```

## 4. Open Items — Still To Be Documented

These were mentioned as "additional configuration" done after the DOSLib build but not yet captured here — filling these in is the next step for this doc:

- [ ] Manual `APPLOAD` steps, if any were needed beyond the `arxload` in the lsp chain
- [ ] **Trusted Locations** — was `Visual LISP Development\DOSLib 9.0\` (or the whole `O:\IGI\Cad Support\` tree) added to AutoCAD's Trusted Locations for 2027? Required if `SECURELOAD` blocks unsigned ARX/LSP from untrusted paths.
- [ ] `SECURELOAD` system variable setting used for the 2027 profile
- [ ] `ACADLSPASDOC` setting (affects whether `acaddoc.lsp` reloads per-document vs. once)
- [ ] Support File Search Path additions in the 2027 profile (this is what resolves `acetutil*` and `ctextapp.arx` by name only)
- [ ] Any Startup Suite entries configured
- [ ] Whether a separate 2027 AutoCAD **profile** was created, or the 2026 profile was reused/renamed
- [ ] Whether `acad.lsp`/`acaddoc.lsp` pointing back at the `AutoCAD 2026\` folder (§1) is the intended long-term setup or a placeholder to be un-forked later

## 5. Repo Note

This repo (`Civil3D-Readme`) now has an **untracked `DOSLib/`** folder at its root — the fresh GitHub clone used to build the 2027 ARX (per `git status`: `?? DOSLib/`). Since it's third-party source (not this shop's own code) and includes build output binaries, consider whether it belongs:
- committed here (if you want the exact source/version pinned for reproducibility), with build output (`DOSLib/bin/`) excluded via `.gitignore`, or
- left untracked / removed from this repo folder now that the `.arx` is deployed to `O:`, since the source itself doesn't need to live in this readme-focused repo.

---
*Compiled 2026-09-22 from a read-only pass over `O:\IGI\Cad Support\AutoCAD 2027\`, `O:\IGI\Cad Support\Visual LISP Development\DOSLib 9.0\`, and the local `DOSLib\` clone, plus the DOSLib rebuild walkthrough provided by the user. Section 4 is intentionally left as open questions pending more detail from the user.*
