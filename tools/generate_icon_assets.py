"""Generate Rabochiy VPN app-icon source assets from the user-provided art.

Produces two files under `assets/images/`:

* `logo_rabochiy.png` — 1024x1024 square, solid dark fill behind the whole
  card (cat + 'Rabochiy VPN' wordmark), **no baked-in rounded corners**.
  Used by iOS and as the pre-API-26 Android launcher icon; the OS rounds
  the corners itself, so the source must stay square to avoid the classic
  "rounded inside rounded" double-corner artefact.

* `logo_rabochiy_foreground.png` — 1024x1024, transparent background, the
  cat head only, sized to ~65% of the canvas so it sits comfortably
  inside the adaptive-icon "sweet spot" (66dp of 108dp). Paired with a
  solid `adaptive_icon_background` color in `pubspec.yaml`, this renders
  cleanly under every launcher mask shape (circle, squircle, rounded
  square, teardrop) without clipping anything important.

The `Rabochiy VPN` wordmark deliberately does *not* appear in the adaptive
foreground: on circular masks it would get cropped, and every Android
launcher already prints the app label beneath the icon from the
`android:label` manifest attribute.

Run with:

    python tools/generate_icon_assets.py

Requires: Pillow (PIL). Input: `C:/Users/admin/Downloads/rabochiy.png`.
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image


SRC = Path(r"C:/Users/admin/Downloads/rabochiy.png")
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "images"

# Uniform background tint used everywhere — flat dark with a faint blue
# bias so it blends into the app's liquid-glass theme. The source card
# has a subtle gradient (brighter centre, darker bottom / corners); we
# replace the whole thing with this solid colour so iOS + Android
# launchers end up with a consistent dark square whatever shape mask
# they apply on top.
BG_RGB: tuple[int, int, int] = (22, 26, 34)

# Source geometry measured from the input art. Anything outside the card
# bbox is just the pure-black page around the rounded rectangle, which we
# throw away.
CARD_BOX = (84, 71, 1170, 1176)  # left, top, right+, bottom+ — roughly square

# Cat face bbox in the source — used to isolate it for the adaptive
# foreground layer. Deliberately stops above `y=860` so none of the
# 'Rabochiy VPN' wordmark leaks into the adaptive foreground (text would get
# clipped by circular launcher masks anyway).
CAT_BOX = (290, 220, 960, 860)

# Output canvas. 1024 is the de-facto standard for `flutter_launcher_icons`
# and is large enough to downscale cleanly for every density bucket.
CANVAS = 1024


def _fit_contain(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize `img` to fully contain inside `size` preserving aspect."""
    img = img.copy()
    img.thumbnail(size, Image.LANCZOS)
    return img


# Content bbox — a tight crop around the cat + wordmark that deliberately
# sits *inside* the rounded card, with zero rounded corners caught in the
# frame. Dimensions empirically measured from the source so the content
# occupies the same visual proportions as in the original artwork.
CONTENT_BOX = (220, 200, 1030, 1030)


def _paint_card_background(rgb: Image.Image) -> Image.Image:
    """Flatten every "card background" pixel of `rgb` to the uniform
    [`BG_RGB`] fill, leaving only the saturated green strokes and the
    bright white wordmark glyphs untouched.

    The source card has a radial-ish gradient from the slightly-brighter
    centre to darker corners. Pasting that gradient as-is on the icon
    canvas makes the card's original rounded shape visible as a halo. By
    flattening all low-saturation dark pixels to a single colour we make
    the final icon indistinguishable from a purpose-built flat square —
    iOS / Android can then round it themselves on top.

    Heuristic per pixel:
      * saturation ≥ 25 → keep (green strokes).
      * max RGB ≥ 200  → keep (white wordmark 'VPN').
      * otherwise       → replace with `BG_RGB` (card background).
    """
    out = rgb.copy()
    in_px = rgb.load()
    out_px = out.load()
    w, h = rgb.size
    for y in range(h):
        for x in range(w):
            r, g, b = in_px[x, y]
            mx = max(r, g, b)
            mn = min(r, g, b)
            if (mx - mn) >= 25 or mx >= 200:
                continue  # content pixel — keep original colour
            out_px[x, y] = BG_RGB
    return out


