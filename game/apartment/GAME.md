# apartment

Walk round a made-up Israeli flat, in 3D, built from a floor plan.

## In Evgeni's words

> Lets start working on apratements, in separate to the cities, even in simulations of 1
> building or just the apatement with no view. there are a lot of topics... apartement
> schemes, building schemes, items in the apartements. doesnt have to be ultra realistic,
> can go slowly there by iterating crudely

> do we have to do things from tracks. i just want separate "simulation"

The goals for later (2026-11-26):

> scheme -> apartment walk
> apartment -> decorate it
> building -> walk into apartements ( will need to see performance around those transitions )
> apartement -> see the view of the city ( will need to see performance around those transitions )

## What it is now

A simulation, not a game: nothing to win or lose (the idle playtest "fails" for that, and
that is expected). Eight flats, one per level, each a 4-room Givatayim / Tel Aviv flat:
entrance, guest toilet, bathroom, mamad, bedrooms, hall, kitchen, salon with a sliding door
to the mirpeset, parents' room with its own shower room.

- Walk at eye height: arrows / WASD, or drag (sideways turns, up walks on).
- Shift (K) swaps to the dollhouse: the flat from above, ceilings off, room names.
- Space starts the guided tour: it walks every room by itself. A tap or click stops it.
- Decorate in the dollhouse: tap a piece of furniture to pick it up, drag it, "rotate"
  (or space) turns it, arrows nudge it. It will not go into a wall, out of the flat or onto
  another piece: let go there and it jumps back. Tap the floor to put it down.

## Later (said, not built)

- Decorate a flat: add and remove furniture, keep the result (moving is built).
- A whole building: walk in from the stairwell (the plans for buildings exist in
  lab/apartments/building.py).
- The view of the city from the windows.
