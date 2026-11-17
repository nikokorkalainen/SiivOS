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

- **Font:** the system font only (SF Pro). No custom fonts in the app.
- **Layout:** the existing `NavigationSplitView` with a sidebar. Content is left aligned with a
  readable maximum width (about 860 to 960 pt) rather than a narrow centred column.
- **Accent colour:** add an `AccentColor` asset.
  - Light appearance: `#2F7A5F` (moss green).
  - Dark appearance: `#2F7A5F` for filled buttons and the selected sidebar row. Use `#9CCBB0`
    (lichen) for tinted icons, links and chart lines on dark backgrounds, where moss is too dark.
- **Light and dark mode:** both are required. Use system semantic colours (`.primary`,
  `.secondary`, `Color(nsColor: .windowBackgroundColor)` and so on) everywhere else so both
  modes work without extra code.
- **Sizes:** keep using `ByteCountFormatter`, so the user's region decides the decimal comma.

## Sidebar

Order: Overview, Cleanup, Apps, Performance, Protection, Health Timeline, History.
History shows the size waiting in the holding area as a small trailing label, only when it is
not empty. No other badges.

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

## Logo and app icon

- App icon: green gradient tile (`#1A9E73` top left to `#0B4A39` bottom right), two four-point
  white glints with equal arms, grouped and centred above the name "SiivOS" in Nunito
  ExtraBold, with "OS" in mint `#5EE6A8`.
- At 32 px and below the name drops out and the glints fill the tile.
- Icon files for the app (an `.icns` or asset catalog) still need exporting from the canvas.
