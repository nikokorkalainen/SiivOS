# App icon and logo tile

- `AppIcon.svg`: the app icon, two glints on the green tile. Used at every size, in the Dock,
  Finder and Launchpad.
- `AppIcon.iconset/`: every size macOS uses, named the way `iconutil` expects.
- `../../Resources/AppIcon.icns`: the file the app bundle uses.
- `LogoTile.svg` and `LogoTile.png`: the same tile with the name under the glints. For GitHub,
  social posts and the website, not for the app.

The name is drawn as outlines from Nunito ExtraBold, so the tile does not need the font
installed. Nunito is by The Nunito Project Authors and licensed under the SIL Open Font License
1.1 (https://github.com/googlefonts/nunito).

## Making the files again

On Linux (needs `rsvg-convert`, Python with fontTools and Pillow, and the Nunito variable font):

```
python3 design/icon/make_icon.py path/to/Nunito[wght].ttf design/icon
mv design/icon/AppIcon.icns Resources/AppIcon.icns
```

On a Mac, the `.icns` can also be rebuilt from the iconset:

```
iconutil -c icns design/icon/AppIcon.iconset -o Resources/AppIcon.icns
```
