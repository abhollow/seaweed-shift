"""Synthesised wind for levels that have it (Veracruz first).

    python3 tools/make_wind_audio.py

Writes audio/wind_loop.ogg (a seamless 8s bed) and audio/gust.wav (a 2.4s
swell). Placeholders until real recordings are chosen -- but deliberately
built from band-passed noise with a moving centre frequency, which is what wind
actually is, so they sound like wind rather than hiss.
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100


def svf_bandpass(x, centre_hz, q):
    """State-variable band-pass with a per-sample centre frequency."""
    out = np.zeros_like(x)
    low = band = 0.0
    for i in range(len(x)):
        f = 2.0 * np.sin(np.pi * centre_hz[i] / SR)
        high = x[i] - low - q * band
        band += f * high
        low += f * band
        out[i] = band
    return out


def write_wav(path, x):
    x = np.clip(x, -1.0, 1.0)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def normalise(x, peak_db):
    return x / (np.abs(x).max() + 1e-9) * (10 ** (peak_db / 20.0))


def wind_loop(seconds=8.0, seed=3):
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    # Two slow, incommensurate wobbles in pitch and level: steady but alive.
    centre = 420 + 160 * np.sin(2 * np.pi * t / seconds) + 70 * np.sin(2 * np.pi * 3 * t / seconds + 1.3)
    x = svf_bandpass(noise, centre, 0.9)
    level = 0.75 + 0.25 * np.sin(2 * np.pi * 2 * t / seconds + 0.4)
    x = x * level
    # Seamless loop: blend the tail into the head.
    fade = int(SR * 0.6)
    ramp = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * ramp + x[-fade:] * (1 - ramp)
    x = x[:-fade]
    return normalise(x, -10.0)


def gust(seconds=2.4, seed=7):
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    p = np.linspace(0, 1, n)
    noise = rng.standard_normal(n)
    # The pitch rises into the gust and falls away -- the "whoosh".
    centre = 280 + 720 * np.sin(np.pi * p) ** 1.5
    x = svf_bandpass(noise, centre, 0.7)
    env = np.sin(np.pi * p) ** 1.8
    return normalise(x * env, -4.0)


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    audio = os.path.join(here, "audio")
    tmp = os.path.join(audio, "_wind_loop.wav")
    write_wav(tmp, wind_loop())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis",
                    "-q:a", "4", os.path.join(audio, "wind_loop.ogg")], check=True)
    os.remove(tmp)
    write_wav(os.path.join(audio, "gust.wav"), gust())
    print("wrote audio/wind_loop.ogg and audio/gust.wav")
