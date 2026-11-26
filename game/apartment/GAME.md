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

- Outside: the flat is on the third floor of a street building, with a mirpeset you can
  walk onto and the street, trees and cars below. Behind it is the stairwell with a lift;
  the film starts on the street, rides the lift up and walks into the flat.
- Two garden flats (the last two levels): the same flats on the ground floor with a fenced
  garden (lawn, path, trees, a table, a lounger); the film walks in from the garden gate.

## Later (said, not built)

- Decorate a flat: add and remove furniture, keep the result (moving is built).
- A whole building: more than one flat to walk into (the plans for buildings exist in
  lab/apartments/building.py).
- The view of the real city from the windows (now a made-up street).
