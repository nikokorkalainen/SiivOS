# SiivOS production plan

Approved 17 November 2026.

## What we're building

A native Mac app (Swift + SwiftUI) that cleans up clutter, manages and uninstalls apps, shows what is slowing the Mac down, and checks for malware and adware.

- **Goal:** personal use first; open-source release later if it turns out good enough.
- **Platform:** macOS 14 or newer.

## Principles

These are what should make SiivOS stand out, and every feature is held to them.

1. **Explain and undo.** Every change is explained in plain words before it runs, and can be reversed.
2. **Privacy first.** Everything runs on the Mac. No telemetry, no ads, no scare tactics.
3. **Honest.** No "RAM booster" style features that don't help. On macOS the real gains come from freeing disk space and taming background items.
4. **Health timeline.** A health score with local history, showing what changed and when.

## How SiivOS stands out

Looked at on 17 November 2026, from the products' own websites: CleanMyMac (paid, closed source, the broadest feature set), CCleaner for Mac (free and paid, looks behind on macOS support) and Purge (free, open source, storage cleanup only, files go to the Trash first).

Purge already covers "open, private, honest, reversible" for storage cleanup, so those principles alone do not set SiivOS apart. What does:

1. **Undo with a history.** Every change is recorded with the explanation that was shown, and a whole change, such as an uninstall, can be put back in one click. Purge relies on the Trash and CleanMyMac deletes; neither keeps a readable record of what was done and why.
2. **The health timeline.** Answering "what changed on my Mac, and when?": new background items, apps added or removed, what grew. None of the three does this.
3. **Diagnosis instead of boosting.** Explaining why the Mac is slow right now, in plain words, with no "free up memory" buttons.
4. **Breadth with a trust model.** Cleanup, apps, performance and protection in one app, all local and reversible. Purge is trustworthy but narrow; CleanMyMac is broad but paid and closed.

## Phases

| # | Phase | What it delivers | Status |
|---|-------|------------------|--------|
| 1 | Setup | Build tools installed, project skeleton, this plan in the repo | Done. Built and run on macOS 15.8.3. The engine's tests first ran on the Mac on 18 November 2026, once Xcode was installed, and all passed |
| 2 | Safety core | Scan engine, action log, undo. Removed items go to a restorable holding area, not straight to deletion | Done. Built and tried out on macOS 15.8.3 |
| 3 | Clutter cleanup | Caches, logs, old downloads, large and duplicate files, leftovers from removed apps | Done. Built and tried out on macOS 15.8.3 |
| 4 | App manager | All apps with size and last use, full uninstall including leftovers, login items and background agents | Done. Built and tried out on macOS 15.8.3. Login items are not listed, only linked to in System Settings (see Known constraints) |
| 5 | Performance | Live view of processor, memory, disk and battery use, with plain-language diagnoses from built-in rules | Done. Built and tried out on macOS 15.8.3 |
| 6 | Protection | ClamAV for malware, plus own checks for adware, suspicious background agents, browser extensions and configuration profiles | Done. Built and tried out on macOS 15.8.3, including a real ClamAV 1.5.4: definitions downloaded and Downloads scanned |
| 7 | Health timeline | Health score with local history | Done. Built and tried out on macOS 15.8.3, with all 144 engine tests passing there. A score out of 100 that shows its reasons, a reading when the app opens (at most every six hours) kept in `health-history.json`, charts of the score and free space over time, and a list of what has changed: apps, background items, browser extensions, profiles, macOS's protections, free space, and SiivOS's own changes |
| 8 | Polish | Menu bar widget, tests, README and licence, ready for an open-source release | Built, waiting for the owner to build and try it on the Mac. Menu bar icon with a panel (health score, disk, memory, processor, new changes worth a look), a Settings window with the switch for it and a privacy statement, tests for the safety paths that had none, a README written for the public, and the licence: GNU General Public License version 3 or later, chosen by the owner on 18 November 2026. Running the tests automatically on GitHub was offered and left for when the repository goes public, where it is free |
| 9 | AI assistant (later) | Added once the rules-based diagnoses work | Not started |

## Planned additions

Ideas taken from the comparison above and from the owner. Each is built as part of the phase it belongs to, or as a follow-up to a finished phase.

