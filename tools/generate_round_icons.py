"""Generate circular pre-masked `ic_launcher_round.png` rasters at every
Android density bucket.

Android adaptive icons (mipmap-anydpi-v26) already cover API 26+ and let
the launcher mask into any shape. Devices on API 21..25 (still supported
by our `minSdk = flutter.minSdkVersion`, i.e. 21) do NOT understand the
adaptive XML — they need a classic raster. If the manifest declares
`android:roundIcon`, round-icon launchers of that era render the raster
verbatim, so we ship a pre-masked circle to avoid them cropping our
square icon awkwardly.

The round raster uses the cat-only foreground (no 'Rabochiy VPN' wordmark)
so it reads at 48dp and never runs into the edge.

Run: `python tools/generate_round_icons.py`
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "images"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BG_RGB = (22, 26, 34)

# Android density buckets for launcher icon, per Material spec.
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def build_round_icon(size: int) -> Image.Image:
    """Return a size×size RGBA image: dark circle, cat centred inside,
    fully transparent outside the circle."""
    fg_src = Image.open(ASSETS / "logo_rabochiy_foreground.png").convert("RGBA")

    # Base circular disc in BG_RGB.
    disc = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    # Soften mask edge by half a pixel to avoid hard aliasing at small
    # densities.
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.6))
    bg = Image.new("RGBA", (size, size), (*BG_RGB, 255))
    disc.paste(bg, (0, 0), mask)

    # Scale cat foreground to ~78% of the disc — tighter than the 65%
    # used for the adaptive safe-zone because a circle mask already gives
    # us guaranteed visibility; we want the cat to read big and bold at
    # 48dp.
    target = int(size * 0.78)
    cat = fg_src.copy()
    cat.thumbnail((target, target), Image.LANCZOS)
    cx = (size - cat.width) // 2
    # Nudge down a touch for optical centring (the ears push visual mass
    # upward).
    cy = (size - cat.height) // 2 + int(size * 0.015)
    disc.paste(cat, (cx, cy), cat)

    return disc


def main() -> None:
    for folder, px in DENSITIES.items():
        out_dir = RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        img = build_round_icon(px)
        path = out_dir / "ic_launcher_round.png"
        img.save(path, format="PNG", optimize=True)
        print(f"wrote {path} ({px}x{px})")


if __name__ == "__main__":
    main()
