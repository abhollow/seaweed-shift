"""Placeholder ferry horn for Playa del Carmen.

    python3 tools/make_ferry_audio.py

Writes audio/horn.wav: a low two-note ship's horn, 1.8s. A real recording can
replace it later -- this exists so the ferry's arrival is audible from day one,
since the horn is the player's warning that a wake is coming.
"""
import os
import wave

import numpy as np

SR = 44100


def horn(seconds=1.8):
    t = np.arange(int(SR * seconds)) / SR
    # Two notes a fifth apart, each a stack of harmonics -- the brassy buzz of
    # a real horn rather than a pure tone.
    x = np.zeros_like(t)
    for f0, gain in ((98.0, 1.0), (147.0, 0.7)):
        for k in range(1, 9):
            x += gain * np.sin(2 * np.pi * f0 * k * t) / k
    # a slight wobble in pitch, as a real horn has
    x *= 1.0 + 0.03 * np.sin(2 * np.pi * 5.5 * t)
    env = np.minimum(1.0, t / 0.12) * np.minimum(1.0, (seconds - t) / 0.45)
    x *= env
    return x / np.abs(x).max() * 0.6


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    x = np.clip(horn(), -1, 1)
    with wave.open(os.path.join(here, "audio", "horn.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("wrote audio/horn.wav")
