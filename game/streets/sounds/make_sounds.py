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

and the street's own life, which the game fades in and out by where you are and the hour
(the "sounds of the street" part of streets.gd):

  birds.wav       12 s    by day in the trees: house sparrows' cheeps, a bulbul's liquid
                          phrases, now and then a trill; near and far, a little room round them
  crickets.wav     4 s    at night in the gardens: two field crickets chirping at their own
                          rates, a tree cricket's soft trill under them
  voices.wav      10 s    people talking at a cafe or a shop a little way off: five voices'
                          syllables, vowels and pauses, muffled by the distance -- a murmur,
                          no words (the loop's ends are cross-faded)
  dog.wav        ~1.5 s   a dog barking twice a street or two away (not a loop)
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


def tone(f_of_t, env, harm=(1.0,)):
    """a note: its frequency (Hz, per sample) and loudness (per sample), a few harmonics"""
    ph = 2 * np.pi * np.cumsum(f_of_t) / R
    x = sum(a * np.sin(ph * (k + 1)) for k, a in enumerate(harm))
    return x * env


def circ_reverb(x, seconds, amount, seed):
    """a little room: circular (the loop stays a loop), a decaying noise tail"""
    n = len(x)
    m = int(R * seconds)
    rng = np.random.default_rng(seed)
    ir = np.zeros(n)
    ir[:m] = rng.normal(0, 1, m) * np.exp(-np.arange(m) / (m / 5))
    ir *= amount / np.sqrt((ir ** 2).sum())
    ir[0] += 1.0
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir), n)


def lowpass(x, hi, order=2):
    f = np.fft.rfftfreq(len(x), 1 / R)
    return np.fft.irfft(np.fft.rfft(x) * bp(np.maximum(f, 1.0), 1.0, hi, order), len(x))


def birds():
    T = 12.0
    n = int(R * T)
    x = np.zeros(n)
    rng = np.random.default_rng(31)

    def put(sig, at, gain):
        i = int(at * R)
        j = min(n, i + len(sig))
        x[i:j] += gain * sig[:j - i]

    def note(f0, f1, dur, shape=1.0):
        m = int(R * dur)
        t = np.arange(m) / m
        f = f0 + (f1 - f0) * t ** shape
        return tone(f, np.sin(np.pi * t) ** 2, (1.0, 0.12))

    t = 0.15
    while t < T - 1.6:   # (each call over before the loop ends: no seam)
        kind = rng.random()
        gain = rng.uniform(0.25, 1.0)
        if kind < 0.55:   # a sparrow: a run of cheeps
            k = rng.integers(2, 6)
            s = t
            for _ in range(k):
                a = rng.uniform(3000, 3600)
                put(np.concatenate([note(a, a * 1.35, 0.035), note(a * 1.3, a * 0.95, 0.05)]), s, gain)
                s += rng.uniform(0.14, 0.32)
            t = s
        elif kind < 0.85:   # a bulbul: three to five liquid notes, sliding
            s = t
            for _ in range(rng.integers(3, 6)):
                f0 = rng.uniform(1500, 2700)
                put(note(f0, f0 * rng.uniform(0.8, 1.3), rng.uniform(0.08, 0.18), 0.6), s, gain * 0.8)
                s += rng.uniform(0.12, 0.22)
            t = s
        else:   # a trill
            s = t
            f0 = rng.uniform(4200, 5600)
            for i in range(rng.integers(8, 15)):
                put(note(f0 * (1 - 0.01 * i), f0 * 0.82, 0.03), s, gain * 0.5)
                s += 0.055
            t = s
        t += rng.uniform(0.15, 1.1)
    x = circ_reverb(x, 0.25, 0.35, 32)
    return x / np.abs(x).max()


def crickets():
    T = 4.0
    n = int(R * T)
    tt = np.arange(n) / R
    x = np.zeros(n)
    for f, period, pulses, amp, off in [(4600, 0.5, 3, 1.0, 0.0), (4250, 0.4, 4, 0.6, 0.13)]:
        env = np.zeros(n)
        for c in np.arange(0, T, period):
            for p in range(pulses):
                s = int((c + off + p * 0.03) * R) % n
                m = int(0.018 * R)
                idx = (s + np.arange(m)) % n
                env[idx] += np.sin(np.pi * np.arange(m) / m) ** 2
        x += amp * env * np.sin(2 * np.pi * f * tt)
    x += 0.05 * (0.5 + 0.5 * np.sin(2 * np.pi * 45 * tt)) ** 4 * np.sin(2 * np.pi * 2900 * tt)   # (soft: a steady tone grates)
    x = circ_reverb(x, 0.2, 0.3, 33)
    return x / np.abs(x).max()


