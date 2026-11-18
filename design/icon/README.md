# App icon and logo tile

- `AppIcon.svg`: the app icon, two glints on the green tile. Used at every size, in the Dock,
  Finder and Launchpad.
- `AppIcon.iconset/`: every size macOS uses, named the way `iconutil` expects.
- `../../Resources/AppIcon.icns`: the file the app bundle uses.
- `LogoTile.svg` and `LogoTile.png`: the same tile with the name under the glints. For GitHub,
  social posts and the website, not for the app.

The glint shape and the name on the logo tile come from the master logo in `design/logo/`.

- `make_wordmark.py`: writes `Sources/SiivOS/SiivOSWordmark.swift`, the logo as SwiftUI shapes.

## Making the files again

From the repo root (needs `rsvg-convert` and Python with Pillow and fontTools):

```
python3 design/icon/make_icon.py design/icon
mv design/icon/AppIcon.icns Resources/AppIcon.icns
python3 design/icon/make_wordmark.py
```

On a Mac, the `.icns` can also be rebuilt from the iconset:

```
iconutil -c icns design/icon/AppIcon.iconset -o Resources/AppIcon.icns
```
