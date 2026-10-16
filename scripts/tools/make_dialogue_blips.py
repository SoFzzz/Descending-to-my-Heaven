"""Prepares the ending dialogue blips from the dmochas pack.

The pack originals peak at -17 to -25 dBFS with RMS of -30 to -36 dBFS; with the -12/-15 dB volume
they had in the game they ended at -35/-38 dBFS peak (inaudible).
Here three per voice are picked, normalized to a -3 dBFS peak and given a 2 ms fade.
Usage: python scripts/tools/make_dialogue_blips.py <ogg folder of the pack>
"""
import sys
import numpy as np
import soundfile as sf

PACK = sys.argv[1] if len(sys.argv) > 1 else "D:/ASSETS-PRUEBA/dmochas-dialogue_bleeps_pack/dmochas-dialogue_bleeps_pack/ogg"
OUT = "assets/audio/sfx/dialogue/"
VOICES = {"kaelen": [3, 10, 5], "elysia": [6, 16, 17]}   # low-mid / high
PEAK_DB = -3.0

for voice, picks in VOICES.items():
    for n, pick in enumerate(picks, 1):
        data, sr = sf.read("%s/bleep%03d.ogg" % (PACK, pick))
        if data.ndim > 1:
            data = data.mean(axis=1)
        data = data / np.abs(data).max() * 10 ** (PEAK_DB / 20)
        fade = int(sr * 0.002)
        ramp = np.linspace(0, 1, fade)
        data[:fade] *= ramp
        data[-fade:] *= ramp[::-1]
        sf.write("%s%s_%d.ogg" % (OUT, voice, n), data, sr, format="OGG", subtype="VORBIS")
