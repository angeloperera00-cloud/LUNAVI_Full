#!/usr/bin/env python3
"""Generate LUNAVI's bundled *illustrative* assets.

1. Lunavi/Resources/MapAssets/illustrative_south_pole_terrain.jpg
   A procedurally generated crater field, shaded with a low Sun (12 deg) and cast
   shadows. It is NOT NASA data and is NOT georeferenced: the app labels it
   "Illustrative terrain - not NASA data - not to scale". Replace it with a
   LOLA-derived basemap using ScienceService (see README).
2. Lunavi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
   A custom crescent-and-horizon mark (no SF Symbols, no NASA insignia).

Deterministic: fixed random seed. Requires numpy and Pillow.
Usage: python3 Tools/generate_illustrative_assets.py [repo_root]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 3072
SEED = 20261120


def fractal_noise(n, beta, rng):
    white = rng.standard_normal((n, n))
    spectrum = np.fft.fft2(white)
    ky = np.fft.fftfreq(n)[:, None]
    kx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1.0
    spectrum *= k ** (-beta / 2.0)
    spectrum[0, 0] = 0.0
    field = np.real(np.fft.ifft2(spectrum))
    return (field - field.mean()) / field.std()


def add_crater(h, cx, cy, r, fresh=True):
    n = h.shape[0]
    ext = int(r * 2.8) + 2
    x0, x1 = max(0, int(cx - ext)), min(n, int(cx + ext))
    y0, y1 = max(0, int(cy - ext)), min(n, int(cy + ext))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(xx - cx, yy - cy) / r
    depth = 0.42 * r if r < 60 else 0.30 * r
    rim = (0.075 if fresh else 0.045) * r
    rim_width = 0.11 if fresh else 0.24
    bowl = np.where(d < 1.0, -depth * (1.0 - np.clip(d, 0, 1) ** 2.2), 0.0)
    if r > 120:  # flat floor on large craters
        bowl = np.maximum(bowl, -depth * 0.82)
    rim_profile = rim * np.exp(-((d - 1.0) / rim_width) ** 2)
    ejecta = np.where(d > 1.0, rim * 0.45 * np.clip(d, 1.0, None) ** -3.0, 0.0)
    h[y0:y1, x0:x1] += bowl + rim_profile + ejecta


def ridge_distance(n, points):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    best = np.full((n, n), np.inf, dtype=np.float32)
    for (ax, ay), (bx, by) in zip(points[:-1], points[1:]):
        ax, ay, bx, by = ax * n, ay * n, bx * n, by * n
        vx, vy = bx - ax, by - ay
        t = np.clip(((xx - ax) * vx + (yy - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        dist = np.hypot(xx - (ax + t * vx), yy - (ay + t * vy))
        best = np.minimum(best, dist)
    return best


def terrain():
    rng = np.random.default_rng(SEED)
    h = 7.0 * fractal_noise(N, 2.3, rng) + 2.5 * fractal_noise(N, 1.6, rng)

    # A long illustrative ridge passing through the demo sites (A at 0.46,0.53; B at 0.57,0.44).
    ridge = ridge_distance(N, [(0.18, 0.86), (0.33, 0.66), (0.46, 0.53), (0.57, 0.44), (0.70, 0.32), (0.86, 0.17)])
    modulation = 0.75 + 0.25 * fractal_noise(N, 3.0, rng)
    h += 80.0 * np.exp(-(ridge / 62.0) ** 2) * modulation + 18.0 * np.exp(-(ridge / 200.0) ** 2)

    # Two broad massifs.
    yy, xx = np.mgrid[0:N, 0:N]
    for cx, cy, s, a in [(0.80, 0.52, 260, 45), (0.36, 0.12, 300, 38)]:
        h += a * np.exp(-(((xx - cx * N) ** 2 + (yy - cy * N) ** 2) / (2 * s * s)))
    del yy, xx

    # Large illustrative craters (kept clear of the demo sites).
    for cx, cy, r in [(0.24, 0.30, 460), (0.77, 0.75, 330), (0.10, 0.70, 250), (0.60, 0.07, 210)]:
        add_crater(h, cx * N, cy * N, r, fresh=False)

    # Power-law crater population.
    for _ in range(140):
        add_crater(h, rng.uniform(0, N), rng.uniform(0, N), rng.uniform(40, 140), fresh=rng.random() < 0.5)
    radii = 3.0 * (1 - rng.random(3200)) ** (-1 / 1.6)
    for r in np.clip(radii, 3, 36):
        add_crater(h, rng.uniform(0, N), rng.uniform(0, N), float(r), fresh=rng.random() < 0.7)
    return h, rng


def shade(h, rng, sun_elevation_deg=12.0):
    t = np.tan(np.radians(sun_elevation_deg))
    gy, gx = np.gradient(h)
    norm = np.sqrt(gx ** 2 + gy ** 2 + 1.0)
    # Light from the left (-x), low elevation; slight component from the top.
    lx, ly, lz = -np.cos(np.radians(sun_elevation_deg)) * 0.94, -0.34 * np.cos(np.radians(sun_elevation_deg)), np.sin(np.radians(sun_elevation_deg))
    lam = np.clip((-gx * lx + -gy * ly + lz) / norm, 0, None)

    # Cast shadows along rows (light travels toward +x).
    cols = np.arange(N, dtype=np.float64)[None, :]
    g = h + cols * t
    shadow_height = np.maximum.accumulate(g, axis=1) - cols * t
    lit = (h >= shadow_height - 0.5).astype(np.float64)
    # Soften shadow edges slightly (3-tap box along both axes).
    lit = (lit + np.roll(lit, 1, axis=1) + np.roll(lit, -1, axis=1)) / 3.0
    lit = (lit + np.roll(lit, 1, axis=0) + np.roll(lit, -1, axis=0)) / 3.0
    albedo = 0.86 + 0.07 * fractal_noise(N, 2.0, rng) + 0.03 * fractal_noise(N, 0.8, rng)
    image = albedo * (0.03 + 1.45 * lam * lit)
    image = np.clip(image, 0, 1) ** (1 / 1.35)
    grain = 0.012 * rng.standard_normal(image.shape)
    return np.clip(image + grain, 0, 1)


def write_terrain():
    h, rng = terrain()
    img = shade(h, rng)
    out = os.path.join(ROOT, "Lunavi", "Resources", "MapAssets", "illustrative_south_pole_terrain.jpg")
    Image.fromarray((img * 255).astype(np.uint8), mode="L").save(out, quality=84, optimize=True, progressive=True)
    print("terrain:", out, os.path.getsize(out) // 1024, "KiB")


def write_icon():
    s = 4096  # supersample
    bg = (0x10, 0x17, 0x19)
    ink = (0xF2, 0xF1, 0xEB)
    amber = (0xE6, 0xB7, 0x6E)
    icon = Image.new("RGB", (s, s), bg)
    mask_outer = Image.new("L", (s, s), 0)
    d = 0.56 * s
    cx, cy = 0.5 * s, 0.45 * s
    ImageDraw.Draw(mask_outer).ellipse([cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2], fill=255)
    cut = Image.new("L", (s, s), 0)
    ox, oy, cd = cx - d / 2 + 0.32 * d, cy - d / 2 - 0.08 * d, 0.9 * d
    ImageDraw.Draw(cut).ellipse([ox, oy, ox + cd, oy + cd], fill=255)
    crescent = Image.fromarray(np.where(np.array(cut) > 0, 0, np.array(mask_outer)).astype(np.uint8))
    icon.paste(Image.new("RGB", (s, s), ink), (0, 0), crescent)
    draw = ImageDraw.Draw(icon)
    horizon_y = 0.775 * s
    sun_r = 0.045 * s
    sun_x = 0.66 * s
    draw.pieslice([sun_x - sun_r, horizon_y - sun_r, sun_x + sun_r, horizon_y + sun_r], 180, 360, fill=amber)
    draw.rectangle([0.17 * s, horizon_y, 0.83 * s, horizon_y + 0.011 * s], fill=amber)
    out = os.path.join(ROOT, "Lunavi", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    icon.resize((1024, 1024), Image.LANCZOS).save(out, optimize=True)
    print("icon:", out, os.path.getsize(out) // 1024, "KiB")


if __name__ == "__main__":
    write_icon()
    write_terrain()
