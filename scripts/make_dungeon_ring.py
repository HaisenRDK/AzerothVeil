#!/usr/bin/env python3
# Draws addon/Media/dungeon_ring.tga (the ring round a dungeon quest's objective icon, Engine/QuestLog.lua KindFrame):
# the game's dungeon icon's three teal waves, pixelled, the outline round the hole only, fading out outside.
# Usage: scripts/make_dungeon_ring.py addon/Media/dungeon_ring.tga
import math, struct, sys
G = 32                      # cells across: the pixels it shows (the game's icon is 29)
N = 128                     # the texture, each cell 4 x 4
R_OUT, R_IN = 0.98, 0.50    # the black outline included
OUT_W, IN_W = 0.10, 0.06    # outline widths (of the half size)
def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
def lerp(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
dark = (20, 37, 34); mid = (62, 101, 95); light = (81, 140, 140); white = (153, 192, 186); black = (12, 10, 6)
SS = 6
cells = []
for cy in range(G):
    row = []
    for cx in range(G):
        acc = [0.0] * 4
        for sy in range(SS):
            for sx in range(SS):
                dx = ((cx + (sx + .5) / SS) / G - .5) * 2; dy = ((cy + (sy + .5) / SS) / G - .5) * 2
                r = math.hypot(dx, dy); th = math.atan2(dy, dx)
                if r < R_IN - 0.03 or r > R_OUT + 0.03: continue
                a = smooth(R_IN - 0.03, R_IN + 0.01, r) * (1 - smooth(R_OUT - 0.20, R_OUT, r))   # (fading out towards the outside)
                band = (r - R_IN - IN_W) / (R_OUT - 0.08 - R_IN - IN_W)
                # three waves, winding the other way, tighter
                ph = 3 * th - 11.0 * math.log(r)
                w = 0.5 + 0.5 * math.cos(ph)
                arm = w ** 1.5
                lead = (0.5 + 0.5 * math.cos(ph + 0.55)) ** 8
                core = math.exp(-((band - 0.40) / 0.30) ** 2)
                i = max(0.0, min(1.0, 0.08 + 0.80 * arm * (0.55 + 0.45 * core) + 0.35 * lead * core))
                col = lerp(dark, mid, smooth(0.0, 0.5, i)) if i < 0.5 else lerp(mid, light, smooth(0.5, 0.9, i))
                if i > 0.9: col = lerp(col, white, smooth(0.9, 1.0, i) * 0.6)
                # the black outline, outside and round the hole
                edge = 1 - smooth(R_IN + IN_W - 0.02, R_IN + IN_W + 0.02, r)   # (the outline round the hole only)
                col = lerp(col, black, edge * 0.92)
                for k in range(3): acc[k] += col[k] * a
                acc[3] += a
        al = acc[3] / (SS * SS)
        rgb = tuple(acc[k] / acc[3] for k in range(3)) if acc[3] > 0 else (0, 0, 0)
        row.append((rgb, al))
    cells.append(row)
out = bytearray()
for y in range(N):
    for x in range(N):
        (r_, g_, b_), al = cells[y * G // N][x * G // N]
        out += bytes((int(b_ + .5), int(g_ + .5), int(r_ + .5), int(al * 255 + .5)))
open(sys.argv[1], 'wb').write(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28) + out)
