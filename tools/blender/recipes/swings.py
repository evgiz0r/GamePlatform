"""A playground swing set: an A-frame at each end, a top bar 3.4 m long, two seats on
chains. 2.4 m high, about 3.6 x 1.8 m. The swings swing along +X (the bar runs along Y)."""
import kit

H = 2.4
L = 3.4
SPREAD = 0.85     # the A-frame's feet, either side of the bar
for y in (-L / 2, L / 2):
    for sx in (-1, 1):
        kit.rod((sx * SPREAD, y, 0.0), (0.0, y, H), 0.05, "paint2", sides=8)
    kit.rod((-SPREAD * 0.45, y, H * 0.45), (SPREAD * 0.45, y, H * 0.45), 0.03, "paint2")   # a brace
kit.rod((0, -L / 2 - 0.1, H), (0, L / 2 + 0.1, H), 0.055, "paint", sides=8)                  # the top bar
for y in (-0.75, 0.75):
    for dy in (-0.2, 0.2):
        kit.rod((0, y + dy, H - 0.02), (0, y + dy, 0.48), 0.012, "metal", sides=4)          # chains
    kit.box((0.22, 0.5, 0.04), (0, y, 0.46), "rubber")                                       # the seat
