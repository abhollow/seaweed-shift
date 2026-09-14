#!/usr/bin/env python3
"""
Generates the weather/crowd ambience layers for Seaweed Shift.

Two looping beds and two sets of one-shots:
  rain_loop.ogg    continuous rain, plays for the whole storm
  thunder_1..3.ogg fired at random intervals during a storm
  crowd_loop.ogg   muffled bar crowd, plays for the whole Happy Hour
  yell_1..4.ogg    random shouts, heavily low-passed so no words are audible

The loops are crossfaded head-to-tail so they don't tick at the wrap point, then
encoded to Ogg Vorbis (Godot loops Ogg sample-accurately; MP3 cannot).

Run from anywhere:  python3 tools/make_ambience.py
Requires ffmpeg with libvorbis.
"""

import math
import os
import random
import struct
import subprocess
import tempfile
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")


# --- primitives -------------------------------------------------------------

def white(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(xs, cutoff_hz):
    """One-pole lowpass."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
    y = 0.0
    out = []
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(xs, cutoff_hz):
    lp = lowpass(xs, cutoff_hz)
    return [x - l for x, l in zip(xs, lp)]


def brown(n, leak=0.995, scale=0.03):
    """Integrated noise -- lots of low-frequency energy, good for rumble."""
    y = 0.0
    out = []
    for _ in range(n):
        y = y * leak + random.uniform(-1.0, 1.0) * scale
        out.append(y)
    return out


def normalize(xs, peak=0.9):
    m = max(abs(x) for x in xs) or 1.0
    k = peak / m
    return [x * k for x in xs]


def crossfade_loop(xs, fade_sec=1.0):
    """Fold the tail back over the head so the loop point is seamless."""
    f = int(SR * fade_sec)
    if f * 2 >= len(xs):
        return xs
    head = xs[:f]
    tail = xs[-f:]
    body = xs[f:-f]
    blended = []
    for i in range(f):
        t = i / f
        blended.append(head[i] * t + tail[i] * (1.0 - t))
    return blended + body


def write_wav(path, xs):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in xs:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def emit(name, xs, quality="4"):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    write_wav(tmp, xs)
    dest = os.path.join(OUT, name)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", tmp,
         "-c:a", "libvorbis", "-q:a", quality, dest],
        check=True,
    )
    os.unlink(tmp)
    kb = os.path.getsize(dest) / 1024
    print(f"  {name:<18} {len(xs)/SR:5.1f}s  {kb:6.0f} KB")


# --- rain -------------------------------------------------------------------

def make_rain(dur=12.0):
    n = int(SR * dur)
    # Rain is broadband hiss weighted to the high end, plus slow gusts.
    hiss = highpass(white(n), 900.0)
    body = lowpass(white(n), 5200.0)
    rumble = brown(n, 0.9992, 0.02)

    out = []
    for i in range(n):
        # Slow amplitude drift so it breathes instead of sitting flat.
        gust = 0.82 + 0.18 * math.sin(2 * math.pi * 0.07 * i / SR + 1.1) \
                    + 0.08 * math.sin(2 * math.pi * 0.23 * i / SR)
        out.append((hiss[i] * 0.55 + body[i] * 0.35 + rumble[i] * 2.2) * gust)

    return crossfade_loop(normalize(out, 0.72), 1.5)


def make_thunder(dur, crack, seed):
    random.seed(seed)
    n = int(SR * dur)
    rumble = lowpass(brown(n, 0.9997, 0.05), 420.0)
    body = lowpass(highpass(white(n), 160.0), 1300.0)
    snap = lowpass(white(n), 3200.0)

    out = []
    for i in range(n):
        t = i / n
        # Sharp opening crack, then a long uneven roll. Gains are set by
        # measured RMS, not by ear: raw brown noise is ~6x hotter than the mid
        # band, so an untuned mix is pure sub-bass that a phone speaker cannot
        # reproduce at all. The mid `body` layer carries the audible thunder.
        crack_env = math.exp(-t * 34.0) * crack
        roll = math.exp(-t * 2.4) * (
            0.75 + 0.25 * math.sin(2 * math.pi * 1.7 * i / SR + seed)
        )
        out.append(rumble[i] * 2.4 * roll
                   + body[i] * roll * 2.2
                   + snap[i] * crack_env * 1.5)

    # Short fade-in so the file never starts on a click.
    fin = int(SR * 0.004)
    for i in range(min(fin, n)):
        out[i] *= i / fin
    return normalize(out, 0.85)


# --- crowd ------------------------------------------------------------------

def make_crowd(dur=14.0):
    n = int(SR * dur)
    # Babble: several noise bands each amplitude-modulated at speech syllable
    # rates (3-7 Hz) and offset in phase, then muffled. No single voice is
    # legible because none of them are voices -- it just has the rhythm of one.
    layers = []
    for k in range(7):
        band = lowpass(highpass(white(n), 180.0 + k * 90.0), 900.0 + k * 260.0)
        rate = 3.0 + random.random() * 4.0
        phase = random.random() * 6.283
        wob = 0.5 + random.random() * 0.5
        layers.append((band, rate, phase, wob))

    room = lowpass(brown(n, 0.9995, 0.03), 180.0)

    out = []
    for i in range(n):
        # Room tone kept low: brown noise carries enormous low-frequency energy
        # and at any higher gain it buries the babble entirely.
        acc = room[i] * 0.30
        for band, rate, phase, wob in layers:
            env = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(2 * math.pi * rate * i / SR + phase))
            acc += band[i] * env * wob * 0.60
        out.append(acc)

    # Heard through the hotel bar's walls: everything above ~1.4k is gone.
    out = lowpass(out, 1400.0)
    return crossfade_loop(normalize(out, 0.60), 1.5)


def make_yell(dur, base_hz, seed):
    random.seed(seed)
    n = int(SR * dur)
    breath = lowpass(white(n), 1100.0)

    out = []
    for i in range(n):
        t = i / n
        # Pitch swoops up then sags -- reads as a shout, carries no words.
        f = base_hz * (1.0 + 0.30 * math.sin(math.pi * t) - 0.12 * t)
        vib = 1.0 + 0.02 * math.sin(2 * math.pi * 5.5 * i / SR)
        f *= vib
        ph = 2 * math.pi * f * i / SR
        # A couple of harmonics stand in for vowel formants.
        v = (math.sin(ph) * 0.6
             + math.sin(ph * 2.0) * 0.25
             + math.sin(ph * 3.0) * 0.12)
        env = min(1.0, t / 0.12) * math.exp(-max(0.0, t - 0.25) * 4.5)
        out.append((v * 0.8 + breath[i] * 0.35) * env)

    # The muffling is the point: past ~750 Hz there is nothing to decode.
    out = lowpass(out, 750.0)
    return normalize(out, 0.70)


# --- go ---------------------------------------------------------------------

print("Generating ambience...")
random.seed(7)
emit("rain_loop.ogg", make_rain())

for i, (dur, crack) in enumerate([(3.4, 0.55), (4.2, 0.30), (2.6, 0.80)], start=1):
    emit(f"thunder_{i}.ogg", make_thunder(dur, crack, i * 13))

random.seed(21)
emit("crowd_loop.ogg", make_crowd())

for i, (dur, hz) in enumerate([(0.75, 190), (0.55, 240), (0.90, 155), (0.62, 275)], start=1):
    emit(f"yell_{i}.ogg", make_yell(dur, hz, i * 31))

print("\nDone.")
