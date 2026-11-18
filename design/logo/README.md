# Text logo

The name "SiivOS" with the two glints off the top-left corner of the S, drawn by the owner.
`SiivOS-logo-for-light-backgrounds.svg` is the master file: everything else follows it.

- `SiivOS-logo-for-light-backgrounds`: deep green `#0B3D30`, with jade `#178A64` for "OS" and the
  small glint. This is the owner's file as exported from Illustrator.
- `SiivOS-logo-for-dark-backgrounds`: the same file recoloured, soft white `#F1F7F3` with mint
  `#5EE6A8`.

Each comes as SVG (any size) and PNG (1200 px wide).

After changing the master file:

```
python3 design/icon/make_wordmark.py      # the app's sidebar logo (SiivOSWordmark.swift)
python3 design/icon/make_icon.py design/icon && mv design/icon/AppIcon.icns Resources/AppIcon.icns
```

and make the dark version again by swapping the two colours.
