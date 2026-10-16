"""Prepara los blips de dialogo del final (Tarea 15) a partir del pack de dmochas.

Los originales del pack llegan con pico de -17 a -25 dBFS y RMS de -30 a -36 dBFS; con el
volumen de -12/-15 dB que se les daba en el juego quedaban en -35/-38 dBFS de pico (inaudibles).
Aqui se eligen tres por voz, se normalizan a -3 dBFS de pico y se les aplica un fundido de 2 ms.
Uso: python scripts/tools/make_dialogue_blips.py <carpeta ogg del pack>
"""
import sys
import numpy as np
import soundfile as sf

PACK = sys.argv[1] if len(sys.argv) > 1 else "D:/ASSETS-PRUEBA/dmochas-dialogue_bleeps_pack/dmochas-dialogue_bleeps_pack/ogg"
OUT = "assets/audio/sfx/dialogue/"
VOICES = {"kaelen": [3, 10, 5], "elysia": [6, 16, 17]}   # grave-medio / agudo
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
