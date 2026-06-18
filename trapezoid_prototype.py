#!/usr/bin/env python3
"""Prototype: multi-scale Truchet tiling on half-hexagon trapezoid tiles.

Validates the geometry before porting to the Processing sketch.

Canonical tile (short edge = 1): vertices CCW with the long edge first,
  (0,0) (2,0) (1.5,H) (0.5,H),  H = sqrt(3)/2.
The long edge carries TWO ports (Mitchell's multiple-points-per-side
generalization); every port is the central third of a unit segment, so band
width is 1/3 everywhere and the multi-scale thirds invariant holds.

Rep-4 subdivision: one child tilted along each leg, one upright bottom-middle,
one rotated 180 top-middle. Tiles are stored as (p0, e, depth) where
world(z) = p0 + z*e (complex similarity); a child is (p0 + q0*e, ec*e).

Every connection is a circular arc whose centre lies ON both port's edge
lines (corner, apex, or base midpoint), so bands cross edges perpendicularly
and the crossing width equals the annulus thickness, 1/3.

Outputs:
  trapezoid_alphabet.png - one tile per motif, with port-third ticks
  trapezoid_preview.png  - multi-scale field
"""
import cmath
import math
import random

from PIL import Image, ImageDraw

H = math.sqrt(3) / 2
THIRD = 1.0 / 3.0

# ---------------------------------------------------------------- geometry
V = [0 + 0j, 2 + 0j, 1.5 + H * 1j, 0.5 + H * 1j]   # CCW, long edge V0->V1
BASE_MID = 1 + 0j          # "virtual corner": children's corners land here
APEX = 1 + math.sqrt(3) * 1j   # legs extended meet here

# port centres (5 ports: 3 short edges + 2 unit segments on the long edge)
PORTS = {
    'B1': 0.5 + 0j,
    'B2': 1.5 + 0j,
    'R': 1.75 + (H / 2) * 1j,
    'T': 1.0 + H * 1j,
    'L': 0.25 + (H / 2) * 1j,
}

# connection -> (arc centre, mid radius, start deg, end deg), CCW sweep.
# Centres sit on both edge lines => perpendicular crossings.
CONNS = {
    ('L', 'B1'): (0 + 0j, 0.5, 0, 60),       # 60-degree corner arc
    ('R', 'B2'): (2 + 0j, 0.5, 120, 180),    # 60-degree corner arc
    ('T', 'R'): (1.5 + H * 1j, 0.5, 180, 300),   # 120-degree corner arc
    ('L', 'T'): (0.5 + H * 1j, 0.5, 240, 360),   # 120-degree corner arc
    ('B1', 'B2'): (1 + 0j, 0.5, 0, 180),     # U-turn at base midpoint
    ('L', 'R'): (APEX, 1.5, 240, 300),       # sweep below the cut-off apex
}

# motif alphabet: (connections, weight); 5 ports is odd, so one port is
# always unmatched -- the foreground wing nub caps it.
MOTIFS = [
    ([('L', 'B1'), ('R', 'B2')], 3),
    ([('L', 'B1'), ('T', 'R')], 3),
    ([('L', 'T'), ('R', 'B2')], 3),
    ([('L', 'T'), ('B1', 'B2')], 3),
    ([('T', 'R'), ('B1', 'B2')], 3),
    ([('L', 'R'), ('B1', 'B2')], 4),
    ([('B1', 'B2')], 1),
    ([('L', 'R')], 1),
]

# rep-4 children as (q0, ec): child_p0 = p0 + q0*e, child_e = ec*e
CHILDREN = [
    (0.5 + H * 1j, -0.25 - (H / 2) * 1j),   # tilted along left leg
    (2 + 0j, -0.25 + (H / 2) * 1j),         # tilted along right leg
    (0.5 + 0j, 0.5 + 0j),                   # upright, bottom middle
    (1.5 + H * 1j, -0.5 + 0j),              # rotated 180, top middle
]

CORNERS = V + [BASE_MID]

# port-third boundary points (for the alphabet sheet's tick marks)
UNIT_SEGS = [(0 + 0j, 1 + 0j), (1 + 0j, 2 + 0j),
             (V[1], V[2]), (V[2], V[3]), (V[3], V[0])]
TICKS = [a + (b - a) * t for a, b in UNIT_SEGS for t in (THIRD, 2 * THIRD)]

# ---------------------------------------------------------------- drawing
DARK = (36, 33, 38)
LIGHT = (240, 233, 215)


