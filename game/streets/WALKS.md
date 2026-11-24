# The filmed walks: what is still different from the films

The aim (the user's): bring each replay closer to its film, slowly, pass after pass --
by **details** (what stands where), **behaviour** (how people, cars and the walker move
and look) and **quality** (light, materials, the camera's own look). This is the list to
work from. Take a few items, biggest first; make them; record a side-by-side
(`DEV.md`, "The filmed walk": about 20 min); look; tick them off here (move them to
"Done" with the pass) and add what the new video shows. Film seconds are the walk's own
clock. Keep the films and anything past the walks' ends out of the repo.

Some items belong to other sessions' city-wide work (the light, buildings, pavements,
parking): marked *(city-wide)*. Do those with a look at what they did first, small and
focused, or leave them to them.

## Walk 1: Katzenelson to Ha-Meri (level 5, 96 s; `make_givatayim.py`)

### Measured against the full film (22 Nov 2026, before pass 15)
The user's original film is on their PC (1080x1920 upright, 30 fps, not mirrored; walk second
= film second). Scored second by second (`tests/film_score.py`) and its landmarks solved
(`tests/film_marks.py`, marks in `tests/marks/`); places as `P(s, off)` of `make_givatayim.py`.
Each item below is also in its section.
- **Score 33** over the walk: as alike as the film is to itself 5 s later (the film half a second
  on scores 67, one 55, two 45, three 40, five 33, ten 31, thirty -- another place -- 25). Best 20-29 s (40), worst 90-99 s
  (22) and the passage's 40-59 s (29-32). Worst seconds 42, 43, 52, 53, 67, 68, 91, 95.
