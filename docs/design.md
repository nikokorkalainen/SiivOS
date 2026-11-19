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

## Fixes from the first green build

Seen in the owner's screenshot of the Cleanup screen before scanning (18 November).

1. **The green must fill the whole content column.** `.background(SiivOSWindowBackground())` in
   `ContentView` only covers the size of the content, so a small screen such as an empty state
   shows a grey column with a small green box. Make the detail fill the column first:

       detail(for: selection ?? .overview)
           .frame(maxWidth: .infinity, maxHeight: .infinity)
           .background(SiivOSWindowBackground())

   and do not give individual screens or empty states their own background.

2. **The selected sidebar row must not be macOS blue.** A `List` selection is drawn in the accent
   colour chosen in System Settings, which the app cannot change. Draw the rows yourself: keep
   the same sections and badge, but use plain rows (for example a `ScrollView` with a `VStack`
   of buttons, or a `List` without a selection binding) and draw the selected row's background:
   - dark mode: white at 14 %, corner radius 8, icon in mint `#7EE0B4` with its white details,
     text in the primary colour;
   - light mode: moss `#2F7A5F`, corner radius 8, white icon and text.
   Keep keyboard use working: the rows are buttons, and `.onMoveCommand` moves the selection
   with the up and down arrow keys.

3. **Empty states are not boxes.** Replace `ContentUnavailableView` on the Cleanup screen with
   the layout on the canvas ("Cleanup before scanning"), centred in the content column on the
   green, with nothing behind it:
   - the Cleanup icon, `SiivOSIconView(.cleanup, size: 72)`;
   - the heading "Scan this Mac for clutter" (22 pt semibold);
   - the existing sentence about what SiivOS looks for, and "Scanning only looks. Nothing is
     removed until you tick items and confirm.", in secondary text, at most about 500 pt wide;
   - **Scan for Clutter** as the main button;
   - under a thin divider, two short columns: "Safe to remove" (App caches, Logs, Leftovers
     from removed apps) and "Check first" (Old downloads, Large files, Duplicate files);
   - last, in small secondary text, the note that macOS may ask for permission to look in the
     Desktop, Documents and Downloads folders.
   New texts need Finnish translations like the rest. `ComingSoonView` should follow the same
   open layout: the section's icon at 72 pt, its title and summary, no box.

4. **More room above the logo.** Add about 6 pt of top padding to `SiivOSSidebarHeader` so the
   logo does not sit tight under the window buttons.

## Sidebar

**Logo at the top:** `SiivOSSidebarHeader()`, the text logo (`SiivOSLogo`, 39 pt tall including the glints): the
name with the two glints off the top-left corner of the S, and no app icon. Put it above the
sections, for example with `.safeAreaInset(edge: .top)` on the sidebar `List`. It is drawn from
outlines, so it needs no font installed. Dark mode: soft white with mint "OS"; light mode: deep
green with jade "OS". The big glint takes the colour of "Siiv", the small one the colour of "OS".

