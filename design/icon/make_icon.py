"""Exports the SiivOS app icon (glints only) at every macOS size, plus the logo tile with the name.

The name is converted to outlines from Nunito ExtraBold (SIL Open Font License), so the
icon does not depend on the font being installed.

Usage: python3 -I make_icon.py <nunito-variable.ttf> <output-dir>
"""
import subprocess
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image


def glint(cx, cy, arm, pinch):
    """A four-point glint with equal arms and concave sides."""
    p = pinch
    return (
        f"M {cx} {cy - arm} Q {cx + p} {cy - p} {cx + arm} {cy} "
        f"Q {cx + p} {cy + p} {cx} {cy + arm} Q {cx - p} {cy + p} {cx - arm} {cy} "
        f"Q {cx - p} {cy - p} {cx} {cy - arm} Z"
    )


# 1024 x 1024 grid, tile 824 x 824 at (100, 100), the macOS icon template.
# Logo tile: the glints as one group, centred above the name.
F_BIG, F_SMALL = glint(560, 350, 145, 25), glint(386, 450, 66, 11)
# App icon: no name, the glints centred on the tile.
S_BIG, S_SMALL = glint(568, 484, 202, 32), glint(346, 650, 92, 14)

FONT_PATH, OUT = Path(sys.argv[1]), Path(sys.argv[2])
WHITE, MINT = "#FFFFFF", "#5EE6A8"
SIZE, BASELINE, CENTER_X = 196, 768, 512


def word_paths() -> str:
    font = instantiateVariableFont(TTFont(FONT_PATH), {"wght": 800})
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = SIZE / font["head"].unitsPerEm

    # Lay the letters out on the advance widths and measure the ink.
    letters, x = [], 0
    for ch in "SiivOS":
        name = cmap[ord(ch)]
        letters.append((ch, name, x))
        x += font["hmtx"][name][0]
    bounds = BoundsPen(glyph_set)
    for _, name, gx in letters:
        glyph_set[name].draw(TransformPen(bounds, (1, 0, 0, 1, gx, 0)))
    x_min, _, x_max, _ = bounds.bounds
    shift = CENTER_X - (x_min + x_max) / 2 * scale

    parts = []
    for i, (ch, name, gx) in enumerate(letters):
        pen = SVGPathPen(glyph_set)
        # Font units are y-up; flip into SVG space and sit on the baseline.
        glyph_set[name].draw(TransformPen(pen, (scale, 0, 0, -scale, shift + gx * scale, BASELINE)))
        colour = MINT if i >= 4 else WHITE  # "OS" in mint
        parts.append(f'<path d="{pen.getCommands()}" fill="{colour}"/>')
    return "\n".join(parts)


def icon_svg(small: bool, words: str) -> str:
    if small:
        art = f'<path d="{S_BIG}" fill="#FFFFFF"/><path d="{S_SMALL}" fill="#5EE6A8"/>'
    else:
        art = f'<path d="{F_BIG}" fill="#FFFFFF"/><path d="{F_SMALL}" fill="#5EE6A8"/>\n{words}'
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
    words = word_paths()
    # The app icon is the glints only, at every size. The version with the name is the
    # square logo tile for GitHub and social, not used by the app.
    icon, tile = OUT / "AppIcon.svg", OUT / "LogoTile.svg"
    icon.write_text(icon_svg(True, words))
    tile.write_text(icon_svg(False, words))
    old_small = OUT / "AppIcon-small.svg"
    if old_small.exists():
        old_small.unlink()

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
