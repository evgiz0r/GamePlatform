"""A playground slide: a platform 1.2 m up on four posts under a little roof, a ladder up
the back, a curved chute down the front with its run-out on the ground. About 1 x 3.6 m,
2.4 m to the roof's top. +X is the way down the chute."""
import kit

H = 1.2          # the platform's height
P = 0.9          # the platform's side
# four posts and the roof's frame
for sx in (-1, 1):
    for sy in (-1, 1):
        kit.cyl(0.045, 2.2, (sx * P / 2, sy * P / 2, 1.1), "metal")
kit.box((P + 0.06, P + 0.06, 0.06), (0, 0, H), "wood")                   # the deck
kit.box((P + 0.3, P + 0.3, 0.05), (0, 0, 2.2), "paint", rot=(0, 0, 0))    # a flat roof...
kit.cyl(0.75, 0.25, (0, 0, 2.35), "paint", sides=4, radius2=0.05)         # ...and its pyramid top
# side rails round the deck, open to the chute (+X) and the ladder (-X)
for sy in (-1, 1):
    kit.box((P, 0.04, 0.5), (0, sy * P / 2, H + 0.35), "paint2")
# the ladder at the back, leaning a little
for sy in (-0.22, 0.22):
    kit.rod((-P / 2 - 0.55, sy, 0.0), (-P / 2, sy, H + 0.05), 0.03, "metal")
for k in range(1, 5):
    t = k / 5
    kit.rod((-P / 2 - 0.55 * (1 - t), -0.22, H * t), (-P / 2 - 0.55 * (1 - t), 0.22, H * t), 0.022, "metal")
# the chute: from the deck's edge, steep, easing out onto the ground
kit.tube([(P / 2, 0, H + 0.02), (P / 2 + 0.9, 0, H - 0.55), (P / 2 + 1.9, 0, 0.35), (P / 2 + 2.5, 0, 0.3)],
         0.55, "paint3", flat=True, depth=0.05)
# the run-out's foot
kit.cyl(0.04, 0.3, (P / 2 + 2.4, 0, 0.15), "metal")
