"""The streets' driving sounds, made rather than recorded: python3 make_sounds.py (numpy).

Every one is a loop the game plays at a pitch and a volume it sets each frame (see the
"sounds of driving" part of streets.gd). Made so they loop without a seam -- the noises are
built in the frequency domain (a spectrum with random phases, turned back into a wave, is
periodic by construction), the engines from whole numbers of cycles -- and so that a
laptop's or a phone's small speaker can play them: the old engine was a buzz of sharp pulses
almost all below 200 Hz, which such speakers turn into a rough flutter, and it was the only
sound there was. Now the road's roar carries the speed and the engine sits under it.

  engine.wav       0.5 s  the engine at 1200 rpm: firing at 40 Hz, its harmonics falling away
                          smoothly, the crank's half order under it, a slow wobble in loudness
  engine_load.wav  0.5 s  the same under load: higher harmonics, a breath of intake noise
  road.wav         3 s    tyres on asphalt: a pinkish roar from 90 Hz to 1.4 kHz, a hump at 800
  wind.wav         3 s    wind round the car: 300 Hz - 3.5 kHz
  city.wav         8 s    the city round you, far off: low and soft, slowly breathing
  train.wav        4 s    a train going by (rails.gd, a 3D sound on each train): the wheels'
                          roar on the rails, the bogies' thump coach by coach (three coaches
                          a loop, so the rhythm loops too), a faint electric motor's whine
  train_horn.wav   1.4 s  its horn, two tones, pulling out of a station (not a loop)

`python3 make_sounds.py train train_horn` makes only those (the rest are left as they are).
"""
import os
import wave
import numpy as np

R = 22050
HERE = os.path.dirname(os.path.abspath(__file__))


def shaped_noise(seconds, shape, seed):
    n = int(R * seconds)
    f = np.fft.rfftfreq(n, 1 / R)
    rng = np.random.default_rng(seed)
    mag = shape(np.maximum(f, 1.0))
    mag[0] = 0
    x = np.fft.irfft(mag * np.exp(1j * rng.uniform(0, 2 * np.pi, len(f))), n)
    return x / np.abs(x).max()


def bp(f, lo, hi, order=2):
    return (1 / np.sqrt(1 + (lo / f) ** (2 * order))) * (1 / np.sqrt(1 + (f / hi) ** (2 * order)))


def road():
    hump = lambda f: 1 + 0.8 * np.exp(-((np.log(f / 800)) ** 2) / 0.3)
    return shaped_noise(3.0, lambda f: f ** -0.5 * bp(f, 90, 1400) * hump(f), 11)


def wind():
    return shaped_noise(3.0, lambda f: f ** -0.5 * bp(f, 300, 3500, 1), 12)


def city():
    x = shaped_noise(8.0, lambda f: f ** -1.0 * bp(f, 60, 700), 13)
    t = np.arange(len(x)) / R
    return x * (0.75 + 0.25 * np.sin(2 * np.pi * t * 3 / 8.0))   # (3 breaths in the loop)


def engine(load):
    n = int(R * 0.5)
    t = np.arange(n) / R
    rng = np.random.default_rng(21 if load else 22)
    amps = [0.5, 0.6, 0.55, 0.45, 0.35, 0.25, 0.18, 0.12, 0.08, 0.05] if load else \
        [1.0, 0.6, 0.38, 0.25, 0.16, 0.1, 0.06, 0.035]
    x = 0.3 * np.sin(2 * np.pi * 20 * t + 0.3) + 0.12 * np.sin(2 * np.pi * 60 * t + 1.1)
    for h, a in enumerate(amps, 1):
        x += a * np.sin(2 * np.pi * 40 * h * t + rng.uniform(0, 2 * np.pi))
    x *= 1 + 0.12 * shaped_noise(0.5, lambda f: bp(f, 4, 30, 1), 23 if load else 24)
    if load:
        x += 0.35 * shaped_noise(0.5, lambda f: bp(f, 250, 1800), 25) * (0.6 + 0.4 * np.sin(2 * np.pi * 40 * t) ** 2)
    return x / np.abs(x).max()


def train():
    n = int(R * 4.0)
    t = np.arange(n) / R
    roar = shaped_noise(4.0, lambda f: f ** -0.6 * bp(f, 60, 1600), 31)
    # the bogies: three coaches a loop, two bogies a coach, two axles a bogie, each a dull thump
    thump = np.zeros(n)
    burst = shaped_noise(4.0, lambda f: bp(f, 70, 380), 32)
    per = 4.0 / 3.0
    for c in range(3):
        for at in (0.08, 0.10 + per * 0.62):
            for ax in (0.0, 0.11):
                t0 = c * per + at + ax
                env = np.exp(-np.maximum(t - t0, 0) / 0.035) * (t >= t0)
                thump += env * burst
    whine = sum(a * np.sin(2 * np.pi * f * t + ph) for f, a, ph in ((440, 1.0, 0.0), (880, 0.4, 1.3), (1320, 0.2, 2.1)))
    x = roar + 0.9 * thump / np.abs(thump).max() + 0.08 * whine
    return x / np.abs(x).max()


def train_horn():
    n = int(R * 1.4)
    t = np.arange(n) / R
    x = np.zeros(n)
    for f0 in (370.0, 440.0):
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
        for h in range(1, 7):
            x += np.sin(2 * np.pi * f0 * h * np.cumsum(vib) / R) / h
    env = np.minimum(t / 0.05, 1.0) * np.minimum((1.4 - t) / 0.3, 1.0)
    x *= env
    return x / np.abs(x).max()


SOUNDS = {"engine": lambda: engine(False), "engine_load": lambda: engine(True), "road": road,
          "wind": wind, "city": city, "train": train, "train_horn": train_horn}


def save(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(R)
        w.writeframes((np.clip(x * 0.85, -1, 1) * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    for name, make in SOUNDS.items():
        if only and name not in only:
            continue
        save(os.path.join(HERE, name + ".wav"), make())
        print(name + ".wav")
