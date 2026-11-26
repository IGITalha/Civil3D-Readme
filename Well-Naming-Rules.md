# Alberta Well Naming Rules — Reference

These are the official rules for naming wells on wellsite plans, with the source for each, and how the `WNH` command (`LISP/Well Name Header.lsp`) applies them.

Compiled 2026-11-25 from the AER and Alberta King's Printer sources listed at the end.

---

## 1. The rule: OGCR section 13.020

The legal requirement is in the **Oil and Gas Conservation Rules** (AR 151/71), s. 13.020. Directive 056 s. 7.7.2 refers back to it. The text below is from the consolidation current as of November 4, 2026:

> **13.020(1)** The length of a well name shall not exceed 36 characters and spaces.
>
> **(2)** A well name shall be created at the time the well is licensed and shall include
> - **(a)** the licensee name by an abbreviation which is satisfactory to the Regulator,
> - **(b)** any optional particulars that the applicant proposing the well name desires and the Regulator approves, or as may be required to distinguish it from an existing well name,
> - **(c)** one of the following:
>   - (i) if a well is located in or adjacent to a field, the designated field name or the approved abbreviation;
>   - (ii) if the well is not located in or adjacent to a designated field, the name of the strike area or the approved abbreviation;
>   - (iii) if a crude bitumen well is located in a sector, the sector name or the approved abbreviation;
> - and **(d)** the legal subdivision, section, township and range in which the **bottom hole** of the well is located, in that order, indicated by numbers separated by hyphens.

OGCR s. 2.010(3) adds: *"The well name shall be in accordance with section 13.020."*

## 2. What each part means

```
 CVE   100  HZ   BERLRW   5-18-59-24
 (a)   ──(b)──    (c)       (d)
```

| Part | Rule | Example | Notes |
|---|---|---|---|
| **(a) Licensee** | Abbreviation acceptable to the AER | `CVE`, `TOURMALINE` | The AER doesn't publish a fixed list. Use what the client uses on their licences. |
| **(b) Optional particulars** | Anything the applicant wants and the AER approves, or what's needed to tell it apart from an existing well name | `100`, `102`, `HZ`, `DD` | This is where the UWI prefix and well type go. Directive 056 s. 7.7.2 says these go **between the licensee abbreviation and the field name**. |
| **(c) Field / strike area** | Designated field name if in or next to a field, otherwise the strike area name, or the approved abbreviation of either | `BERLRW` (Berland River West) | Official list: AER Map-94 (see section 4) |
| **(d) Location** | **Bottom hole** LS-SEC-TWP-RGE, in that order, separated by hyphens | `5-18-59-24` | No meridian, no leading zeros |
| **Length** | 36 **characters and spaces** at most | `CVE 100 HZ BERLRW 5-18-59-24` = 28 | Dashes count too |

### Special cases (Directive 056 s. 7.7.2)
- **Brine-hosted mineral wells (BMR):** must have `MIM` immediately after the licensee name or abbreviation.
- **Geothermal wells (GRDR):** must have `GT` in the same position.
- **Name changes:** a name can be changed when the licensee changes, the **bottom hole location is revised**, or the well type changes. That's done by amendment or information update; see Manual 012.
- The AER can change a well name itself to make it comply with 13.020 (OGCR s. 13.010(4)).

## 3. Where "100" / "102" comes from: the UWI

The number after the operator is taken from the well's **Unique Well Identifier** (AER, *Unique Well Identifiers*, March 2023):

```
1  00 / 05-18-059-24 W5 / 0
│  │    └ bottom hole location   └ event sequence
│  └ location exception code
└ survey system (1 = Dominion Land Survey)
```

- **"100" = survey system `1` + location exception `00`.** The location exception code *"is used to describe more than one licensed well in a legal subdivision"* and *"generally… the sequence in which the drill holes were licensed in the legal subdivision"*.
  - The first well licensed in the LSD is `00`, so **100**.
  - The second is `02`, so **102**, then 103, and so on. *"01 is not used."*
- **The UWI follows the bottom hole:** *"The location component describes the bottomhole location of the well, not the surface position."*
- **Horizontal wells / multiple legs:** *"The unique well identifier is assigned based on the projected bottomhole location of the longest drill leg."*
- **Road allowances:** a well that ends in a road allowance gets a location exception of `S` or `W` (south or west of the LSD), e.g. `1S0`, not `100`.

So whether a well is 100 or 102 depends on **whether another well has already been licensed with its bottom hole in the same LSD**. The drafting manual says the same: *"if not supplied by client can be determined by finding if any other wells are in the same LSD"*.

## 4. Field / strike area names: the official list

The AER publishes **Map-94: Map of Alberta Strike Areas**, an annual, free map plus a list of every field and strike area with its approved abbreviation:

