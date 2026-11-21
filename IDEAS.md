# Ideas — things to build one day, not today

A parking lot for concepts about this kit. Nothing here is scheduled or in progress.
Adding a line costs nothing; it is a thought, not a promise. When one gets built, move
its notes to wherever the work lives and delete the line.

If you are the AI: read this before proposing new features, so you do not re-pitch what
is already parked, and when the person mentions something new that is not being built
right now, offer to add it here rather than letting it get lost in the chat.

## Games and content

- **Dialog as a shared system.** One game now has its own text box with portraits and
  multiple-choice answers. When a second game needs one, lift it out of that game into
  something both can use, rather than copying it.
- **Memory games.** Match pairs, repeat the sequence, that family.
- **2D open world.** A big map you wander instead of one screen.
- **3D open world.** "2D open world" above, but in 3D: `GameMode3D` exists now
  (`shell/game_mode_3d.gd`, see `reference/drop/`), so this is the open-world part. Biggest
  item on this list.
- **A guided tour of a real town.** A virtual tour on a baked real city
  (`tools/osm_city.py`): a guide leads you along a route, stops at the sights, turns your
  view to each and explains it -- what it is, its history, what to notice -- then walks on.
  The more real the town looks, the nicer the tour, so it rides on every realism pass a
  game on that town gets. Pieces that exist already: walking a recorded route at a
  person's pace with the head turning to look (one game replays filmed walks that way),
  a town's landmarks and places from OSM and official data. New: the tour's script (stops,
  where to look, the words, maybe spoken), a guide to follow, and a way to pause, ask,
  skip ahead. Leans on "Dialog as a shared system" above for the guide's lines.
- **Card games and card assets.** Deck, hand, table; and the art to go with it.
- **Game flow in open worlds.** State machines, a database of characters, states and
  dialogs. How do people actually structure this? Research first, then decide.
- **Open world of gambling.** You wander around and play mini games with bets. Every
  person you meet has their own riddle or game. Somewhere between math puzzles and
  spotting the scammer's trick. Leans on "2D open world" and "in-game dialog" above.
- **Dressing and clothes.** An open world where you start in bad clothes. People you
  meet present themselves and what they wear, and you pick what you want: sometimes you
  buy it, sometimes they give it to you for a reason. You see yourself wearing it, and
  everyone else wearing theirs. A visual game first. Needs layered outfit art, which the
  kit does not have today (see "Hand-drawn input" below).

## Platform and tooling