VOWELS = [(750, 1300), (500, 1800), (300, 2200), (500, 900), (320, 800)]   # a e i o u


def voices():
    T = 10.0
    xf = 0.6
    n = int(R * (T + xf))
    tt = np.arange(n) / R
    f = np.fft.rfftfreq(512, 1 / R)
    win = np.hanning(512)
    out = np.zeros(n)
    rng = np.random.default_rng(41)
    for v in range(5):
        f0 = rng.uniform(95, 135) if v % 2 == 0 else rng.uniform(170, 240)
        f0t = f0 * (1 + 0.12 * np.sin(2 * np.pi * tt * rng.uniform(0.2, 0.5) + rng.uniform(0, 6)))
        ph = 2 * np.pi * np.cumsum(f0t) / R
        src = sum(np.sin(ph * k) / k for k in range(1, 30))
        src += 0.08 * rng.normal(0, 1, n)
        # who talks when: phrases of syllables, pauses between
        env = np.zeros(n)
        vowel = np.zeros(n, dtype=int)
        s = rng.uniform(0, 1.5)
        while s < T + xf:
            e = s + rng.uniform(0.8, 2.6)
            while s < e:
                d = rng.uniform(0.14, 0.24)
                i, j = int(s * R), min(n, int((s + d) * R))
                if i >= n:
                    break
                k = np.arange(j - i) / max(j - i, 1)
                env[i:j] = np.sin(np.pi * k) ** 0.7 * rng.uniform(0.6, 1.0)
                vowel[i:j] = rng.integers(0, len(VOWELS))
                s += d
            s = e + rng.uniform(0.4, 1.8)
        # the vowel's formants on the source, frame by frame (overlap-add)
        y = np.zeros(n)
        for i in range(0, n - 512, 256):
            F1, F2 = VOWELS[vowel[i + 256]]
            shape = 0.05 + np.exp(-((f - F1) / 110) ** 2) + 0.7 * np.exp(-((f - F2) / 160) ** 2) + 0.25 * np.exp(-((f - 2700) / 300) ** 2)
            y[i:i + 512] += np.fft.irfft(np.fft.rfft(src[i:i + 512] * win) * shape, 512)
        out += y * env * rng.uniform(0.5, 1.0)
    fr = np.fft.rfftfreq(n, 1 / R)   # (a little way off: the highs gone; the voices' hum under 200 Hz too, or it is a drone)
    out = np.fft.irfft(np.fft.rfft(out) * bp(np.maximum(fr, 1.0), 220, 1900), n)
    m = int(R * xf)
    N = int(R * T)
    loop = out[:N].copy()
    fade = np.linspace(0, 1, m)
    loop[:m] = out[:m] * fade + out[N:N + m] * (1 - fade)
    loop = circ_reverb(loop, 0.4, 0.5, 42)
    return loop / np.abs(loop).max()


def dog():
    n = int(R * 1.6)
    x = np.zeros(n)
    rng = np.random.default_rng(51)
    for at, f0 in [(0.05, 520), (0.38, 470)]:
        m = int(R * 0.18)
        t = np.arange(m) / R
        f = f0 * (1.2 - 0.45 * t / 0.18)
        env = np.minimum(t / 0.008, 1.0) * np.exp(-t / 0.06)
        harm = [1.0 / (1 + abs(k * f0 - 900) / 400) for k in range(1, 12)]
        b = tone(f, env, harm)
        b += 0.5 * shaped_noise(0.18, lambda ff: bp(ff, 500, 3000), 52)[:m] * np.exp(-t / 0.035)
        i = int(at * R)
        x[i:i + m] += b
    x = lowpass(x, 2200)   # (a street or two away)
    tail = np.exp(-np.arange(int(R * 0.5)) / (R * 0.09)) * rng.normal(0, 1, int(R * 0.5))
    x = np.convolve(x, np.concatenate([[1.0], 0.04 * tail]))[:n]
    fade = np.ones(n)
    fade[-int(R * 0.2):] = np.linspace(1, 0, int(R * 0.2))
    x *= fade
    return x / np.abs(x).max()


SOUNDS = {"engine": lambda: engine(False), "engine_load": lambda: engine(True), "road": road,
          "wind": wind, "city": city, "birds": birds, "crickets": crickets, "voices": voices, "dog": dog}


def save(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(R)
        w.writeframes((np.clip(x * 0.85, -1, 1) * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    for name, make in SOUNDS.items():
        save(os.path.join(HERE, name + ".wav"), make())
        print(name + ".wav")