- **The forecourt's layout (26-32 s, 58 marks, 3.7 px rms).** The film's bollards are a loose
  cluster of four by the walk's line, not a row across the forecourt: A P(11.7, -3.2),
  B (rusty) P(13.5, -1.7), C P(13.2, -2.9), D P(14.8, -2.5), each +-1.1 m; one more, E, far
  off at P(21.1, +3.1) +-1.6 by the hoop railing. The game: seven in a row at s 13.6 from off
  -6.6 to +4.2, and one at P(15.3, 0.2). The barrier's post P(23.1, +8.3) +-2.3 (game
  P(21.6, 5.3)): further on and further south-east. The left transformer pole P(17.8, -0.5)
  +-1.2 (game's twin poles P(16.6, -2.25)). The two women P(15.4, -5.4) and P(15.2, -6.3)
  (game P(14.0, -6.1), P(14.2, -6.8)): about right, a metre further on.
- **The forecourt at 31-32 s from the walk:** the film looks over open paving to the block
  on columns (cars parked under it) with the barrier in front ~8 m off, the transformer's
  poles on a concrete base to the right; the game's frame is filled by the white picket
  fence of the planted bed, with the barrier far back behind it and a plain block (no
  columns, no cars). The bed's front is in the open paving the film walks past.
- **The head in the forecourt:** the film looks 20 degrees further left at 26.5-27 s (at the
  bollards and the barrier, the women at its right edge) and tips 12-13 degrees further down
  at 27-28.5 s (at the paving), then 6-9 degrees further up at 30.5-31.5 s; the replay keeps
  its tilt at -15.5 throughout. At 26 s the film's phone stood ~3 m back from the replay's
  and ~0.7 m further from the block's wall (rough: its marks are all 9-13 m off).
- **The passage (40-53 s, pace-bound: places along it rest on pass 13's pace fit, +-3 m):**
  a white lamp pole with stickers and a red-ringed sign on top at P(33, -0.6) -- the film
  passes it close on the right at 43.5-44 s; the game has none. A small bin with a purple
  liner hung on that pole (44 s). The big black slotted bin at P(45.8, -0.4), passed at
  52.5-53 s; the game's is at P(41, -0.95) and passed before 50 s. A second pole stands right
  behind the big bin (s ~49, bearing only).
- **The passage's end (61-68 s):** the man in blue at the hoop railing is about right; at
  67-68 s a passer-by fills the replay's frame a metre off the camera (the film's is clear);
  the film has motorbikes and scooters parked on the left at 67.5 s, the game none.
- *(Pass 15 made the three below: the forecourt's layout and its far side, the passage's pole
  and bins, Ha-Meri's looks. Score 34.5 -> 35.3; seconds 93-94 +14 and +15, 29 and 49 +6-7.)*
- **Ha-Meri (89-96 s): the replay looks the wrong way.** The film looks along Ha-Meri at 90.5-
  91.5 s (cars parked down its left side) and across at its far pavement at 93-95.5 s (the
  white low wall and hedge, the kick scooter, a tree in a pit); the replay turns to yaw 41-50
  (Ha-Meri runs ~120-130) and 37 degrees down at 93.5-95.5 s, into the corner building's wall
  and front garden.

### Details
- [ ] Buildings along the route in their own colours and faces: warm cream and sand
      plaster, not white-grey; balcony rows with railings, many closed in; AC units on
      the walls; roller shutters; solar heaters and tanks on the roofs over the arcade
      block and the passage (film 0-30 s, 64-96 s). *(city-wide)*
- [ ] The block on columns at the forecourt's south-east: cars parked under it, its
      lobby and stair core seen between the columns (film 26-31 s).
- [ ] The arcade's columns: white, with a dark wooden cladding round the foot about half a
      metre high (film 19-22 s); the game's are plain light grey.
- [ ] The café on Katzenelson's north pavement behind the walk's start, its tables and
      awning; people at them (film 0-1 s).
- [ ] Katzenelson's north kerb north-west of the zebra: red and white as filmed (film 0.5 s),
      not the city's blue and white -- pass 4's `kerb_paint` there draws nothing visible
      (DEV.md, pass 12); and no guard railing beside the bollard (the city's).
- [ ] Cars parked along Katzenelson's far kerb, across the road from the wait (film 1-2.5 s:
      white and dark cars in a row past the arcade's motorbikes).
- [ ] The shops under the arcade: flat brown glass against the film's lit fronts -- the
      confectionery's glass door and yellow boards, the second shop's sign and colours, its
      branding above (film 15-21 s).
- [ ] A manhole cover in the arcade's dark pavers (film 19 s).
- [ ] The motorbikes as the film's: a white-and-blue naked bike, black scooters with top
      boxes, yellow number plates; a bicycle among them (film 19-24 s).
- [ ] The forecourt: the red-ringed round sign on its own pole by the twin poles (film
      29-31 s); the transformer's box and cables up the poles.
- [ ] The passage: yellow leaves scattered on the pavers (film 36-52 s); a second pole right
      behind the big bin (film 49-53 s, bearing only); the rough concrete low
      wall under the tall hedge (film 44-52 s); the bin's black slotted body is right,
      its lid and liner not.
- [ ] The passage's pavers a shade lighter and warmer than the game's (film 36-56 s).
- [ ] The little street: the parked cars as filmed -- a white SUV and two white cars
      (film 64-72 s); a second gatepost pair further on; the corner building's face. Its
      layout is a guess (pass 14: a 4 m street left of the passage's line): the film shows
      wide paving left of the walk at 67-71 s and cars further off, along Sheinkin and in a
      gap between the south-east blocks (s 60-64).
- [ ] Overhead wires along the little street and Sheinkin (film 72-80 s); the street
      lamps on their poles.
- [ ] Street name signs (Israel's white on blue) at Sheinkin's corner and Ha-Meri's;
      the "P" signs with their times; the no-entry sign by the transformer.
- [ ] Sheinkin's far corner: the yellow parking signs are two, not one; the booth's
      face (a screen, a card slot); the scooters' colours (film 82-86 s).
- [ ] Ha-Meri: trees in square earth pits along the kerb every ~8-10 m; cars parked
      both sides (the game's do it); a delivery scooter (film 88-96 s).
- [ ] Ha-Meri's far pavement (film 93-96 s): the low wall white plaster and stone with a
      hedge over it, an e-scooter (a kick scooter, teal) parked against it; the kerb jogs
      out where the parking bay starts.
- [ ] Small things: drain grates at the kerbs, utility cabinets at corners, stickers and
      graffiti on poles, a fire hydrant, chewing-gum stains on the slabs.

### Behaviour
- [ ] Katzenelson's traffic past 17 s, seen from the arcade and the forecourt (the film's
      first 17 s have five cars, all now sent as filmed).
- [ ] The talkers' hands: the characters have no talking or gesturing clip, so the three in
      the forecourt only turn to each other; a clip would need adding to the kit's art.
- [ ] Passers-by on Katzenelson and Ha-Meri walking past both ways (the city's walkers are
      there, not the film's).
- [ ] 26 s: the walk out of the arcade passes a metre from the block's side wall, which fills
      the right of the frame where the film sees open forecourt and the stair building far
      off -- start the slant ~1.5 m further left (P(7.9, -7.0)), then re-log and re-fit.
- [ ] The head in the forecourt: 20 degrees left at 26.5-27 s, 12-13 down at 27-28.5 s,
      6-9 up at 30.5-31.5 s (measured above).
- [ ] Under the arcade (18-24 s) the head is set, not measured (the fitted facing read half
      the turn there, pass 14): the film's frame by frame, read off the columns' and the
      motorbikes' row, would give its glances.
- [ ] A cyclist or an e-scooter rider passing on Sheinkin (common there; check the film
      at 76-90 s).

### Quality
- [ ] The light: the film's late morning is bright, slightly hazy, warm; shadows soft-edged
      and blue-grey, not near black; the sky pale near the horizon. *(city-wide)*
- [ ] The grade (pass 10's curve, both walks) refitted for the brighter light another session
      gave the city (the sun x1.12, the fill at 0.6, 21 Nov): record bare
      (`STREETS_FILM_LOOK=0`) and run `tests/film_look.py` as pass 10 did.
- [ ] Dappled shade under the passage's trees: patches of sun through the leaves moving
      on the pavers (film 33-56 s); the game's crowns cast plain blobs.
- [ ] The camera's own look, what is left of it: a touch of motion blur in the steps, its
      slight wide-angle bend at the edges, its sharpening halo on edges against the sky.
- [ ] Materials: plaster stained under the windows, concrete posts rough, the slabs'
      cracks sharper, the asphalt's patches; the zebra's paint worn to grey in the wheel
      tracks.
- [ ] People's look: real clothes and hair rather than the kit's chunky figures; heights
      checked (`tests/scale_check.gd`).
- [ ] Cars' look: the kit's boxy bodies against the film's real models -- rounder, glass
      that reflects, wheels with tyre walls; parked cars' dust.
- [ ] Trees as the film's species: ficus with dense dark crowns on Katzenelson, palms and
      bamboo in the passage's beds; leaf colour lighter and more varied.

## Walk 2: Sheinkin and Sirkin (level 6, 106 s; placed from a GPS track)

Its film is not in this repo or this machine's scratch: a session needs a clip of
1:42-3:08 of the user's film (under 10 MB, emailed) to set it beside the replay.

### Details
- [ ] The café tables and umbrellas on Sirkin stand on the walk's line: the walk goes
      through three of them at 57-63 s (`SCAN=1`). Move the walk or the tables as the film
      has them.
- [x] The walk runs right against cars parked half up on the pavement (60-70 s); the film
      walks clear of them -- put the walk on the pavement's back half there, or park
      those cars in the road. *(Its points at 52-68 s moved 0.3-0.6 m toward the shops: the
      cars' sides 1.1 m off, not 0.2-0.5; the trees at Sirkin's kerb ~1 m, not 0.65; the
      shopfronts 1.6 m. The stop at 69-79 s is where it was.)*
- [ ] The Roladin corner: its shop front, terrace and awning as filmed.
- [ ] Sirkin's shops: the computer shop, Ovad's Sabich (its yellow awning is in), a second
      shop beside it the map does not have (the user: two shops at 1:11).
- [ ] The Katznelson corner at the end: the pedestrian lights (red and green men), the
      push button on the pole, the zebra, the railings (100-106 s).
- [ ] Trees in pits along Sirkin, bins, bike racks, motorbikes on the pavement as filmed.
- [ ] Sirkin's street trees hang their lowest leaves at face height over the pavement: the
      walk passes one at 66 s (0.65 m off its trunk, at (486.5, -734.7)) through its leaves.
      Pruned street trees keep about 2.2 m clear over a pavement. *(city-wide: the trees)*
- [ ] At 28 s the walk heads straight at a street tree before stepping round its road side
      (a front garden's bougainvillea hangs over the pavement's back beside it, leaving 28
      cm): the film presumably walked between the tree and the wall.

### Behaviour
- [ ] Cars that stop for it on the Sheinkin zebra (its `zebras` are there, no `cars`):
      send one to stop, one to pass, as the film shows (6-14 s).
- [ ] At the Katznelson lights: wait for the green man, look left then right, cars
      passing on Katznelson meanwhile (99-106 s).
- [ ] People at the café tables sitting; passers-by.
- [ ] The head's looks against the film second by second (it has three; the film will have
      more).
- [ ] The walk's last 20 s (86-106) are timed from the GPS track's stops and laid by hand:
      check against the film once it is here.

### Quality
- [ ] As walk 1's: the light, the phone's look, materials, people and cars.

## Both walks
- [ ] Sound: footsteps, traffic, a scooter, voices -- the films have sound; the replays
      are quiet.
- [ ] A side-by-side for walk 2 as soon as its film is here (`tests/run.sh filmed_walk 6`).
- [ ] Re-run `SCAN=1` for both after every merge: other sessions' kerbside things
      (bollards, cabinets, motorbikes, tables) keep landing on the walks' lines.

## Done
- Pass 15 of walk 1 (DEV.md): what the full film's measures said, three of them. The forecourt
  as solved -- the bollards a cluster of four by the walk's line and one far off (not a row of
  seven), the barrier further on and out, the transformer's twin poles on their plinth across
  the passage's mouth, the planted bed's front back to s 19.5 so the film's open paving is
  open; the passage's white lamp pole with stickers, a red-ringed sign and a small bin with a
  purple liner hung on it (P(33, -0.6), a new prop), the big bin on to P(45.8, -0.75);
  Ha-Meri's looks as the film's frames show them (a walk's new `face`: down the street at
  125 degrees while crossing, back across at its far pavement at 200 from the far kerb, at the
  phone's usual tilt), found by sweeping the replay's camera round (`filmed_walk` `SWEEP`).
- Pass 14 of walk 1 (DEV.md): the forecourt as filmed -- out from under the arcade at the
  block's corner and across on a slant, the two women and the man in white 6 m ahead at 26 s
  with their scooter, a dark board wall behind them and a cabinet, the slabs to the block, the
  bed's front low; the arcade at the film's 1.3 m/s (the walk had gone on to the passage's line
  under it; the zebra was right) and looking along it, not at the shop windows; the passage
  straight on along the hedge onto the little street's pavement, past one railing and the man
  in blue, no car on it; the crossing's looks from the film's own frames (it looks left at the
  near half's cars, 3-5 s). Walk 2 round two new street trees and a car parked on its
  pavement (after a merge).
- Pass 13 of walk 1 (DEV.md): from the far kerb on, the walk's pace and the head's turns as the
  film's, measured on every frame (the camera's facing within a few degrees of the film's from
  19 s to the end; the pace's ups and downs, no stop at Sheinkin's corner); the film's people
  moving -- the man walking along the confectionery to the far kerb's railing, a third with
  the women in the forecourt, all three talking with their bodies, a woman crossing the
  passage's end in front of the man in blue.
- Pass 12 of walk 1 (DEV.md): Katzenelson's crossing as filmed -- tactile paving at the north
  kerb and through the median's cut, the median's ends raised red-paver blocks in a concrete
  kerb with a no-U-turn sign, a black bollard with a steel top; the walk waits 2 m back
  facing across, then beside the bollard, and stands by the cut's south-east side; the near
  half's black hatchback (2 s) and white SUV (3 s), the grey SUV at 12.4 s.
- Pass 11 of walk 1 (DEV.md): the phone exposes for what it sees (both walks: the arcade, the
  passage's shade and the sunny forecourt held near the film's steady brightness) and the
  arcade's paving mid-grey, not near black; Katzenelson's far half as filmed -- a white
  hatchback by, a white sedan waiting in the kerb lane, a grey SUV driving on past the walk.
- Pass 10 of walk 1, both walks' picture (DEV.md): the phone's picture measured and laid
  over the replays (`tests/film_look.py`: the bright end squeezed, not blown -- 0.1% clipped
  against the game's 4.4%; shade lifted; greys warmed; colour a little less); Ha-Meri's far
  kerb as filmed (a silver hatchback past the crossing, blue and white paint, no yard car on
  the pavement); the bougainvillea off the little street's pavement; the hand's sway doubled
  to read as the film's does.
- Pass 9 of walk 1, both walks (DEV.md): the phone in a hand -- tipped 15.6 degrees down
  as the film's horizon says (it was 11.3), swaying slowly as the film's does (0.25 degrees
  rms, 0.5-0.8 Hz, `tests/film_shake.py`; the steps' jolts are stabilised out of the film,
  so none are added) and rolling a little; looks up and down as well as across (down at
  Katzenelson's stripes 6-8 s and Ha-Meri's kerb 92-95 s, where it had looked into a tree).
- Passes 1-8 of walk 1 (DEV.md, "The filmed walk"): the street's geometry, the arcade,
  the forecourt, the passage, the little street, the crossings and their cars, the
  people standing, the booth, the bollards, the shops, the head's looks.
- Walk 2: the look left at the two shops (70-74 s) and the cars that blocked it; on to the
  Katznelson corner (to 106 s). Then, from its first recording that far: round two
  bougainvillea clumps on the pavement (1 s, 29 s); no bike rack where the city had put one
  across the walk's pavement (86 s: details' `clear`); the end 1.9 m from the corner's tree,
  not 1.0 (its trunk filled the last look); a passer-by who kept pace just ahead for 80 s
  now draws away after a few seconds (both walks). The fruit crates at 16 s are the green
  corner shop's, from the film: kept. Then another session placed the film's red hydrant at
  the corner (3:22) on the walk's last metre: the end moved to (487.5, -770.9), between it
  and the light's pole, 1.1 m or more from everything.