| Idea | Inspired by | Belongs to | Status |
|------|-------------|------------|--------|
| Never-touch list: Cleanup never lists data of macOS, password managers and sign-in, iCloud and other syncing, or security and device-management software. Passwords, mail and messages cannot be removed at all | Purge | Phase 3 | Done. Built and tried out on macOS 15.8.3 |
| Hold back caches and logs of apps that are open, and count an open app as installed wherever it is kept | Purge | Phase 3 | Done. Built and tried out on macOS 15.8.3 |
| "Safe to clean" or "Check first" label on every item | Purge | Phase 3 follow-up | Not started |
| Developer clutter: Xcode data, Homebrew, npm and Docker caches | Purge | Phase 3 follow-up | Not started |
| Count copies that share disk space once, so sizes are honest | Purge | Phase 3 follow-up | Not started |
| Visual map of the largest folders on the disk | CleanMyMac | Phase 3 follow-up | Not started |
| App permissions overview: which apps can use the camera, microphone and files | CleanMyMac | Phase 6 | Done with Phase 6. It needs Full Disk Access to show anything |
| Notice and record new background items when they appear | SiivOS's own | Phase 7, where the history of readings is built | Done with Phase 7. SiivOS notices them when it takes a reading, not at the moment they appear; a notification while the app is closed would need the menu bar widget of Phase 8 |
| Green look, SiivOS icon set, sidebar logo and the app-drawn sidebar from `docs/design.md` | Owner's design notes | All screens | Done. Built and tried out on macOS 15.8.3 in dark and light mode |
| Sidebar cannot be hidden; its own button collapses it to slightly larger icons only. The app lays out the sidebar and content itself, without the standard split view, and the window has no title bar strip. Collapsing is animated, and the collapsed sidebar shows the two glints in place of the logo | Owner | Sidebar and window | Done. Built and tried out on macOS 15.8.3 |
| The window remembers its size and place when it is closed and opened again, and between launches. It opens at 1200 by 800 the first time, wide enough for three Overview cards in a row | Owner | Window | The default size works on the Mac. Remembering did not work at first and was rebuilt: only changes made after the window has settled are remembered, a new window is asked to open in the remembered size, and the place is corrected a moment after it appears. Waiting for the owner to try it |
| Settings window (see below) | Owner | Phase 8, or earlier where a phase needs a setting | Started with Phase 8: the menu bar switch and the privacy statement. The other proposed settings are not yet agreed |
| Finnish language version. The app follows the Mac's language, with English as the fallback | Owner | Its own step after Phase 4, then kept up to date in every later phase | Done. Built and tried out on macOS 15.8.3. The owner chose "sovellus", "terveys" and "Terveystiedot" |
| Screens redesigned to follow `docs/design.md`: Overview with Check This Mac and a three-part disk bar, Cleanup in two parts with a bottom action bar and Undo, History as one list, app icon | Owner's design notes | Overview, Cleanup, History, sidebar and the confirmation sheet | Done. Built and tried out on macOS 15.8.3, including the glint loading animation |

Decided against: cleaning cloud storage and updating other apps (both need network access, against the privacy principle), clearing browser history, and finding blurry or similar photos (little benefit for the effort).

### Proposed settings

Kept short on purpose. A setting is only added when people would reasonably want different behaviour.

- **Cleanup:** how old a download must be to count as old, how big a file must be to count as large, which checks to run, and folders to leave out of every scan.
- **Holding area:** delete held items automatically after a chosen time (off unless turned on), and warn when the holding area grows past a chosen size.
- **Permissions:** whether SiivOS has Full Disk Access and App Management, with buttons that open the right page in System Settings.
- **Privacy:** a plain statement of what SiivOS does and does not send anywhere. Anything that would use the network, such as malware definition updates in Phase 6, is listed here and is off until turned on.
- **Menu bar (built in Phase 8):** show SiivOS in the menu bar, on unless turned off. With it on, closing the window leaves SiivOS running there.
- **Still open:** how long the health timeline keeps its history (it now keeps the last 2,000 readings and 1,000 changes), and opening at login.

## How we work

- Claude writes the code and commits it to this repository. Claude's workspace cannot compile the Mac app, but it can compile the engine and run its tests (`Scripts/check-engine-on-linux.sh`).
- At the end of each phase, Niko builds and runs the app from Xcode, runs `swift test`, and reports what works and what breaks. `bash Scripts/make-app.sh` builds the double-clickable app.
- Problems are fixed before the next phase starts.

## Known constraints

- The app will need **Full Disk Access** to do its job, so it cannot be distributed through the Mac App Store. It will be distributed directly.
- A public release needs a paid Apple Developer account for signing and notarisation. Personal use does not.
- The accent colour from `docs/design.md` is an asset (`Resources/Assets.xcassets`) that `Scripts/make-app.sh` compiles with Xcode's asset tool. On a Mac without Xcode the script skips it and the app uses the Mac's own accent colour. It also does not apply when the app is run straight from Xcode, because that run has no app bundle.
- ClamAV (decided by the owner on 18 November 2026): SiivOS uses a ClamAV that the user installs themselves, for example with Homebrew, and bundles no part of it. Virus definitions are kept in SiivOS's own folder and downloaded from database.clamav.net only when the user clicks the button for it. That download is the only network use in SiivOS. Bundling was looked at again in Phase 8, and Claude's recommendation is to keep it this way: ClamAV is under the GPL version 2, which would tie SiivOS's own licence to it; it would add ClamAV's programs and libraries to every copy of the app; and SiivOS would become responsible for shipping ClamAV's security updates. The owner has the last word.
- macOS gives apps no supported way to list the "Open at Login" items in System Settings. SiivOS lists background items from the LaunchAgents and LaunchDaemons folders, and opens System Settings for the rest.
- Removing background items and apps that belong to all users needs administrator rights, which SiivOS does not ask for yet. It shows those items and leaves them alone.

## Project layout

- `Sources/SiivOSCore/` is the engine: everything that inspects or changes the Mac. No UI code.
- `Sources/SiivOS/` is the app: SwiftUI interface only.
- `Tests/SiivOSCoreTests/` holds tests for the engine.
- `docs/design.md` describes how the screens should look and behave. The screens follow it.
- `Resources/AppIcon.icns` is the app icon; its master files are in `design/icon/`.
- `LICENSE` is the GNU General Public License, version 3.
- `Scripts/make-app.sh` builds a double-clickable `SiivOS.app`.
- `Scripts/check-engine-on-linux.sh` compiles and tests the engine in Claude's Linux workspace.