- **Bus lanes from official data, for baked Israeli towns.** The city baker
  (`tools/osm_city.py`) could take the Ministry of Transport's layer of existing bus and
  priority lanes (data.gov.il, dataset `nataz_kayam`, CC BY: credit it on screen beside
  OSM's): which stretches of the main roads have a bus-only lane -- on the right, the left,
  or down the centre behind a median -- its hours, and how many other lanes there are. A
  driving game on the town could then run buses and taxis in their own lane, paint it
  (אוטובוס / "BUS"), and keep traffic and its autopilot out of it. In late 2026 the layer had
  46 stretches in Ashdod and 4 in Givatayim. The stretches are given by street name and
  from/to, so matching them to OSM's ways is the fiddly part. Needs data.gov.il on the
  network allowlist. (OVER, over.org.il, mirrors the same layer but publishes no licence of
  its own: take it from data.gov.il. Its signalled-junction and roundabout layers matched
  OSM's almost exactly -- useful as a check in a scene test, not as data.)

- **Official data for what OSM leaves out, for baked Israeli towns.** A baked town's
  realism is capped by what OSM knows. In November 2026 OSM had no height for 90% of one
  town's buildings, 94% of another's, 65% of a city centre's (so they come out ~4 storeys
  where real streets have 15-25-storey towers behind the low blocks); a few dozen street
  trees in a town that has thousands; and a handful of the shops a filmed street showed.
  Where those could come from, biggest difference to the look first -- each needs its host
  on the network allowlist. Tel Aviv's GIS (gisn.tel-aviv.gov.il, ArcGIS REST, IView2
  MapServer) also has street trees with species (layer 628), lamp poles (543), licensed
  businesses (964), public-transport lanes with hours (611), parking zones (544):
  - *storeys or heights per building*: done for Tel Aviv (its GIS's buildings layer, in the
    baker's `SURVEYS`), and for Givatayim and the part of Ramat Gan beside it (their
    municipal layers' floor counts, saved once as extracts beside the city file because
    the first answers only inside its map viewer; see the `real-places` skill); other
    towns' municipal layers, GovMap / the Survey of Israel;
  - *kindergartens, shelters, gardens; the mix of cars; bus lanes; real bus lines*: done
    for the towns one game needed, from a municipal map, data.gov.il (the CKAN API: its
    file server refuses scripts) and the Ministry of Transport's GTFS;
  - *street trees with species* (ficus, jacaranda and palms read very differently):
    done for two towns, read by the baker (`TREE_SURVEYS`): a street-tree inventory with
    species, and crowns traced from the air with their size;
  - *businesses*, for whole rows of shopfronts: business-licensing layers (רישוי עסקים);
  - *when a building went up and what it is for* (a 1930s block, a 1960s shikun, a 2000s
    tower look nothing alike; which ground floors are shops): municipal building and
    land-use layers;
  - *buses on their real lines*: the Ministry of Transport's GTFS feed (gtfs.mot.gov.il);
    bus lanes above;
  - *paid-parking zones* (the kerb's blue-white paint), *street-light poles*, *road and
    pavement surfaces* (real widths): municipal layers, where a town publishes them;
  - *how busy each street is* and *each junction's light timing*: rarely published.
  OVER (over.org.il, which has an API and an MCP server) gathers many of these layers in
  one place and is a quick way to find them, but publishes no licence of its own: take
  each layer from its own publisher, under its licence, and credit it on screen beside
  OSM's. The terrain tiles the baker already reads cannot stand in for building heights
  (tried; see the `real-places` skill).

  What Tel Aviv's GIS holds, checked 20 Nov 2026 (layer id, then how many fall in a
  2.4 x 2.7 km box of the centre; ArcGIS REST `query`, `f=geojson`, `outSR=4326`; the list
  of all 256 layers is `IView2/MapServer?f=json`):
  - street trees with species and survey year (628): 3,743, where OSM has 178; tree canopy
    outlines 2024 (574); special trees (865);
  - construction sites with their stage (499): 328; building permits saying what is built
    (772): 1,724 -- cranes, hoardings, a block half-clad, the city's commonest sight;
  - buildings to preserve (682): 401, and the White City's declared area (671) -- with the
    survey's year, which blocks get the Bauhaus look;
  - licensed businesses with name and kind (964): 3,387, where OSM has 775 places;
  - lamp poles with their type (543): 7,105; hydrants (673): 815; motorbike parking (951):
    160; loading-zone signs with their hours (449): 113; taxi stands (691); bike paths with
    width (577); bike-share stations (835); sculptures (606); notice boards (841);
    drinking fountains (994);
  - kindergartens (768): 85, where OSM has 7; public shelters (592): 77, none in OSM;
    playgrounds (696): 54; daycare (624): 15 -- a kindergarten's fenced yard with its
    shade sail, a shelter's sign and concrete entrance;
  - signalled junctions (547): 109; the Ministry of Transport's bus stops (956): 235;
    light-rail lines and stations (760-766, 954);
  - how busy a street is: traffic noise at 4 m (786) as a stand-in; Waze jams (892), live
    only.
  GovMap (govmap.gov.il) is national, so it covers the neighbouring towns too: it shows
  kindergartens, shelters, schools and bus stops, but none of its public layers has
  building heights (a search for "גובה" gives ground contours and noise maps only). Its
  real-estate deals layer may give each sale's floor, whose highest per address would
  stand in for a building's storeys -- not checked. It is not reachable from the cloud
  yet, and the address its page reads from (a browser's Network tab) is needed first.
  National, each needing its host allowed: the vehicle registry on data.gov.il (the real
  mix of makes, models and colours, for traffic and parked cars); GTFS above.

- **Tracking verified music.** Which tracks are confirmed CC0 vs CC-BY, where they came
  from, what has been checked. Today this lives loosely in `assets/CREDITS.md` and a
  note in `assets/INDEX.md`.
- **Skills for recurring tasks and concepts.** Whenever something is done twice, or the
  AI notices it is new, it should suggest tracking it (as a skill, a doc, or whatever
  fits) so the next time is easier. This file is the first step of that.
- **Camera integration.** Use the player's webcam as an input or a texture.
- **Multiplayer, my computer as the server.** Something simple: one-versus-one.
- **Hand-drawn input.** Let the player draw their own assets online, or have the first
  interaction ask about and suggest assets instead of assuming the kit's art.
