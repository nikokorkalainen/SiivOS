"""Exports the SiivOS app icon (glints only) at every macOS size, plus the logo tile with the name.

The glint shape and the lettering come from the master logo,
design/logo/SiivOS-logo-for-light-backgrounds.svg, so a change there carries over here.

Usage (from the repo root; needs rsvg-convert and Pillow):
    python3 design/icon/make_icon.py design/icon
"""
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "design" / "logo" / "SiivOS-logo-for-light-backgrounds.svg"
OUT = Path(sys.argv[1])

# The logo's letters, as (class, path data). st0 is "Siiv", st1 is "OS".
_paths = re.findall(r'<path class="(st\d)" d="([^"]+)"', LOGO.read_text())
LETTERS = _paths[:-2]           # the last two paths are the glints
S_HEIGHT, LEFT, RIGHT, BASE = 72.6, 74.73, 367.5, 127.3   # measured from the logo file


def glint(cx, cy, arm):
    """The SiivOS glint, as in the logo: control points at 12 % and 45.4 % of the arm."""
    k1, k2 = 0.12 * arm, 0.454 * arm
    return (
        f"M{cx} {cy - arm}"
        f"C{cx + k1} {cy - k2} {cx + k2} {cy - k1} {cx + arm} {cy}"
        f"C{cx + k2} {cy + k1} {cx + k1} {cy + k2} {cx} {cy + arm}"
        f"C{cx - k1} {cy + k2} {cx - k2} {cy + k1} {cx - arm} {cy}"
        f"C{cx - k2} {cy - k1} {cx - k1} {cy - k2} {cx} {cy - arm}Z"
    )


# 1024 x 1024 grid, tile 824 x 824 at (100, 100), the macOS icon template.
# Logo tile: the glints as one group, centred above the name.
F_BIG, F_SMALL = glint(560, 350, 145), glint(386, 450, 66)
# App icon: no name, the glints centred on the tile.
S_BIG, S_SMALL = glint(568, 484, 202), glint(346, 650, 92)


def name_group(cx: float, baseline: float, cap: float) -> str:
    """The name from the logo, centred on cx, sitting on baseline, with the S `cap` units tall."""
    scale = cap / S_HEIGHT
    tx = cx - (LEFT + RIGHT) / 2 * scale
    ty = baseline - BASE * scale
    colour = {"st0": "#FFFFFF", "st1": "#5EE6A8"}
    shapes = "".join(f'<path d="{d}" fill="{colour[c]}"/>' for c, d in LETTERS)
    return f'<g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})">{shapes}</g>'


def icon_svg(with_name: bool) -> str:
    if with_name:
        art = f'<path d="{F_BIG}" fill="#FFFFFF"/><path d="{F_SMALL}" fill="#5EE6A8"/>\n' + name_group(512, 768, 138)
    else:
        art = f'<path d="{S_BIG}" fill="#FFFFFF"/><path d="{S_SMALL}" fill="#5EE6A8"/>'
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1A9E73"/><stop offset="1" stop-color="#0B4A39"/></linearGradient>
<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%"><feGaussianBlur stdDeviation="10"/></filter>
<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>
</defs>
<rect x="100" y="112" width="824" height="824" rx="186" fill="#000000" opacity="0.28" filter="url(#shadow)"/>
<g clip-path="url(#tile)">
<rect x="100" y="100" width="824" height="824" fill="url(#bg)"/>
{art}
</g>
</svg>
"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon, tile = OUT / "AppIcon.svg", OUT / "LogoTile.svg"
    icon.write_text(icon_svg(False))
    tile.write_text(icon_svg(True))

    iconset = OUT / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    slots = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    rendered = {}
    for points, scale in slots:
        px = points * scale
        suffix = "" if scale == 1 else "@2x"
        target = iconset / f"icon_{points}x{points}{suffix}.png"
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-o", str(target), str(icon)], check=True)
        rendered[px] = target
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(OUT / "LogoTile.png"), str(tile)], check=True)

    images = {px: Image.open(path).convert("RGBA") for px, path in rendered.items()}
    images[1024].save(OUT / "AppIcon.icns", append_images=[images[px] for px in (16, 32, 64, 128, 256, 512)])
    print("wrote", sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()
