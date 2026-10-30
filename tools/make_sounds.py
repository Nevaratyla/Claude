"""Synthesises every sound effect of the game into assets/sounds/*.wav.

Run:  <venv>/bin/python tools/make_sounds.py   (needs numpy and scipy)
No recordings are used: wind, birds, crickets, the engine, the alien voice
and the rest are built from noise and oscillators, so the repo stays small
and there is nothing to license.
"""
import os

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sounds")
rng = np.random.default_rng(2026)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def lowpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def env(n, attack, release):
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def seamless(x, fade=0.5):
    """Crossfades the tail into the head so the clip loops without a click."""
    f = int(fade * SR)
    head = x[:f].copy()
    x = x[f:].copy()
    ramp = np.linspace(0, 1, f)
    x[-f:] = x[-f:] * (1 - ramp) + head * ramp
    return x


def save(name, x, peak=0.8):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("wrote", name, f"{len(x) / SR:.1f}s")


def wind(sec, strength=1.0):
    n = int(sec * SR)
    w = lowpass(rng.standard_normal(n), 500)
    gust = lowpass(rng.standard_normal(n), 0.4, 1)
    gust = 0.55 + 0.45 * gust / (np.max(np.abs(gust)) + 1e-9)
    leaves = bandpass(rng.standard_normal(n), 1500, 5000) * 0.15 * np.clip(gust - 0.4, 0, 1)
    return (w * gust + leaves) * strength


def chirp(dur, f0, f1, vib=0.0):
    t = t_axis(dur)
    f = np.linspace(f0, f1, len(t)) + vib * np.sin(2 * np.pi * 35 * t) * f0 * 0.05
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(len(t), 0.005, dur * 0.5)


def birds(sec, density=0.6):
    out = np.zeros(int(sec * SR))
    t = 0.3
    while t < sec - 1.0:
        # A short phrase of 2-6 notes from one bird.
        notes = rng.integers(2, 7)
        base = rng.uniform(2800, 5200)
        pos = t
        for _ in range(notes):
            d = rng.uniform(0.04, 0.12)
            c = chirp(d, base * rng.uniform(0.9, 1.15), base * rng.uniform(0.7, 1.3), rng.uniform(0, 1))
            i = int(pos * SR)
            out[i:i + len(c)] += c * rng.uniform(0.3, 1.0)
            pos += d + rng.uniform(0.02, 0.08)
        t = pos + rng.exponential(1.6 / density)
    return out


def ambient_day():
    # Long loop so it does not feel repetitive: gentle wind, a few distant birds.
    sec = 75.0
    x = wind(sec + 0.5) * 0.9
    b = np.zeros_like(x)
    b[:int(sec * SR)] += birds(sec, 0.22)
    x = x + lowpass(b, 6000) * 0.1
    save("ambient_day", seamless(x, 0.5), 0.6)


def ambient_evening():
    sec = 45.0
    n = int((sec + 0.5) * SR)
    t = np.arange(n) / SR
    x = wind(sec + 0.5, 0.6)
    # Crickets: several chirping at slightly different rates and pitches.
    for k in range(5):
        f = rng.uniform(4200, 5200)
        rate = rng.uniform(2.5, 4.0)
        gate = (np.sin(2 * np.pi * rate * t + rng.uniform(0, 6)) > 0.4).astype(float)
        trill = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 30 * t))
        x += np.sin(2 * np.pi * f * t) * lowpass(gate * trill, 300) * rng.uniform(0.02, 0.045)
    save("ambient_evening", seamless(x, 0.5), 0.55)


def engine():
    # 2 s loop with whole cycles of every component, so it loops perfectly.
    sec = 2.0
    t = t_axis(sec)
    f0 = 32.0
    x = np.zeros_like(t)
    for h, amp in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.25), (6, 0.12), (8, 0.06)]:
        x += amp * np.sin(2 * np.pi * f0 * h * t + rng.uniform(0, 6))
    # Firing pulses and exhaust noise.
    pulses = np.maximum(0, np.sin(2 * np.pi * f0 * 2 * t)) ** 6
    noise = lowpass(rng.standard_normal(len(t)), 900)
    x = x * 0.6 + pulses * 0.8 + noise * pulses * 0.6
    x = lowpass(x, 1800)
    save("engine_loop", x, 0.7)


