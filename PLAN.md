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

## Phases

| # | Phase | What it delivers | Status |
|---|-------|------------------|--------|
| 1 | Setup | Build tools installed, project skeleton, this plan in the repo | Done. Built and run on macOS 15.8.3 with the Command Line Tools. Tests not yet run on a Mac |
| 2 | Safety core | Scan engine, action log, undo. Removed items go to a restorable holding area, not straight to deletion | Built. Engine tests pass in Claude's workspace. Awaiting build and test of the app on a Mac |
| 3 | Clutter cleanup | Caches, logs, old downloads, large and duplicate files, leftovers from removed apps | Not started |
| 4 | App manager | All apps with size and last use, full uninstall including leftovers, login items and background agents | Not started |
| 5 | Performance | Live view of processor, memory, disk and battery use, with plain-language diagnoses from built-in rules | Not started |
| 6 | Protection | ClamAV for malware, plus own checks for adware, suspicious background agents, browser extensions and configuration profiles | Not started |
| 7 | Health timeline | Health score with local history | Not started |
| 8 | Polish | Menu bar widget, tests, README and licence, ready for an open-source release | Not started |
| 9 | AI assistant (later) | Added once the rules-based diagnoses work | Not started |

## How we work

- Claude writes the code and commits it to this repository. Claude's workspace cannot compile the Mac app, but it can compile the engine and run its tests (`Scripts/check-engine-on-linux.sh`).
- At the end of each phase, Niko builds and runs the app and reports what works and what breaks. For now this is done with the Command Line Tools (`bash Scripts/make-app.sh`), because Xcode is not installed yet.
- Problems are fixed before the next phase starts.

## Known constraints

- The app will need **Full Disk Access** to do its job, so it cannot be distributed through the Mac App Store. It will be distributed directly.
- A public release needs a paid Apple Developer account for signing and notarisation. Personal use does not.

## Project layout

- `Sources/SiivOSCore/` is the engine: everything that inspects or changes the Mac. No UI code.
- `Sources/SiivOS/` is the app: SwiftUI interface only.
- `Tests/SiivOSCoreTests/` holds tests for the engine.
- `Scripts/make-app.sh` builds a double-clickable `SiivOS.app`.
- `Scripts/check-engine-on-linux.sh` compiles and tests the engine in Claude's Linux workspace.
