# Screenshots

Pictures of SiivOS for the main README. They are taken on a real Mac, so look at each one
before adding it: nothing in it should be something you would not show a stranger, such as
file names, folder names or the names of apps you would rather keep to yourself. The Disk
Map shows the name of your home folder in three places: its subtitle, the line of folders
under it, and the sentence about what has grown.

All in dark mode, with the window at its normal size:

| File | What it shows |
|------|---------------|
| `overview.webp` | The Overview after Check This Mac has run |
| `cleanup.webp` | Cleanup, Clutter, with results and their labels |
| `disk-map.webp` | Cleanup, Disk Map, showing the home folder |
| `health-timeline.webp` | The Health Timeline with its score and charts |
| `welcome.webp` | The first step of the welcome, after the logo has finished drawing |

## Taking one again

1. Press Command-Shift-4, then Space, then click the SiivOS window. The picture is saved
   on the Desktop, with a wide shadow around the window.
2. From the project folder, cut the shadow off and shrink it (needs Python with Pillow):

   ```
   python3 Scripts/trim-screenshots.py overview="path/to/the screenshot.png"
   ```

   The name before the equals sign is the file it replaces here.
