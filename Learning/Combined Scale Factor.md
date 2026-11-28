# Combined Scale Factor (CSF)

*A practical guide for survey drafting and Civil 3D, and how it shows up in IGI drawings.*

> **In one line:** the drawing measures distances on a flat map grid, but the plan has to report what you'd measure on the actual ground. CSF is the number that converts between the two.

---

## 1. Why we need it

The Earth is curved, but our coordinate grids are flat. A distance measured with a tape on site (**ground**) is a little different from the same distance measured between coordinates in the drawing (**grid**).

The difference is tiny, but the plans report areas to **0.001 ha**, so it's big enough to change the numbers we print.

---

## 2. Three surfaces, two corrections

```
            A ●~~~~~~~~/\~~~~/\~~~~~~~~~~~● B        Physical ground    (where the crew measures)
                 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
                         ⌒‾‾‾‾‾‾‾‾‾‾‾⌒                Reference ellipsoid (smooth math model of the Earth)

            ●─────────────────────────────●          Flat projected grid (UTM / 3TM: what the drawing uses)
                                                     conceptual, not to scale
```

| Surface | What it is |
|---|---|
| **Ground** | The physical Earth, where the survey crew measures horizontal distance |
| **Ellipsoid** | A smooth mathematical model of the Earth's shape |
| **Grid** | A flat coordinate system such as UTM or Alberta 3TM. **Our drawings are in grid coordinates.** |

Getting from ground to grid takes two steps:

```
Ground ──(× Elevation Factor)──► Ellipsoid ──(× Grid Scale Factor)──► Grid
```

**Key idea:** CSF rolls both corrections into **one multiplier**, which is why it's called *combined*.

---

## 3. The two pieces

### A. Elevation Factor (EF): height above the Earth model

Higher ground sits farther from the Earth's centre. Picture two circles, one inside the other: the outer one is bigger, so the same angle covers a longer distance up there.

```
        Ground   ⌒‾‾‾‾‾‾‾‾⌒      ← longer
                  ¦  h   ¦
      Ellipsoid   ⌒‾‾‾‾‾‾⌒       ← shorter
```

**EF = R / (R + h)**
- R = the Earth's radius, about 6,371,000 m
- h = **ellipsoidal height** (height above the ellipsoid, *not* simply elevation above sea level)

Example: a lease near 800 m → EF ≈ 6,371,000 / 6,371,800 = **0.999874**

EF is always **a bit less than 1** for ground above the ellipsoid, which is all of Alberta.

### B. Grid Scale Factor (GSF): flattening the map

Flattening a curved surface onto paper always stretches or squashes it, like trying to flatten an orange peel. How much depends on **how far you are from the projection's central meridian** (its centre line).

```
  1.0000 - - - - -\- - - - - - - - - - - -/- - - -
                   \                     /
                    \_________●_________/
                          central meridian
                   UTM: 0.9996 here   ·   Alberta 3TM: 0.9999 here
```

- At the central meridian it's lowest: **0.9996 in UTM**, **0.9999 in 3TM**.
- It grows as you move east or west, and can go **above 1** near the zone edges.

### Combine them

**CSF = EF × GSF**

Example: EF 0.999874 × GSF 0.99962 = **CSF 0.999494**

Typical values are around **0.9995 to 1.0001**.

---

## 4. Converting: which way?

| Direction | Formula | When |
|---|---|---|
| **Ground → grid** | Grid = Ground × CSF | Putting a crew's measured distance into the drawing |
| **Grid → ground** | **Ground = Grid ÷ CSF** | **Reporting from the drawing: what our area tables do** |

**Distance example:** the crew measures 1,000 m on the ground, and CSF = 0.999500.
- Ground → grid: 1,000 × 0.999500 = **999.500 m**
- Grid → ground: 999.500 ÷ 0.999500 = **1,000 m**
- The difference is **0.5 m (50 cm) in only one kilometre.**

### Areas use CSF squared

An area is length × width, so **both** directions get corrected:

**Ground area = Grid area ÷ CSF²**

**Lease example:** a lease measures **4.1580 ha** in the drawing, and CSF = 0.99960.
- CSF² = 0.99920
- 4.1580 ÷ 0.99920 = **4.1613 ha** on the ground
- That's **+0.0033 ha (33 m²)**, enough to change the third decimal the table prints

---

## 5. How it shows up in IGI drawings

| What | Where |
|---|---|
| **The CSF value** | The `USERR1` system variable. Type `USERR1` on the command line to see it. |
| **Who reads it** | `igl-get-combined-scale-factor` in `Integrated Geomatics Library.lsp`. It deliberately uses `USERR1`, **not** the CSF drawing property, and warns against relying on the property. |
| **Area formula in our routines** | ground ha = grid area (m²) ÷ 10,000 ÷ CSF², then acres = ha × 2.4710538 |
| **Routines that apply it** | ARTS (Area Required / Timber Salvage), AWUW (Upland / Wetland), IAT (Incidental Activities) |
| **⚠️ The exception** | **DAREA.lsp doesn't apply CSF**, so its areas are **grid**, not ground. This is open question Q6 in [Area Tables - Discovery.md](../LISP/Area%20Tables%20-%20Discovery.md). |

### Checklist
- ✅ Check whether the drawing or routine **already** applies CSF, so it isn't applied twice or missed.
- ✅ Check the **direction**: ÷ for grid → ground. Some workflows store the reciprocal (1/CSF) instead.
- ✅ For areas, use **CSF²**, not CSF.
- ❌ Don't confuse CSF with the **plot or viewport scale** (1:500, 1:1000). They're unrelated.

---

## 6. Learning path

Ground vs grid distance → ellipsoid vs geoid vs the physical Earth → coordinate systems → UTM zones and central meridians (and Alberta 3TM) → elevation factor → grid scale factor → **combined scale factor** → applying it in Civil 3D

---

## 7. Practice

**Q1.** The crew measures 2,000 m on the ground. CSF = 0.999800. Is the grid distance larger or smaller, and by how much?
> **Smaller.** 2,000 × 0.999800 = **1,999.600 m**, 0.400 m less.

**Q2.** A lease measures **2.500 ha** in the drawing. `USERR1` = 0.99950. What goes in the table?
> CSF² = 0.99900. 2.500 ÷ 0.99900 = 2.5025 → **2.503 ha** (× 2.4710538 = **6.18 ac**)

**Q3.** DAREA reports 2.500 ha for that same lease. Why does it differ from ARTS?
> DAREA doesn't divide by CSF², so it reports the **grid** area. ARTS reports the **ground** area (2.503).
