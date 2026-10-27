#!/usr/bin/env python3
"""sine-check.py WAV FREQ START_BYTE [END_BYTE]  — level and dropouts of one captured tone.

Reads the block of a 44.1 kHz s16 stereo capture (qemu-vm.sh AUDIO=wav) between two
byte offsets: take the file size before and after playing the tone (tone.cpp), wait
~2 s after the tone so QEMU flushes the tail. Prints RMS per channel (full scale = 1)
over the middle half of the block, and the number of dropouts: phase jumps of the
sine after the first 0.6 s (samples lost or repeated) plus runs of silence > 2 ms.

What is NOT counted, on purpose: QEMU converts the guest's stream (e.g. 96 kHz) to
44.1 kHz in chunks and leaves single-sample kinks of a few percent on the chunk
boundaries, in a pattern locked to the guest's buffer period, with or without the
code under test. They shift nothing, so they aren't dropouts; a sample-residual
"click counter" mistakes them for glitches (0-50 per tone, bursts of 100+).

Compare levels against the same tone played without the node or effect under test.
Exit status 1 when there are dropouts.
"""
import math, struct, sys

import numpy as np

RATE = 44100


def read_block(path, start, end=None):
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read() if end is None else f.read(end - start)
    n = len(data) // 4
    s = np.array(struct.unpack(f"<{n * 2}h", data[: n * 4]), float)
    return s[0::2], s[1::2]


def analyse(freq, left, right):
    n = len(left)
    a, b = n // 4, n - n // 4
    if b - a < RATE // 2:
        return None
    rms = lambda v: float(np.sqrt(np.mean(v[a:b] ** 2)) / 32768)
    ref = left if np.max(np.abs(left)) >= np.max(np.abs(right)) else right
    block = int(RATE / freq) * max(1, int(0.01 * freq))   # ~10 ms of whole cycles
    k = np.arange(block)
    cs, sn = np.cos(2 * np.pi * freq * k / RATE), np.sin(2 * np.pi * freq * k / RATE)
    phases = [math.atan2(-(ref[i:i + block] @ sn), ref[i:i + block] @ cs)
              for i in range(0, n - block, block)]
    lo, hi = int(0.6 * RATE) // block, (n - int(0.3 * RATE)) // block
    jumps = [i * block / RATE for i in range(max(1, lo), min(hi, len(phases)))
             if abs((phases[i] - phases[i - 1] + math.pi) % (2 * math.pi) - math.pi) > 0.2]
    peak = np.max(np.abs(ref[a:b])) or 1
    quiet = np.abs(ref[int(0.6 * RATE):n - int(0.3 * RATE)]) < 0.01 * peak
    edges = np.diff(np.concatenate(([0], quiet.astype(int), [0])))
    silent = int(np.sum((np.nonzero(edges == -1)[0] - np.nonzero(edges == 1)[0]) > RATE * 0.002))
    return {"L": rms(left), "R": rms(right), "dropouts": len(jumps) + silent,
            "jumps_at_s": [round(t, 3) for t in jumps[:10]], "seconds": round(n / RATE, 2)}


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(2)
    end = int(sys.argv[4]) if len(sys.argv) > 4 else None
    r = analyse(float(sys.argv[2]), *read_block(sys.argv[1], int(sys.argv[3]), end))
    print(r if r else "block too short (no audio captured?)")
    sys.exit(0 if r and r["dropouts"] == 0 else 1)
