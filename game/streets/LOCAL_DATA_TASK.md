# Task for a session on the user's own computer: the data the cloud cannot reach

**Done, 21 Nov 2026** (see DEV.md, "Data fetched on the user's computer"): job 1 from
Givatayim's map (a) and Ramat Gan's own layer (b), GovMap and the Survey of Israel not
needed; job 2 from Givatayim's map (no playgrounds layer there); job 3 both parts; job 4
for Givatayim and Ashdod. Left: Ashdod's building heights. Its map was looked at in the
second round: it has only its public buildings (316 heights), no layer of all of them.

You are a Claude Code session running on the user's own computer in Israel. The cloud
sessions that build this game cannot reach GovMap, givatayim.muni.il, data.gov.il's files
or gtfs.mot.gov.il: their network policy blocks them, and some Israeli government sites
refuse foreign or cloud servers anyway. Your job is to fetch what they cannot, and to
commit it in a form they can build from without ever reaching those sites. You need git and
Python 3. Godot is not needed for this task.

## Read first

- `CLAUDE.md`: the rules. Several sessions work at once. Fetch and merge `origin/main`
  before you test and again before you push. Check for conflict markers. Never force-push.
- `game/streets/DEV.md`, section "Tel Aviv's own survey: building heights". That was the
  first town done this way, and it is the model for this task.
- `.claude/skills/real-places/SKILL.md`, the bullet "A town's own survey of its buildings
  beats OSM's guesses -- mostly". It covers what went wrong with a survey's heights: trees
  over a roof, towers caught half-built, complexes.
- `IDEAS.md`, the bullet "Official data for what OSM leaves out", for the full list and
  what is already known.
- `tools/osm_city.py`: its docstring, then `SURVEYS`, `survey_fetch`, `survey_apply` and
  `add_surveys`.

## The towns

Each level is one JSON file in `game/streets/cities/`, baked from OSM. Its `origin` and
`bounds` give its box. Approximate lat/lon boxes:

| Level | File | Box (S, W, N, E) | Buildings | Heights guessed |
|---|---|---|---|---|
| 1, the main one | `givatayim.json` | 32.0561, 34.7952, 32.0842, 34.8234 (2.7 x 3.1 km: Givatayim, and the edges of Ramat Gan and Tel Aviv) | 6,243 | 4,726 |
| 3 | `ashdod.json` | 31.7507, 34.6061, 31.8752, 34.7130 | 10,148 | 9,499 |
| 7 | `tel_aviv.json` | 32.0576, 34.7579, 32.0872, 34.8037 | 9,597 | 534 (done) |

Tel Aviv's parts are done: Tel Aviv's own GIS answers the cloud and GitHub, and the baker
already reads it (`SURVEYS`). Do not fetch Tel Aviv's layers. That server also has
kindergartens, shelters, trees and more (layer ids in `IDEAS.md`), and cloud sessions
can fetch those themselves.

## Rules for every source

- **Read the site's terms of use before downloading anything.**
  - Prefer an official download or open-data API over a map site's internal one.
  - Do not get around a login, a captcha or a rate limit, or anything that asks not to be
    automated.
  - Pause about a second between requests. Fetch only the boxes above.
  - If the terms forbid it, stop and tell the user.
- **Write down each source's licence and its on-screen credit line.** The game shows
  credits beside OSM's, from the city file's `"credits"`.
- **No personal data in the repo.** Real-estate deals and vehicle records are about
  people. Keep only what the game needs: a floor count per address, shares of car makes
  and colours. Never names, prices, plate numbers or ID numbers.
- **Keep committed extracts small (a few MB each).** Raw downloads stay out of git;
  `tools/.cache/` is ignored. Keep the script that fetched each extract in the repo so it
  can be done again. A script that does not name the game can go in `tools/`; otherwise
  put it beside the data.

## The jobs, most important first

### 1. Givatayim's building heights or storeys

Level 1 is the level people play most, and three in four of its heights are guesses.
Try these in order:

a. **The Givatayim municipality's own map.** Look on givatayim.muni.il for GIS, maps
   (מפות) or engineering information (מידע הנדסי). Many Israeli towns run an ArcGIS
   server or a hosted viewer.
   - If you find a buildings layer with a height or a floor count, read its fields
     (`<layer url>?f=pjson`).
   - If it is ArcGIS REST, add an entry to `SURVEYS` like `tel_aviv_yafo`. `h` may be
     missing: with floors alone, `survey_apply` uses `(floors + 1) * 3 + 1.5` m.