def build_main_icon(src: Image.Image) -> Image.Image:
    """Main `logo_rabochiy.png` — cat + wordmark on a clean flat-dark
    square, no rounded corners, no gradients, no halo."""
    content = src.crop(CONTENT_BOX).convert("RGB")
    flattened = _paint_card_background(content)

    # Paste the flattened content onto a full-bleed BG_RGB canvas at the
    # output resolution, preserving aspect. A light 3% inset all around
    # keeps iOS's mask from clipping into the text on its rounded-square
    # preview.
    canvas = Image.new("RGB", (CANVAS, CANVAS), BG_RGB)
    inset = int(CANVAS * 0.03)
    fit = _fit_contain(flattened, (CANVAS - inset * 2, CANVAS - inset * 2))
    ox = (CANVAS - fit.width) // 2
    oy = (CANVAS - fit.height) // 2
    canvas.paste(fit, (ox, oy))
    return canvas


def _key_background_to_alpha(rgba: Image.Image) -> None:
    """In-place alpha key: make the dark card background fully
    transparent while keeping the green strokes and any bright pixels
    opaque.

    Uses a saturation + brightness heuristic rather than pure luminance
    because the card's interior ramps up to ~(38,42,51) which overlaps
    the anti-aliased green edges in a naive luma threshold."""
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            mx = max(r, g, b)
            mn = min(r, g, b)
            sat = mx - mn
            if sat >= 25 or mx >= 170:
                # Saturated (green cat) or bright (not present here but
                # cheap to keep) — opaque.
                px[x, y] = (r, g, b, 255)
            elif mx <= 10:
                # Pure black corner — fully transparent.
                px[x, y] = (r, g, b, 0)
            else:
                # Dark low-saturation pixel (card fill or anti-aliased
                # halo). Drop to transparent so the adaptive background
                # layer shows through instead of a flat rectangle of the
                # card colour.
                px[x, y] = (r, g, b, 0)


def build_adaptive_foreground(src: Image.Image) -> Image.Image:
    """`logo_rabochiy_foreground.png` — cat head only, 65% of canvas,
    transparent background, centred. Sits comfortably within the adaptive
    icon safe zone."""
    cat_rgba = src.crop(CAT_BOX).convert("RGBA")
    _key_background_to_alpha(cat_rgba)

    # Target size: 65% of canvas — within the 66/108 "sweet spot".
    target = int(CANVAS * 0.65)
    fitted = _fit_contain(cat_rgba, (target, target))

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ox = (CANVAS - fitted.width) // 2
    # Visually centre the cat head slightly above geometric centre — the
    # ears push the visual mass up, so we nudge it down a touch to
    # compensate.
    oy = (CANVAS - fitted.height) // 2 + int(CANVAS * 0.02)
    out.paste(fitted, (ox, oy), fitted)
    return out


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Source art missing: {SRC}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    src = Image.open(SRC).convert("RGB")
    print(f"loaded {SRC.name}: {src.size}")

    main_icon = build_main_icon(src)
    main_path = OUT_DIR / "logo_rabochiy.png"
    main_icon.save(main_path, format="PNG", optimize=True)
    print(f"wrote {main_path} ({main_icon.size})")

    fg = build_adaptive_foreground(src)
    fg_path = OUT_DIR / "logo_rabochiy_foreground.png"
    fg.save(fg_path, format="PNG", optimize=True)
    print(f"wrote {fg_path} ({fg.size})")

    # Write a tiny manifest recording the BG colour the `pubspec.yaml`
    # `adaptive_icon_background` must match.
    print(f"adaptive_icon_background: #{BG_RGB[0]:02X}{BG_RGB[1]:02X}{BG_RGB[2]:02X}")


if __name__ == "__main__":
    main()