def door():
    t = t_axis(0.6)
    thump = np.sin(2 * np.pi * 70 * t) * np.exp(-t * 18)
    body = lowpass(rng.standard_normal(len(t)), 600) * np.exp(-t * 25)
    click = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t * 90)
    save("door", thump + body * 0.8 + click * 0.3, 0.85)


def alien_voice():
    # Low warbling murmur with formant-like resonances: not quite speech.
    # Several phrases of different length and contour for the dialogue.
    for k, (sec, base, rate) in enumerate([(2.6, 95, 3.1), (1.6, 110, 3.8), (2.2, 85, 2.6), (1.2, 120, 4.4)]):
        t = t_axis(sec)
        f = base + 25 * np.sin(2 * np.pi * 0.7 * t + k) + 12 * np.sin(2 * np.pi * 5.3 * t)
        if k == 1:
            f = f * (1 + 0.25 * t / sec)        # rising: a question
        ph = 2 * np.pi * np.cumsum(f) / SR
        src = signal.sawtooth(ph)
        syll = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t + np.sin(2 * np.pi * 0.9 * t) * 2)
        y = np.zeros_like(t)
        for lo, hi, g in [(250, 450, 1.0), (900, 1300, 0.6), (2200, 2800, 0.25)]:
            y += bandpass(src, lo, hi) * g
        y *= syll * env(len(t), 0.08, 0.4)
        # Ring-modulated shimmer on top makes it uncanny.
        y += y * np.sin(2 * np.pi * (31 + k * 6) * t) * 0.6
        out = np.copy(y)
        for d, g in [(0.07, 0.4), (0.13, 0.3), (0.21, 0.2), (0.33, 0.12)]:
            n = int(d * SR)
            out[n:] += y[:-n] * g
        save(f"alien_voice{k}", out, 0.7)


def heartbeat():
    sec = 0.85
    t = t_axis(sec)
    x = np.zeros_like(t)
    for start, amp in [(0.0, 1.0), (0.24, 0.7)]:
        tt = np.clip(t - start, 0, None)
        x += amp * np.sin(2 * np.pi * 48 * tt) * np.exp(-tt * 22) * (t >= start)
    save("heartbeat", lowpass(x, 200), 0.9)


def sting():
    # Tension: low cluster swelling up with rising noise.
    sec = 3.5
    t = t_axis(sec)
    x = np.zeros_like(t)
    for f in [55, 58.3, 82.4, 87.3, 116.5]:
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6))
    swell = np.clip(t / 2.2, 0, 1) ** 2 * np.exp(-np.clip(t - 2.4, 0, None) * 3)
    noise = bandpass(rng.standard_normal(len(t)), 300, 3000) * np.clip(t / sec, 0, 1) ** 3
    save("sting", (x * 0.5 + noise * 0.4) * swell, 0.8)


def caught():
    t = t_axis(1.4)
    x = np.zeros_like(t)
    for f in [233, 247, 349, 370]:
        x += signal.sawtooth(2 * np.pi * f * t) * 0.3
    x = lowpass(x, 2500) * np.exp(-t * 2.5) * env(len(t), 0.005, 0.3)
    save("caught", x, 0.8)


def leaf():
    t = t_axis(0.4)
    n = rng.standard_normal(len(t))
    crack = (rng.random(len(t)) < 0.004).astype(float) * rng.standard_normal(len(t)) * 6
    x = bandpass(n * 0.4 + crack, 1200, 7000) * env(len(t), 0.01, 0.25)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 9 * t) ** 2
    save("leaf", x, 0.7)


def steps():
    # Soft paw pats: low, short, gentle (they play often, so they must not tick).
    for k in range(3):
        t = t_axis(0.11)
        x = lowpass(rng.standard_normal(len(t)), rng.uniform(450, 700), 3) * np.exp(-t * rng.uniform(40, 60))
        x *= env(len(t), 0.004, 0.06)
        save(f"step{k}", x, 0.35)


def tires():
    # Gravel crunch under rolling tyres, 2 s loop.
    sec = 2.5
    n = int(sec * SR)
    x = bandpass(rng.standard_normal(n), 300, 2500)
    grit = (rng.random(n) < 0.01).astype(float) * rng.standard_normal(n)
    x = x * 0.3 + highpass(grit, 1500) * 2.0
    save("tires_loop", seamless(lowpass(x, 3500), 0.5), 0.6)


if __name__ == "__main__":
    ambient_day()
    ambient_evening()
    engine()
    door()
    alien_voice()
    heartbeat()
    sting()
    caught()
    leaf()
    steps()
    tires()