b. **Ramat Gan's municipal GIS, the same way.** Ramat Gan is the box's east edge.
c. **GovMap (govmap.gov.il).** The user searched its layer catalogue for "גובה" and found
   only ground contours and noise maps.
   - Still check its buildings layers (מבנים).
   - Check its real-estate deals layer (עסקאות נדל"ן, the same data as nadlan.gov.il). If
     a deal gives the floor of the flat sold, the highest floor sold at each address is
     the building's floor count, or at least a lower bound. Check whether the ground floor
     counts as 0 or 1.
   - Find the address the page reads its data from: the page's scripts, or ask the user to
     open the browser's Network tab while clicking a building.
d. **The Survey of Israel's open data (המרכז למיפוי ישראל)**, if it has buildings with
   heights or floors.

**What to deliver:**
- **The extract:** the features in the box only, as GeoJSON in lon/lat, with only the
  fields needed. Put it at `game/streets/cities/data/<survey id>.geojson`.
- **The baker change:** teach `survey_fetch` to read `data/<id>.geojson` beside the city
  file before it tries the network. Then a re-bake anywhere, including GitHub's, keeps the
  heights. `tools/` must not name the game, which is why the path is relative to the city
  file.
- **For point sources** (one point per address): `survey_apply` matches only outlines.
  Add point matching: the point inside an OSM outline, else the nearest one within about
  5 m. Or match on the building's `addr`: the city file has it on buildings and keeps a
  list in `addrs`.
- **Apply it** with:

  ```bash
  python3 tools/osm_city.py --add-surveys game/streets/cities/givatayim.json
  ```

  Running it on an already-surveyed file is safe.

**Check the result:**
- How many heights are now measured (`hm`) and how many are still guessed (`g`).
- A few buildings you can name, against their real heights.
- No small outline (under 300 m²) taller than 40 m.
- The credit line is in the file's `credits`.

### 2. Kindergartens, shelters and playgrounds in Givatayim's box

Use GovMap's layers (גני ילדים, מקלטים, גני משחקים) or the municipality's.
- Deliver one points file: kind, name, lon/lat.
- Put it at `game/streets/cities/data/places_givatayim.geojson`, with the counts.
- Drawing them in the game is a later job for a cloud session: a kindergarten's fenced
  yard with a shade sail, a shelter's sign and concrete entrance.

### 3. data.gov.il

Use the CKAN API (`https://data.gov.il/api/3/action/...`) where you can. Its file
server, e.data.gov.il, refused the cloud even when allowed.
- **The vehicle register** (licensed private and commercial vehicles). Summarise it into
  one small JSON of shares for vehicles on the road now:
  - make (`tozeret_nm`), and the top models per make (`kinuy_mishari`);
  - colour (`tzeva_rechev`);
  - year bands.

  The game's traffic and its thousands of parked cars should look like Israel's roads:
  their mix of makes and their whites, silvers and greys. Commit the summary only.
- **The Ministry of Transport's public-transport lanes layer** (bus lanes; see the "bus
  lanes" bullet in `IDEAS.md`). Get its stretches in Givatayim and Ashdod.

### 4. Buses on their real lines (GTFS)

The feed is at gtfs.mot.gov.il: `israel-public-transportation.zip`, about 200 MB.
- For each box above, extract:
  - the stops;
  - the routes, with line number and operator;
  - their shapes;
  - one weekday's trips through the box, with times.
- Commit one compact JSON per town. Do not commit the zip.

## Notes and done

- **Keep notes as you go:**
  - a handoff section in `game/streets/DEV.md`: what each source is, how it was fetched,
    the licence, the counts, and what a cloud session should do with it;
  - update `IDEAS.md`'s data bullet, without naming the game outside its folder;
  - a lesson in the `real-places` skill if one is kit-wide, for example which sites
    refuse cloud servers.
- **Push to `main`** the way `CLAUDE.md` says. If a city file changed, tell the user that
  a cloud session should run the game's tests on it (`landmarks`, a playtest of the level).
- **Report back to the user:** what was found and what was not, each licence, and what
  is left. Then delete this file, or mark in it what is done.
