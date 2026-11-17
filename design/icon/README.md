# App icon

- `AppIcon.svg`: master artwork with the name, used for 128 pt and up.
- `AppIcon-small.svg`: glints only, used for the 16 pt and 32 pt slots, where the name would blur.
- `AppIcon.iconset/`: every size macOS uses, named the way `iconutil` expects.
- `../../Resources/AppIcon.icns`: the file the app bundle uses.

The name is drawn as outlines from Nunito ExtraBold, so the icon does not need the font
installed. Nunito is by The Nunito Project Authors and licensed under the SIL Open Font License
1.1 (https://github.com/googlefonts/nunito).

## Making the files again

On Linux (needs `rsvg-convert`, Python with fontTools and Pillow, and the Nunito variable font):

```
python3 design/icon/make_icon.py path/to/Nunito[wght].ttf design/icon
cp design/icon/AppIcon.icns Resources/AppIcon.icns
```

On a Mac, the `.icns` can also be rebuilt from the iconset:

```
iconutil -c icns design/icon/AppIcon.iconset -o Resources/AppIcon.icns
```
