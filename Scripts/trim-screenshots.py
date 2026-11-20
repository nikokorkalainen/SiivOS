#!/usr/bin/env python3
"""Gets window screenshots ready for the README.

A screenshot taken with Command-Shift-4, Space and a click comes with a wide shadow
around the window and is about a megabyte. This cuts the shadow off, leaving the window
with its rounded corners on a clear background, and saves it as a WebP file of well
under a hundred kilobytes, into docs/screenshots.

Usage, from the project folder (needs Python with Pillow):

    python3 Scripts/trim-screenshots.py overview="path/to/Screenshot 1.png" cleanup="path/to/Screenshot 2.png"

Each argument is the name the picture gets, an equals sign, and the screenshot. Look at
every picture before adding it: the repository is public, and a screenshot shows a real Mac.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "docs" / "screenshots"


def trim(source: Path) -> Image.Image:
    picture = Image.open(source).convert("RGBA")
    # The window is the part that is fully opaque; the shadow around it is see-through.
    box = picture.getchannel("A").point(lambda value: 255 if value == 255 else 0).getbbox()
    if box is None:
        raise SystemExit(f"{source}: no window found. Was it taken by clicking a window?")
    window = picture.crop(box)
    width, height = window.size

    # How far in the top row becomes opaque is about the radius of the window's corners.
    top = [window.getchannel("A").getpixel((x, 0)) for x in range(min(60, width))]
    radius = next((x for x, value in enumerate(top) if value == 255), 0) + 1

    # A rounded mask, drawn large and scaled down so that the corners come out smooth.
    scale = 4
    mask = Image.new("L", (width * scale, height * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width * scale - 1, height * scale - 1), radius=radius * scale, fill=255
    )
    mask = mask.resize((width, height), Image.LANCZOS)

    red, green, blue, _ = window.split()
    return Image.merge("RGBA", (red, green, blue, mask))


def main() -> None:
    pairs = [argument.split("=", 1) for argument in sys.argv[1:] if "=" in argument]
    if not pairs or len(pairs) != len(sys.argv) - 1:
        raise SystemExit(__doc__)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, source in pairs:
        target = OUT / f"{name}.webp"
        result = trim(Path(source))
        result.save(target, quality=92, method=6)
        print(f"{target.relative_to(OUT.parents[1])}: {result.width} x {result.height}, {target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
