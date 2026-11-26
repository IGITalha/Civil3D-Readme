"""Build "Well Name Header - Strike Areas.txt", the field / strike area of
every section in Alberta, which the WNH command reads.

Source: AER Order System (BOS) data, updated monthly by the AER
    https://www.aer.ca/data/shapefiles/AER_Order_System_SHP.zip
Unzip it and point this script at the folder that holds
Admin_Strike_Area.txt, Admin_Strike_Area_Tract.txt, Admin_Field.txt and
Admin_Field_Tract.txt.

    python tools/build_strike_tracts.py <unzipped folder> "LISP/Well Name Header - Strike Areas.txt"

File format - one line per township, sections grouped into runs:

    TWP-RGE-MER|SECTIONS=ABBREVIATION|SECTIONS=ABBREVIATION...
    60-3-6|1-17=RESTHA|18=SMOKY|19-29=RESTHA|30-31=SMOKY|32-36=RESTHA
    60-4-6|1-36=SMOKY

A section split between two areas lists both with "+":  21=RESTHA+SMOKY
Sections in no area are left out. Lines starting with ";" are comments.

Rules: only current tracts (no termination date). A designated field wins
over a strike area (OGCR 13.020(2)(c)), so the field's name is used wherever a
section is in a field order.
"""
import collections
import csv
import datetime
import os
import sys


def read(folder, name):
    with open(os.path.join(folder, name), encoding="latin-1", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def tracts(folder, names_file, tract_file, id_col, abbr_col):
    names = {r[id_col]: r[abbr_col].strip() for r in read(folder, names_file)}
    out = collections.defaultdict(set)
    for r in read(folder, tract_file):
        if r["TERMINATION_DATE"] == "" and r[id_col] in names:
            out[r["TRACT_ID"]].add(names[r[id_col]])
    return out


def runs(secs):
    """{sec: 'ABBR'} -> ['1-17=RESTHA', '18=SMOKY', ...]"""
    out, start, prev, val = [], None, None, None
    for s in sorted(secs) + [None]:
        v = secs.get(s) if s else None
        if s and v == val and s == prev + 1:
            prev = s
            continue
        if start is not None:
            out.append(("%d" % start if start == prev else "%d-%d" % (start, prev)) + "=" + val)
        start, prev, val = s, s, v
    return out


def main(folder, out_path):
    strike = tracts(folder, "Admin_Strike_Area.txt", "Admin_Strike_Area_Tract.txt",
                    "STRIKE_AREA_ID", "STRIKE_AREA_ABBREVIATION")
    field = tracts(folder, "Admin_Field.txt", "Admin_Field_Tract.txt",
                   "FIELD_ID", "FIELD_ABBREVIATION")
    final = dict(strike)
    final.update(field)  # field wins

    # Tract_ID: TTT M RR SS LL Q  (township, meridian, range, section, 00, quarter)
    towns = collections.defaultdict(dict)
    for tid, abbrs in final.items():
        if tid[8:10] != "00" or tid[10] != "0":
            raise SystemExit("unexpected quarter/LSD tract " + tid)
        for a in abbrs:
            if any(c in a for c in "|=+;"):
                raise SystemExit("abbreviation has a separator character: " + a)
        towns[(int(tid[0:3]), int(tid[4:6]), int(tid[3]))][int(tid[6:8])] = "+".join(sorted(abbrs))

    lines = [
        "; Field / strike area of every section in Alberta, for the WNH command.",
        "; From the AER Order System (BOS) data, built %s by tools/build_strike_tracts.py."
        % datetime.date.today().isoformat(),
        "; TWP-RGE-MER|SECTIONS=ABBREVIATION|...   A+B = section split between two areas.",
        "; Field orders win over strike areas. Rebuild monthly from",
        "; https://www.aer.ca/data/shapefiles/AER_Order_System_SHP.zip",
        "DATE|" + datetime.date.today().isoformat(),
    ]
    for (twp, rge, mer) in sorted(towns):
        lines.append("%d-%d-%d|%s" % (twp, rge, mer, "|".join(runs(towns[(twp, rge, mer)]))))
    with open(out_path, "w", encoding="ascii", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print("townships %d, file %s (%d KB)" % (len(towns), out_path, os.path.getsize(out_path) // 1024))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
