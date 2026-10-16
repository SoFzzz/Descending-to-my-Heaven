"""Recorta y normaliza (pico -6 dBFS) los sonidos de interfaz de assets/audio/sfx/ui/ a partir de la
biblioteca Be Not Afraid UI (Atelier Magicae). Los originales duran varios segundos y son graves
(centroide < 300 Hz en los anteriores): se eligen los mas claros y se recorta la parte util.
Uso: python scripts/tools/make_ui_sounds.py "D:/SFX/Be Not Afraid UI/--Unholy/Be Not Afraid UI"   (necesita numpy y scipy)."""
import sys
import numpy as np
from scipy.io import wavfile

SRC = sys.argv[1] if len(sys.argv) > 1 else "D:/SFX/Be Not Afraid UI/--Unholy/Be Not Afraid UI"
OUT = "assets/audio/sfx/ui/"
PEAK_DB = -6.0
# nombre final: (original, inicio s, fin s, fundido de entrada s, fundido de salida s)
CUTS = {
    "ui_move": ("BNA_UI1", 0.05, 0.28, 0.004, 0.08),
    "ui_confirm": ("BNA_UI21", 0.0, 0.60, 0.003, 0.15),
    "ui_back": ("BNA_UI6", 0.05, 0.42, 0.004, 0.12),
    "pause_open": ("BNA_UI7", 0.0, 0.60, 0.004, 0.2),
    "pause_close": ("BNA_UI26", 0.0, 0.50, 0.004, 0.18),
}

for name, (src, t0, t1, fin, fout) in CUTS.items():
    sr, d = wavfile.read(f"{SRC}/{src}.wav")
    d = d.astype(np.float64) / 32768.0
    if d.ndim > 1:
        d = d.mean(axis=1)
    d = d[int(t0 * sr):int(t1 * sr)]
    n_in, n_out = int(fin * sr), int(fout * sr)
    d[:n_in] *= np.linspace(0, 1, n_in)
    d[-n_out:] *= np.linspace(1, 0, n_out) ** 2
    d *= 10 ** (PEAK_DB / 20) / np.abs(d).max()
    wavfile.write(OUT + name + ".wav", sr, (d * 32767).astype(np.int16))
    print(name, src, "%.2f s" % (len(d) / sr), "rms %.1f dBFS" % (20 * np.log10(np.sqrt((d ** 2).mean()))))