def band_poly(center, r, a0, a1):
    """Annulus-sector polygon (canonical coords), flat radial ends."""
    steps = max(16, int(abs(a1 - a0) / 2.5))
    outer, inner = [], []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        d = cmath.exp(1j * a)
        outer.append(center + (r + 1 / 6) * d)
        inner.append(center + (r - 1 / 6) * d)
    return outer + inner[::-1]


def disc(d, xy, r, fill):
    x, y = xy
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def draw_tile(d, p0, e, depth, motif, to_px, ppu):
    """ppu = pixels per canonical unit at scale |e|=1."""
    bg, fg = (DARK, LIGHT) if depth % 2 == 0 else (LIGHT, DARK)
    f = lambda z: to_px(p0 + z * e)
    s = ppu * abs(e)                      # short-edge length in pixels
    d.polygon([f(v) for v in V], fill=bg)
    for c in CORNERS:                     # wings: bg discs, spill allowed
        disc(d, f(c), s / 3, bg)
    for pair in motif:
        c, r, a0, a1 = CONNS[pair]
        d.polygon([f(z) for z in band_poly(c, r, a0, a1)], fill=fg)
    for c in PORTS.values():              # wings: fg nubs cap every port
        disc(d, f(c), s / 6, fg)


# ---------------------------------------------------------------- field
def render_field(path, W=1760, Hpx=1150, ppu=110, ss=3,
                 seed=11, prob=0.58, maxdepth=3):
    rng = random.Random(seed)
    leaves = []

    def collect(p0, e, depth):
        if depth < maxdepth and rng.random() < prob:
            for q0, ec in CHILDREN:
                collect(p0 + q0 * e, ec * e, depth + 1)
        else:
            motif = rng.choices([m for m, _ in MOTIFS],
                                [w for _, w in MOTIFS])[0]
            leaves.append((p0, e, depth, motif))

    cols = int(W / ppu / 3) + 2
    rows = int(Hpx / ppu / H) + 2
    for k in range(-1, rows):
        shift = 1.5 * (k % 2)
        for j in range(-2, cols):
            collect(complex(3 * j + shift, k * H), 1 + 0j, 0)          # up
            collect(complex(3 * j + 3.5 + shift, (k + 1) * H), -1 + 0j, 0)  # down

    sw, sh = W * ss, Hpx * ss
    ppu_ss = ppu * ss
    img = Image.new('RGB', (sw, sh), DARK)
    d = ImageDraw.Draw(img)
    to_px = lambda w: ((w * ppu_ss).real, sh - (w * ppu_ss).imag)

    leaves.sort(key=lambda t: t[2])       # coarse first: fine tiles on top
    margin = ppu_ss                        # wings spill at most s/3
    for p0, e, depth, motif in leaves:
        xs, ys = zip(*(to_px(p0 + v * e) for v in V))
        if max(xs) < -margin or min(xs) > sw + margin \
                or max(ys) < -margin or min(ys) > sh + margin:
            continue
        draw_tile(d, p0, e, depth, motif, to_px, ppu_ss)

    img.resize((W, Hpx), Image.LANCZOS).save(path)
    print(f'{path}: {len(leaves)} leaves')


# ---------------------------------------------------------------- alphabet
def render_alphabet(path, u=150, ss=2):
    cw, chh = 2.7, 1.5                    # cell size in canonical units
    cols = 4
    rows = (len(MOTIFS) + cols - 1) // cols
    W = int(cols * cw * u)
    Hpx = int(rows * chh * u)
    sw, sh = W * ss, Hpx * ss
    ppu_ss = u * ss
    img = Image.new('RGB', (sw, sh), (250, 248, 242))
    d = ImageDraw.Draw(img)
    to_px = lambda w: ((w * ppu_ss).real, sh - (w * ppu_ss).imag)

    for idx, (motif, _) in enumerate(MOTIFS):
        col, row = idx % cols, idx // cols
        p0 = complex(col * cw + 0.35, (rows - 1 - row) * chh + 0.3)
        draw_tile(d, p0, 1 + 0j, 0, motif, to_px, ppu_ss)
        f = lambda z: to_px(p0 + z)
        d.line([f(v) for v in V] + [f(V[0])],
               fill=(150, 150, 150), width=ss)
        for t in TICKS:                   # band edges must hit these exactly
            disc(d, f(t), 3 * ss, (220, 60, 50))

    img.resize((W, Hpx), Image.LANCZOS).save(path)
    print(f'{path}: {len(MOTIFS)} motifs')


if __name__ == '__main__':
    render_alphabet('trapezoid_alphabet.png')
    render_field('trapezoid_preview.png')