Order: Overview, Cleanup, Apps, Performance, Protection, Health Timeline, History.
Icons in buttons (Check This Mac, Scan Again, Undo) are 20 pt; disclosure arrows 15 pt.
History shows the size waiting in the holding area as a small trailing label, only when it is
not empty. No other badges.
Sidebar icons are 30 pt (`SiivOSIconView`'s default size), with rows about 52 pt tall. In SwiftUI, set
`.environment(\.sidebarRowSize, .large)` on the sidebar `List` (macOS 14 and later); if that
does not give the larger look, use `.imageScale(.large)` on the row labels. The Overview's area
cards use matching icons: 34 pt for the Cleanup card, 30 pt for the others.

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

## Performance

Follows the existing `PerformanceView`; these are the design changes.

- Header: title, the line "A live look at what this Mac is doing. Looking changes nothing.", and
  **Open Activity Monitor** on the right.
- **What SiivOS notices:** each diagnosis is a panel with a 34 pt round icon (a check for good, an
  "i" for a note, both in the tint colour with a white mark), the title in semibold and the
  explanation in secondary text. The all-clear message uses the same panel.
- **Right now:** a grid of four panels (two across on a normal window, one on a narrow one),
  each with a plain title, a large number (32 pt semibold, tabular digits), one line of context
  in secondary text, then:
  - Processor: a sparkline, then "Busiest now" with the program, its known-program description
    under it, and its share on the right.
  - Memory: a sparkline, a three-step pressure meter (normal, tight, heavy) with the pressure
    sentence under it, then "Using the most".
  - Startup disk: a bar of used space, and when Cleanup has found something, "Cleanup found
    53,25 GB that is safe to remove." with an **Open Cleanup** button.
  - Battery: a charge bar, the charging or time-left sentence, health and charge cycles.
- Sparklines: the tint colour as a 2 pt line over a soft fade of the same colour, no axes.
- No icons in the panel titles; the sidebar already says where you are.

## Switching views (Apps and Background Items)

The standard segmented picker is thin and faint on the green, and it stretches across the window.
Use `SiivOSSegmentedControl` (`Sources/SiivOS/SiivOSSegmentedControl.swift`) instead:

- 40 pt tall overall: a track (white at 8 % in dark mode, white in light mode, thin outline,
  corner radius 11) holding segments 34 pt tall, at least 128 pt wide, 14 pt text.
- The selected segment is filled with the prominent colour: mint with dark text in dark mode,
  moss with white text in light mode, semibold. Others are medium weight in the primary colour.
- It hugs its content and sits on the left under the page title, not stretched full width.
- On the Apps screen: page title "Apps", one line of subtitle, then the control, then the content.
  Replace the `Picker` with `.pickerStyle(.segmented)` in `AppsView`. The same control suits any
  other place that switches between two or three views.

## Buttons

Every button in the app uses one of these, so no standard grey macOS buttons remain on the green.

| Style | Use for | Height | Corners | Text | Look |
|-------|---------|--------|---------|------|------|
| Main (`ProminentButton`) | the screen's main action: Check This Mac, Scan for Clutter, Remove Ticked Items…, Move to Holding Area | 36 pt | 8 pt | 14 pt semibold | mint with dark text (dark mode), moss with white text (light mode) |
| Standard (`SiivOSButtonStyle(.standard)`) | header and dialog buttons: Scan Again, Open Activity Monitor, Remove a File or Folder…, Cancel, Undo | 36 pt | 8 pt | 14 pt medium | soft panel (white at 9 %) with a thin outline |
| Small (`SiivOSButtonStyle(.small)`) | buttons in rows and cards: Review, Tick All, Put Back, Open Cleanup, Sort | 30 pt | 7 pt | 13 pt medium | same as standard |
| Red | Delete Permanently… (`destructive: true` on standard or small); the confirming Delete Permanently button is a filled red main button | as above | as above | red text | same panel |

- Make sure `ProminentButton` matches the table: 36 pt tall, 8 pt corners, 18 pt side padding.
- Replace `.buttonStyle(.bordered)` in `AppsView` and every plain `Button` that shows as a grey
  macOS button with `SiivOSButtonStyle`. Keep `.plain` only for rows that are not meant to look
  like buttons (sidebar rows, group headers, disclosure arrows).
- Icons inside buttons are 20 pt; text and icon 8 pt apart.

## Notice icons

The round icons on notices (Performance's "What SiivOS notices", and anywhere else a message
needs one) are in the icon set: `SiivOSIconView(.good)`, `.note` and `.attention`, 34 pt. Same
style as the section icons: gradient fill, thin outline, white mark (a check, an "i", an "!").
`.attention` is drawn in a calm amber instead of the tint. Use them instead of the SF Symbols in
`DiagnosisCard` (`checkmark.circle`, `info.circle`, `exclamationmark.circle`).

## Settings

Settings moves from its own standard window into the main window, with the green look like
everything else. Mockups: the "Settings, in the main window" row on the design canvas (dark and
light, with the full and the icons-only sidebar). The Swift for the icon and the controls is in
`design/swift-pending/`, waiting for a syntax check (see its README).

### Icon

`SiivOSIcon.settings`: an eight-tooth gear in the icon-set style, a gradient fill and thin
outline in the tint, with a white ring for the hole. It reads at 30 pt (sidebar), 34 pt
(icons-only sidebar) and all white on the moss selected row in light mode (`isSelected: true`).

### Place in the sidebar

- Pinned at the bottom, apart from the seven sections: a `ThemedDivider` inset 10 pt from both
  sides, then the Settings row, then the existing collapse button under it. The seven sections
  scroll if the window is short; the divider, Settings and the collapse button never scroll.
- The Settings row is a normal `SidebarRow` (same height, icon size, text and selection): white
  at 14 % in dark mode, moss with white icon and text in light mode. Setting it apart by place and
  the divider keeps one way of looking selected across the sidebar.
- Icons-only sidebar: the same order at the bottom: divider, the gear (34 pt, centred), the
  collapse button (centred) under it. The row's tooltip and VoiceOver label read "Settings".
- Command-comma selects it; the SiivOS menu's "Settings…" item does the same. The tooltip on the
  row can say "Settings (⌘,)". No trailing label on the row.
- Arrow keys: down from History goes to Settings, up from Settings goes to History.

### Layout: one scrolling page, not tabs

Settings is one page with a heading for each group, in this order: General, Cleanup,
Permissions, AI agents, Privacy. Reasons:

- There is little in each group. General, Permissions and AI agents hold one or two settings
  each, so as tabs most of the page would be empty, and the tab bar would be the busiest thing.
- Everything is visible at once. Full Disk Access changes what Cleanup can find, so it should
  not hide behind a tab you have to think of opening.
- It matches the other screens, which are scrolling pages. `SiivOSSegmentedControl` stays for
  switching between two big lists (Apps and Background Items).
- New settings slot in without a new tab: "Open SiivOS at login" goes in General; a "Holding
  area" group (empty it automatically after a chosen time, warn past a chosen size) and a
  "Health Timeline" group (how long history is kept) go after Cleanup, before Permissions.

Page: `PageHeader` with the title "Settings" and the subtitle "How SiivOS runs, and what Cleanup
lists." (Finnish suggestion: "Miten SiivOS toimii ja mitä Siivous näyttää."). Content left
aligned, at most 900 pt wide, 30 pt between groups. Each group: a 17 pt semibold heading, then
one or more panels (`Card`, the theme's panel colour, rows separated by `ThemedDivider`).
Inside Cleanup, "Checks to run" and "Folders to leave out" are 14 pt semibold sub-headings over
their own panels, and "Changes apply the next time you scan." is a note under the last panel.

### Controls

All rows use `SettingRow` (label and notes on the left, the control at the far end, 16 pt
side padding, 14 pt top and bottom). Labels and notes wrap and are never shortened, so Finnish
fits: in a narrow window the label takes two lines and the control stays on the right.

| Control | Look | Standard or themed |
|---------|------|--------------------|
| Switch | the Mac's standard switch (`Toggle` with `.toggleStyle(.switch)`, label hidden, title still read by VoiceOver), `.tint(SiivOSTheme.prominent)`: mint on in dark mode, moss in light; off is the system grey | **standard**: the tint carries the theme, and the system switch keeps its keyboard and VoiceOver behaviour |
| Choice (menu) | `SiivOSMenuPicker`: a small SiivOS button (30 pt, `SiivOSButtonStyle(.small)`) showing the current choice and up-down arrows; the menu shows a checkmark on the current one | **themed**: the standard pop-up button is a grey bezel that matches nothing else. If the menu ignores the button style on the Mac, use `.menuStyle(.borderlessButton)` and draw the label as the small button instead |
| Status row | `SettingStatus` at the far end: a small dot and "On" or "Off". On: dot in the tint. Off: dot in calm amber, never red | themed, small |
| List row with a button | in "Folders to leave out": a folder line icon (20 pt), the path shortened with ~ and cut in the middle (full path in the tooltip), "Include Again" as `SiivOSButtonStyle(.small)` at the far end; rows separated by dividers. Empty list: "No folders are left out." in secondary text (Finnish suggestion: "Yhtään kansiota ei ole jätetty pois."). "Add Folder…" (small) on its own row under the list. The panel grows with the list; the page scrolls, the panel does not | themed |
| Path row | `SettingPathField`: the path in 12 pt monospaced type on a slightly recessed field (black at 22 % in dark mode, 5 % in light), cut in the middle, selectable, full path in the tooltip; "Copy Path" (small) beside it, which reads "Copied" for a moment after a click (Finnish needed: "Kopioitu") | themed |
| Note | `SettingNoteText`: 13 pt (callout), secondary colour, at most 640 pt wide, 4 pt under what it explains | |
| Error line | `SettingErrorLine`: the attention icon (18 pt, amber) and "The setting could not be saved: …" in the primary colour, inside the panel directly under the setting it belongs to. Not a red banner | themed |

Buttons follow the "Buttons" section: "Open Full Disk Access Settings" is the main
(`ProminentButton`) action while Full Disk Access is off, and a standard button once it is on.

### Groups in detail

- **General:** "Show SiivOS in the menu bar" with its note. Room for "Open SiivOS at login" below.
- **Cleanup:** the two choices in one panel; "Checks to run" with seven switches in one panel, one
  row each, no notes; "Folders to leave out" with its note at the top of its panel, then the list
  and "Add Folder…"; then "Changes apply the next time you scan."
- **Permissions:** "Full Disk Access" with `SettingStatus`; under it the on or off note, then the
  button. The long off note is the most likely to grow in Finnish, which is why it sits under the
  row at full width rather than beside the status.
- **AI agents:** the switch with notes 1 and 2; then, in the same panel under a divider, the path
  row with notes 3 and 4. When the tool is not in this copy of the app, that part is replaced by
  the one note about Scripts/make-app.sh.

### Privacy

Keep it in Settings, as the last group, "Privacy", in its own panel with the Protection icon
(26 pt) beside the statement. It is not a setting, but Settings is where people look for what an
app does with their data, and placed straight after AI agents it answers the question that the
agent notes raise. It does not need to repeat anywhere else. Protection's download button can
keep its own short line about using the network.

### Wording

Settings only narrow what SiivOS lists. None of them makes it less careful, and nothing on the
page suggests otherwise: no "safe mode", no warnings on the switches, and the folder note keeps
saying that left-out folders are not touched.

## Disk Map

A redesign of `DiskMapView` after the first build (19 November). Mockups: "Disk Map" at the end of
each row on the design canvas, drawn with the owner's real home folder.

### What was wrong

- Every block is the same green at a different strength, so the map reads as one slab and the
  eye cannot tell a photo library from a cache.
- Small blocks with no labels at the bottom right are noise; long names are cut to "iMyfo…ackup".
- The folder name appears twice, and the list repeats the map with the same unreadable shades.

### Page

1. The **Clutter / Disk Map** switch stays where it is now: `SiivOSSegmentedControl` at the top
   of Cleanup, above the page header, on the left.
2. The page header as now: title **"Disk Map"**, subtitle "170,55 GB in your home folder" (or
   "89,1 GB in Library" when looking into a folder). On the right, "Measured today at 9.02" in
   secondary text and **Measure Again** as a standard button with the refresh icon.
3. The breadcrumb under the header (home icon, then each folder; every part but the last is a
   link back).
4. A legend of the kinds below (small rounded squares with their names), 13 pt.
5. The map, 380 pt tall, full content width.
6. One line of secondary text: "Click a folder to look inside. Apps and photo, video and music
   libraries count as one item and are never looked into." (the existing text, shortened).
7. The list in one panel.

### Colour by kind

Each block and list row is coloured by what the folder holds, worked out from its name and place,
so the map can be read at a glance. The same colours in dark and light mode:

| Kind | Which folders | Fill | Text on the block |
|------|---------------|------|-------------------|
| App data | `~/Library` and anything inside it | `#23775A` | white |
| Photos and media | Pictures, Movies, Music, and photo, video and music libraries | `#7FD0A8` | deep green `#062A20` |
| Your documents | Desktop, Documents, and folders inside them | `#5BA8C4` | deep green |
| Downloads | Downloads | `#D6B04F` | deep green |
| Developer files | folders named like developer tools: `node_modules`, `.npm`, `.gradle`, `.cargo`, `DerivedData`, names ending in `-studio` or `sdk`, and any folder starting with a dot | `#9A8FD8` | deep green |
| Other folders | everything else | `#8AA39A` | deep green |
| Smaller items | the existing "N smaller items" group | `#3D5049` | white |

Inside a folder, children inherit the parent's kind unless their own name says otherwise (for
example `node_modules` inside Documents is Developer files).

### Blocks

- Rounded 8 pt, 3 pt gaps.
- **Fill:** a soft gradient in the kind's colour, top-left light to bottom-right dark, with a
  faint white sheen in the top-left corner. Edges: a 1 pt white line along the top at 30 %, a
  1 pt black line along the bottom at 16 %, and a small shadow (black 22 %, radius 2, y 1).

  | Kind | Top left | Middle | Bottom right |
  |------|----------|--------|--------------|
  | App data | `#2F9474` | `#23775A` | `#175640` |
  | Photos and media | `#A0E3C1` | `#7FD0A8` | `#5FB48B` |
  | Your documents | `#80C3D9` | `#5BA8C4` | `#438EAA` |
  | Downloads | `#E8CA73` | `#D6B04F` | `#BB9538` |
  | Developer files | `#B5ACE6` | `#9A8FD8` | `#8073C3` |
  | Other folders | `#A6BBB3` | `#8AA39A` | `#718B82` |
  | Smaller items | `#4B6159` | `#3D5049` | `#30413A` |

  In SwiftUI: `LinearGradient(colors: [top, middle, bottom], startPoint: .topLeading, endPoint:
  .bottomTrailing)`, a `RadialGradient` of white 20 % to clear over it at `.topLeading` (end
  radius about 55 % of the block's longer side), then the edge lines as overlays.
- **Kind symbol:** a line drawing of the kind in the bottom-right corner, in the block's text
  colour at 16 % opacity, 2.4 pt stroke whatever its size. About a third of the block's shorter
  side (Library 132 pt, Pictures 72 pt, Downloads 40 pt), and left out under 28 pt. Symbols:
  App data `square.3.layers.3d`, Photos and media `photo`, Your documents `doc`, Downloads
  `arrow.down.to.line`, Developer files `chevron.left.forwardslash.chevron.right`, Other folders
  `folder` (SF Symbols, ultralight or light weight).
- **Label:** the name in 14 pt semibold and the size in 12 pt under it, top left with 10 to 12 pt
  padding. Only on blocks at least 92 pt wide and 46 pt tall; smaller blocks have no text, and the
  name and size show in the info line under the map. Long names end in "…" at the end, not the
  middle.
- **Library** (when it is a block on the home folder map, and Cleanup has scanned) also says,
  at the bottom of the block: "53,25 GB of it is app caches that Clutter can clear." with a small
  **Review in Clutter** button that switches to Clutter. Use the caches total from the last scan;
  leave the line out if there has been no scan.

### Hover

- **The block under the pointer** keeps full colour, brightens slightly (brightness +7 %), gets a
  2 pt white ring inside its edge (78 %) and a soft shadow (black 32 %, radius 22, y 8), and is
  drawn above its neighbours. Its kind symbol rises to 28 % opacity. Blocks that open show a
  small round chevron badge in the top-right corner (22 pt, white 24 %).
- **The other blocks** fade to 60 % opacity and lose a little colour (saturation 80 %), so the
  hovered one stands out.
- **Info line:** the hint under the map ("Click a folder to look inside…") is replaced while
  hovering by one line: the kind's colour square, the name in semibold, the kind, then at the
  right "89,1 GB, 52 % of your home folder" and "Click to look inside." (smaller items: "Click to
  list them."). This is where small blocks without labels get their name. The hint comes back
  when the pointer leaves the map.
- **Map and list are linked:** hovering a list row highlights its block the same way and shows
  its info line; hovering a block tints its list row (grey 12 %).
- All changes fade over 0.14 s with ease-out; with Reduce Motion on they switch at once.
- In SwiftUI: track `@State var hovered: DiskItem.ID?` with `.onHover` on each block and row, and
  drive opacity, the ring and the info line from it. Use `.onContinuousHover` only if blocks are
  drawn in one `Canvas`.

### List

One row per block, in the same order: the kind's colour square, the name (with a chevron if it
can be opened) and the kind under it in 12 pt secondary text, a bar in the kind's colour, the
percentage and the size, both right aligned with tabular digits. The smaller-items row reads
"Folders under 1 GB, shown together" instead of a kind. Rows keep "Show in Finder" in their
context menu.

### New texts (Finnish needed)

"%1$@ in your home folder" · "Measured today
at %1$@" · the six kind names · "%1$@ of it is app caches that Clutter can clear." · "Review in
Clutter" · "Folders under 1 GB, shown together" · "%1$@, %2$@ of your home folder" ·
"Click to look inside." · "Click to list them."

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
   `SiivOSIconView(section.icon, size: 34)` for Cleanup and `size: 30` for the others.
4. Keep SF Symbols for small controls (Scan Again, Undo, chevrons).

## Loading

- Use `GlintLoader` (in `Sources/SiivOS/GlintLoader.swift`) wherever the app shows a
  `ProgressView` spinner: the Cleanup and Apps scans, and "Checking now…" on the Overview.
- Layout: the glints (96 pt) centred in the content area, with the progress text under them in
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
- Master logo: `design/logo/SiivOS-logo-for-light-backgrounds.svg`, drawn by the owner. Everything
  else follows it: the app's `SiivOSLogo` is generated from it, and the glint shape (four points
  joined by soft curves, control points at 12 % and 45.4 % of the arm) is used in every glint:
  the app icon, the section icons and the loading animation.
- Text logo: the name with the two glints off the top-left corner of the S, no tile. Used in the
  app's interface and anywhere a plain logo fits (README, website). Files in `design/logo/`, one
  for dark backgrounds and one for light.
- Logo tile: the same tile with the glints above the name "SiivOS" in Nunito ExtraBold, "OS" in
  mint. For GitHub, social posts and the website only.
- Files: `Resources/AppIcon.icns` is what the app uses; `Scripts/make-app.sh` copies it into
  the bundle. Master artwork, every size and the logo tile are in `design/icon/` (see its
  README).
