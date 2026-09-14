#!/usr/bin/env python3
"""
Generates placeholder SFX for Seaweed Shift as 16-bit mono 22050 Hz WAVs.

NOTE: pickup, dump, full, storm and happy hour are now real recordings in audio/.
This script no longer generates those four -- rerunning it will not overwrite
them. It only fills in the remaining placeholders.

The rest are deliberately chiptune-ish -- they suit pixel art as placeholders and
they make every hook audible so you can judge WHERE sound belongs before paying
for what it sounds like. Replace the files in audio/ with real ones later; the
filenames are the contract, nothing in the game code needs to change.
"""

import math
import os
import random
import struct
import wave

SR = 22050
# tools/ lives inside the project, so hop up one level to reach res://audio/
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print(f"  {name:<16} {len(samples)/SR:.2f}s")


def env(i, n, attack=0.01, release=0.6):
    """Simple attack/decay envelope, 0..1."""
    t = i / n
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = math.exp(-t / release)
    return a * r


def square(freq, i, duty=0.5):
    phase = (i * freq / SR) % 1.0
    return 1.0 if phase < duty else -1.0


def tone(freq, dur, wave_fn="square", release=0.35, amp=0.5, sweep=None):
    n = int(SR * dur)
    out = []
    for i in range(n):
        f = freq if sweep is None else freq + (sweep - freq) * (i / n)
        if wave_fn == "square":
            v = square(f, i)
        elif wave_fn == "saw":
            v = 2.0 * ((i * f / SR) % 1.0) - 1.0
        else:
            v = math.sin(2 * math.pi * f * i / SR)
        out.append(v * env(i, n, 0.005, release) * amp)
    return out


def noise(dur, release=0.3, amp=0.5, lowpass=0.0):
    n = int(SR * dur)
    out = []
    prev = 0.0
    for i in range(n):
        v = random.uniform(-1.0, 1.0)
        if lowpass > 0.0:
            v = prev + (v - prev) * (1.0 - lowpass)
            prev = v
        out.append(v * env(i, n, 0.002, release) * amp)
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def arp(freqs, note_dur, release=0.25, amp=0.45, wave_fn="square"):
    return seq(*[tone(f, note_dur, wave_fn, release, amp) for f in freqs])


print("Generating placeholder SFX...")

# --- gathering --------------------------------------------------------------
# --- money ------------------------------------------------------------------
# Richer and longer than a sale -- buying gear should feel like an event.
write("purchase.wav", mix(
    arp([392, 523, 659, 784, 1046], 0.08, 0.5, 0.32),
    tone(196, 0.45, "sine", 0.7, 0.22),
))

write("package.wav", arp([1046, 1318, 1568, 2093, 2637], 0.045, 0.22, 0.34, "sine"))

# --- pain -------------------------------------------------------------------
# The only genuinely bad thing in the game. Noise thud plus a falling tone so it
# reads as "you lost something" rather than just "bump".
write("hit.wav", mix(
    noise(0.38, 0.16, 0.55, lowpass=0.55),
    tone(240, 0.38, "saw", 0.22, 0.4, sweep=70),
))

write("rot.wav", mix(
    noise(0.26, 0.2, 0.3, lowpass=0.82),
    tone(180, 0.26, "saw", 0.25, 0.25, sweep=95),
))

# Low double pulse: reputation just crossed below target.

# --- weather ----------------------------------------------------------------
# --- shift end --------------------------------------------------------------
write("complete.wav", mix(
    seq(arp([523, 659, 784], 0.11, 0.4, 0.34),
        tone(1046, 0.55, "square", 0.9, 0.4)),
    tone(262, 0.9, "sine", 1.1, 0.22),
))

print(f"\nWrote {len(os.listdir(OUT))} files to {OUT}")
