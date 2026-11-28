# Learning Notes

Concepts that come up while working on the wellsite plan automation, in plain words. Add new ones as they come up.

## Full guides
| Topic | One line |
|---|---|
| [Combined Scale Factor (CSF)](Combined%20Scale%20Factor.md) | Converts drawing (grid) distances and areas to real (ground) ones. Areas ÷ CSF². Stored in `USERR1`. |

## Quick glossary
| Term | Meaning |
|---|---|
| **Vertical well** | Drilled straight down; the bottom hole is under the surface. The name has no type word. Usually no drill path on the drawing. |
| **Directional (DD)** | Steered at an angle; the bottom hole is offset (usually a few hundred m) but the hole isn't horizontal. Name: `… DD …` |
| **Horizontal (HZ)** | Curves until about flat (80°+) and runs through the formation; the bottom hole is often 1–3 km away. Name: `… HZ …` |
| **Lateral** | The flat, horizontal leg of an HZ well |
| **Upland** | Dry, firm ground (forest, grassland, farmland). On the table: Upland = Area Required total − Wetland |
| **Wetland** | Ground that's wet most of the year (bog, fen, marsh, swamp, shallow open water). Covered by the Alberta Wetland Policy. On the table: area inside `Areas Linework-Wetland` |
| **ABMI** | Alberta Biodiversity Monitoring Institute. It publishes the province-wide wetland inventory our wetland linework comes from. |
| **Incidental activities** | Extra, usually temporary, land needed to build the site: TWS, log deck, borrow pit, campsite, TIA, bank stabilization. Each gets an ID (IA1, IA2 …), lat/long and hectares; `*` = entirely inside the disposition. |
| **Outside / within existing** | Disposition Areas table: how much of each piece is new land vs inside a disposition someone already holds. Outside Existing = piece − existing disposition inside it. |
| **New cut / existing cut** | Timber Salvage table: how much of each piece needs trees cut vs is already cleared. New Cut = piece − existing cut inside it. |
| **TWS** | Temporary Workspace |
| **TIA** | Temporary Industrial Access |
| **Disposition** | The land the government grants for the project (the lease, the access road). |
