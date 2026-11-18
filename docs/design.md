# SiivOS design notes

How the SiivOS screens should look and behave. The mockups live on the design canvas
(https://claude.ai/artifact/2a5tzTxcchuRNBeaJGTxFt), which only the owner can open; this file is
the written version so the app code can follow it. Written against the code on the branch
`claude/intelligent-clarke-msqlh7` (phases 2 and 3).

## Principles

- **Calm.** No red scare warnings, no alarming counts, no "speed up your Mac" claims.
- **Look before removing.** Nothing is removed in one click. Every removal goes through the
  "Before anything changes" sheet. There is no "remove everything" button anywhere.
- **Your own files are special.** Anything the user created (downloads, large files,
  duplicates) is shown apart from app clutter and is ticked one item at a time.
- **Plain words.** Sentence case for text, Title Case only for button and menu labels,
  following macOS. No dashes as punctuation.

## Look

The main design is the **green look** in dark mode, with a standard light mode alongside it.
The app follows the Mac's appearance setting. Colours and backgrounds are in
`Sources/SiivOS/SiivOSTheme.swift`.

- **Font:** the system font only (SF Pro). No custom fonts in the app.
- **Layout:** the existing `NavigationSplitView` with a sidebar. Content is left aligned with a
  readable maximum width (about 860 to 960 pt) rather than a narrow centred column.
- **Dark mode, the green look:**
  - Window: `SiivOSWindowBackground()`, a soft diagonal gradient (`#13563F` top left,
    `#0B3A2E`, `#072519` bottom right), behind the detail column. Use
    `.scrollContentBackground(.hidden)` on lists and forms so the gradient shows through.
  - Sidebar: `SiivOSSidebarBackground()` behind the sidebar `List`, also with
    `.scrollContentBackground(.hidden)`. Deep green with a hint of the gradient.
  - Panels and dividers: `SiivOSTheme.panel` (white at 6 %) and `SiivOSTheme.divider` (white
    at 9 %), so they sit on the green instead of looking like grey boxes.
  - Text: the system primary and secondary colours. They read well on the green as they are.
  - Prominent buttons: `.buttonStyle(.borderedProminent)` with `.tint(SiivOSTheme.prominent)`,
    which is mint. Mint needs dark text: if the label stays white, add
    `.foregroundStyle(SiivOSTheme.onProminent)` to the label.
  - Icons: the SiivOS icon set in mint `#7EE0B4`, with white details.
- **Light mode:** standard macOS window and sidebar, moss `#2F7A5F` for prominent buttons with
  white text, moss icons with jade details.
- **Accent colour:** add an `AccentColor` asset of moss `#2F7A5F` in both appearances. macOS uses
  it for the selected sidebar row, checkboxes and focus rings. (The canvas shows the selected row
  as a soft white highlight in dark mode; that needs a custom sidebar, so moss is fine for now.)
- **Sizes:** keep using `ByteCountFormatter`, so the user's region decides the decimal comma.

## Sidebar

**Logo at the top:** `SiivOSSidebarHeader()` (app icon 32 pt next to the name, 16 pt tall),
above the sections, for example with `.safeAreaInset(edge: .top)` on the sidebar `List`. The
name is drawn from outlines (`SiivOSWordmark`), so it needs no font installed. In dark mode it is
soft white with mint "OS"; in light mode deep green with jade "OS".

Order: Overview, Cleanup, Apps, Performance, Protection, Health Timeline, History.
History shows the size waiting in the holding area as a small trailing label, only when it is
not empty. No other badges.
Sidebar icons are 30 pt (`SiivOSIconView`'s default size), with rows about 52 pt tall. In SwiftUI, set
`.environment(\.sidebarRowSize, .large)` on the sidebar `List` (macOS 14 and later); if that
does not give the larger look, use `.imageScale(.large)` on the row labels. The Overview's area
cards use matching icons: 24 pt for the Cleanup card, 22 pt for the others.

## Overview

1. Title "Overview", with "Last checked today at 22.20" (relative date) under it.
2. A prominent **Check This Mac** button (the window's main action) that runs every scanner.
3. One sentence with real numbers: "93 GB free of 494 GB".
4. A disk bar with three parts: used, safe to remove, free, plus a small legend.
   "Safe to remove" is the total of the Safe to remove scanners from the last check.
5. **What the check found:** one card per area.
   - Cleanup card: the Safe to remove total in large type, a line about the user's own files
     to look through, and a **Review** button that opens Cleanup. No Remove button.
   - Apps, Performance and Protection: quiet cards reading "Coming in a later update" until
     those phases exist.
6. Free space over time (later, with the Health Timeline phase).

## Cleanup

### Two parts

Group the existing scanners by their `id`:

| Part | Heading line | Scanner ids |
|------|--------------|-------------|
| **Safe to remove** | "Files apps and macOS make for themselves. Removing them does not touch your documents." | `caches`, `logs`, `leftovers` |
| **Check first** | "These are your own files. Look at each one before you tick it." | `old-downloads`, `large-files`, `duplicates` |

### Groups

- Each scanner is a collapsible group: disclosure arrow, title, total size.
- **Tick All / Untick All** appears in the group header **only for Safe to remove groups**.
  Check first groups have no Tick All.
- When open, the scanner's `summary` shows once under the header, then the rows.
  The Check first summaries can drop "These are your own files, so check each one" because the
  part heading already says it.
- The "Showing the 100 largest of N items" note stays.

### Rows

- One line per finding: checkbox, a readable name, size on the right.
- **Readable names:** for folders named like bundle identifiers (`com.spotify.client`), show
  the app's name when it can be found (`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
  and the bundle's display name), otherwise the folder name.
- Drop the repeated "Cached data for X." line and the parent folder line. Show the full path as
  a tooltip (`.help(finding.url.path)`) and keep the "Show in Finder" context menu.
- Keep `finding.explanation` where it says something specific (old downloads, large files,
  duplicates, leftovers), as a second line in secondary text.

### Header and action bar

- Header: title "Cleanup", the line "Tick what you want to remove. Nothing changes until you
  confirm.", and **Scan Again** on the right.
- Remove the top Form section ("Ticked: Nothing" and the buttons).
- A bar pinned to the bottom of the window (`.safeAreaInset(edge: .bottom)`):
  - Left: "Nothing ticked" or "2 items ticked, 44,59 GB", with the line "Removed items wait in
    the holding area. You can put them back from History."
  - Right: **Remove Ticked Items…** as the prominent button, disabled when nothing is ticked.

### After removing

Show a banner at the top of the list: "Moved 2 items (44,59 GB) to the holding area. Delete
them permanently in History to free the space." with an **Undo** button that puts them back.

## Before anything changes (sheet)

Keep the existing `RemovalPlanSheet`, with shorter copy:

> SiivOS will move 2 items (44,59 GB) to the holding area. Nothing is deleted yet. The space is
> freed when you delete them permanently in History.

List rows show the readable name and size, with the path as a tooltip. Keep "Will be left
alone" with its reasons. Buttons: Cancel, **Move to Holding Area** (default).

## History

- Title "History", with one line: "44,59 GB is waiting in the holding area. Put items back, or
  delete them permanently to free the space." or "The holding area is empty."
- **Remove a File or Folder…** button on the right of the title.
- Changes in one grouped list. Each row: disclosure arrow, title, and one line with date, size
  and what was removed (no " · " separators).
  - Held: **Put Back** and **Delete Permanently…** (red text).
  - Put back or deleted: a short status in secondary text, no buttons.
  - Details: the original paths.
- Keep the existing "Delete permanently?" confirmation and its wording.

## Copy to correct

- Items never expire from the holding area. Do not mention 30 days anywhere.
- Moving to the holding area does not free space. Every place that talks about freeing space
  must say it happens when items are deleted permanently in History.

## Icons

Use the SiivOS icon set (`Sources/SiivOS/SiivOSIcons.swift`) instead of SF Symbols for the
seven sections: Overview, Cleanup, Apps, Performance, Protection, Health Timeline and History.
Each icon is a soft gradient fill, a thin outline and one white detail (a glint, the gauge
needle, the check mark, the chart's end dot or the clock hands). In light mode the outline is
moss and the detail is jade. The icons are drawn in code, so there are no image files.

How to wire them in:

1. In `AppSection`, add `var icon: SiivOSIcon` that returns the case with the same name
   (`.overview` returns `.overview`, `.timeline` returns `.timeline`, and so on).
2. In the sidebar (`ContentView`), replace `Label(section.title, systemImage: section.symbol)`
   with a label whose icon is `SiivOSIconView(section.icon, isSelected: selection == section)`.
   `isSelected` turns the whole icon white on the selected row.
3. On the Overview's area cards, replace `Image(systemName: section.symbol)` with
   `SiivOSIconView(section.icon, size: 24)` for Cleanup and `size: 22` for the others.
4. Keep SF Symbols for small controls (Scan Again, Undo, chevrons).

## Loading

- Use `GlintLoader` (in `Sources/SiivOS/GlintLoader.swift`) wherever the app shows a
  `ProgressView` spinner: the Cleanup and Apps scans, and "Checking now…" on the Overview.
- Layout: the glints (72 pt) centred in the content area, with the progress text under them in
  secondary text, 18 pt apart. Keep the existing wording ("Checking: %@…", "Getting ready…").
- Motion: the two glints take turns to twinkle, each growing, brightening and making a quarter
  turn every 1.6 seconds. With Reduce Motion on, they stay still and only fade.
- Colours: in dark mode the big glint is near-white and the small one mint `#5EE6A8`, like the
  icon. In light mode they are deep green `#145C47` and jade `#1A9E73`.
- For a small inline spot (a button or a row), `GlintLoader(size: 20)` works, but the standard
  small `ProgressView` is fine there too.

## Logo and app icon

- App icon: green gradient tile (`#1A9E73` top left to `#0B4A39` bottom right) with two
  four-point glints with equal arms, the big one white and the small one mint `#5EE6A8`,
  centred as a group. No name in the icon, at any size: the Dock shows the name on hover.
- Logo tile: the same tile with the glints above the name "SiivOS" in Nunito ExtraBold, "OS" in
  mint. For GitHub, social posts and the website only.
- Files: `Resources/AppIcon.icns` is what the app uses; `Scripts/make-app.sh` copies it into
  the bundle. Master artwork, every size and the logo tile are in `design/icon/` (see its
  README).