- Download: https://www.aer.ca/documents/catalog/Map94_Strike_Areas.zip
- The year-end 2026 edition has 995 names. It's built into `LISP/AER Strike Areas.lsp`.
- Each entry has the field code, strike code, name, **abbreviation**, and one reference township and range.

**Which name to use** (fields take priority over strike areas):
1. Is the well in or next to a **designated field**? Use the field name or abbreviation.
2. If not, use the **strike area** it's in.
3. The boundary is on the strike area map, which is the `Job Info\Strike Area.pdf` in the job folder, or the AER map viewer.

**Quirks in the AER's own file:** 14 names have different abbreviations on different sheets of the spreadsheet. Both spellings are accepted by `WNH`; check the client's licence if one of these comes up:

| Name | Abbreviations in the AER file |
|---|---|
| Chamberlain | CHMBRLAN / CHAMBRLAN |
| Chinook | CHINOOK / CHINOOKR (CHINOOKR is also Chinook Ridge) |
| Clayhurst | CLAYHURST / CLAYHRST |
| Coaldale | COALDALE / COALDL |
| Craigend | CRAIGEND / CRAIGND |
| Hamelin Creek | HAMLIN CK / HAMLN CK |
| Helmsdale | HELMSDLE / HELSMDLE |
| Leahurst | LEAHURST / LEAHST |
| Leduc-Woodbend | LEDUC-WB / LEDUC-WD / LEDUC OR WOODBEND |
| Lunnford | LUNNFORD / LUNNFRD |
| Pembina | PEMBINA / PEM |
| Rockyford | ROCKYFRD / ROFORD |
| Widewater | WIDEWATER / WIDEWATR |
| Wildhorse Creek | WILDHCK / WILDHO |

## 5. Company / client conventions (from the IGI naming sheet)

These are the client styles we follow. They're not AER rules, but they fit within the "optional particulars" in 13.020(2)(b).

| Client | First well in LSD | 2nd / 3rd well | Example |
|---|---|---|---|
| **Cenovus (CVE)** | Always shows `100` | `102`, `103` | `CVE 100 HZ PELICAN 1-17-79-24` |
| **Tourmaline** | UWI left out | `102`, `103` | `TOURMALINE HZ LELAND 3-26-57-27` |

- `HZ` = horizontal, `DD` = directional, blank for a vertical well.
- If the name is over 36 characters, shorten the operator and/or the field/strike area using the AER abbreviations.
- New well centre names are shown in blue. Tourmaline also wants existing well names shown in black.

## 6. How `WNH` applies these rules

| Rule | What `WNH` does |
|---|---|
| 36 characters and spaces | Counts each name and flags it if over |
| (a) Licensee | Operator drawing property; asks if it's still the template placeholder |
| (b) UWI | `100` unless a `Bottom Hole 102/…` label says otherwise. Warns if an AER bottom hole is already in the same LSD, since it may need to be 102. Leaves out `100` except for operators in `WNH_ALWAYS_SHOW_UWI` (currently CVE). |
| (b) HZ / DD | `HZ or DD` drawing property; asks on a fresh drawing |
| (c) Field / strike area | Strike Area drawing property, checked against the AER Map-94 list. A full name is changed to its abbreviation, and unknown values are flagged. Lists nearby fields as a hint. |
| (d) Bottom hole LS-SEC-TWP-RGE | Worked out from the far end of each `Drill Path` and the section labels |
| Horizontal = longest leg's bottom hole | Uses the end of each drill path |
| Road allowance (`S`/`W` codes) | **Not detected.** It warns when a bottom hole is within 25 m of an LSD line, which includes road allowances. |
| MIM / GT wells | Not handled; type them in by hand |
| Field vs strike area choice | Not decided automatically; it needs the strike area map |

## Sources

- [Oil and Gas Conservation Rules, AR 151/71](https://kings-printer.alberta.ca/documents/Regs/1971_151.pdf): s. 2.010(3), 13.010, 13.020 (Alberta King's Printer, current as of November 4, 2026)
- [AER Directive 056: Energy Development Applications and Schedules](https://static.aer.ca/prd/documents/directives/directive-056.pdf): s. 7.7.2 Well Names (October 2026 edition)
- [AER Unique Well Identifiers](https://static.aer.ca/prd/documents/applications/UWI-Description.pdf) (March 2023)
- [AER Map-94: Map of Alberta Strike Areas](https://www1.aer.ca/ProductCatalogue/188.html): [zip download](https://www.aer.ca/documents/catalog/Map94_Strike_Areas.zip), Field Strike Lists YE2026
- IGI Drafting Procedure Manual (UWI / strike area notes) and the IGI well naming convention sheet
