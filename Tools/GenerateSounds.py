#!/usr/bin/env python3
"""Synteza efektów dźwiękowych Rehab Runner (własne, bez zewnętrznych próbek). Użycie: python3 Tools/GenerateSounds.py iOS/Resources/Sounds"""
import math, os, random, struct, sys, wave
out = sys.argv[1] if len(sys.argv) > 1 else "Sounds"
os.makedirs(out, exist_ok=True)
SR = 44100
random.seed(3)

def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * 0.8)) * 32767)) for s in samples))

def tone(freq_fn, dur, shape="sine", vol=1.0, attack=0.005, decay=None):
    n = int(SR * dur); ph = 0.0; res = []
    for i in range(n):
        t = i / SR; f = freq_fn(t); ph += 2 * math.pi * f / SR
        v = math.sin(ph) if shape == "sine" else (1 if math.sin(ph) > 0 else -1) * 0.6 if shape == "square" else math.sin(ph) + 0.4 * math.sin(2 * ph)
        env = min(1, t / attack) * math.exp(-t * (decay if decay else 4 / dur))
        res.append(v * env * vol)
    return res

def mix(*tracks):
    n = max(len(t) for t in tracks); return [sum(t[i] if i < len(t) else 0 for t in tracks) for i in range(n)]
def seq(*parts):
    r = []
    for p in parts: r += p
    return r
def noise(dur, vol=1.0, decay=8, lp=0.3):
    n = int(SR * dur); y = 0.0; r = []
    for i in range(n):
        y += lp * (random.uniform(-1, 1) - y); r.append(y * vol * math.exp(-i / SR * decay))
    return r

write("coin", seq(tone(lambda t: 988, 0.07, "sine", decay=18), tone(lambda t: 1319, 0.28, "sine", decay=10)))
write("jump", tone(lambda t: 300 + 700 * t / 0.22, 0.22, "sine", decay=8))
write("slide", noise(0.35, 1, decay=5, lp=0.15))
write("lane", mix(noise(0.12, 0.7, 25, 0.2), tone(lambda t: 520 - 180 * t / 0.12, 0.12, "sine", 0.4, decay=20)))
write("hit", mix(noise(0.3, 1, 12, 0.4), tone(lambda t: 140 - 70 * t / 0.3, 0.3, "sine", 0.9, decay=10)))
write("rep", seq(tone(lambda t: 523, 0.09, "tri", decay=14), tone(lambda t: 659, 0.09, "tri", decay=14), tone(lambda t: 784, 0.28, "tri", decay=9)))
write("levelup", seq(*[tone(lambda t, f=f: f, 0.11, "tri", decay=12) for f in (523, 659, 784, 1047)], tone(lambda t: 1319, 0.45, "tri", decay=6)))
write("tap", tone(lambda t: 700, 0.05, "sine", decay=40))
write("reward", seq(*[tone(lambda t, f=f: f, 0.09, "sine", decay=10) for f in (784, 988, 1175, 1568)], mix(tone(lambda t: 1568, 0.5, "sine", decay=5), tone(lambda t: 2093, 0.5, "sine", 0.5, decay=5))))
write("pause", seq(tone(lambda t: 600, 0.08, "sine", decay=20), tone(lambda t: 450, 0.14, "sine", decay=14)))
print("OK")
