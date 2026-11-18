# SiivOS

A Mac app that cleans up clutter, manages and uninstalls apps, shows what is slowing the Mac down, and checks for malware and adware. It explains every change before making it, lets you undo it, and keeps everything on your Mac.

SiivOS is in English and Finnish and follows the language of your Mac. It needs macOS 14 or newer.

## What makes it different

- **Explain and undo.** Before anything is removed, SiivOS shows what will happen in plain words. Removed items go to a holding area, not straight to deletion, and a whole change, such as an uninstall, can be put back in one click from History.
- **Private.** Everything runs on your Mac. No account, no telemetry, no ads. The only network use is downloading virus definitions, and only when you click the button for it.
- **Honest.** No "memory booster" and no scare numbers. On a Mac the real gains come from freeing disk space and taming what starts by itself, so that is what SiivOS helps with.
- **A health timeline.** A health score that shows its reasons, and a record of what changed on the Mac and when: apps installed and removed, new background items, free space going up and down.

## What it does

| Section | What you get |
|---------|--------------|
| **Overview** | Free space, what the last check found, the health score, and free space over time. |
| **Cleanup** | Caches, logs, old downloads, large files, duplicate files, and leftovers from apps you have removed. Data of macOS, password managers, iCloud and security software is never listed. |
| **Apps** | Every app with its size and last use. Uninstalling takes the app's leftovers with it. Background items can be reviewed and removed. |
| **Performance** | Processor, memory, disk and battery right now, with a plain-language explanation when something is holding the Mac back. |
| **Protection** | The protection built into macOS, what starts by itself, browser extensions, configuration profiles and app permissions, plus an optional malware scan with ClamAV. |
| **Health Timeline** | The health score with a reason for every point, charts over time, and the list of changes. |
| **History** | Everything SiivOS has changed, with a way to put it back or delete it for good. |

SiivOS also sits in the menu bar, where it shows the health score and marks its icon when something new starts by itself. This can be turned off in Settings.

## What it does not do

- It does not delete anything without showing you first, and it does not empty the holding area by itself.
- It does not "free up memory", clear browser history, or update other apps.
- It does not remove items that belong to all users of the Mac, because that needs administrator rights, which SiivOS does not ask for. It shows them and leaves them alone.
- It cannot list the "Open at Login" apps in System Settings, because macOS gives apps no way to read them. It lists background items and opens System Settings for the rest.

## Getting SiivOS

There is no ready-made download yet. A signed download needs a paid Apple Developer account, so for now you build SiivOS yourself. It takes a few minutes and you do not need to know how to program.

You need Apple's developer tools: either the Command Line Tools (small, no sign-in needed) or Xcode (large, with a visual editor).

### Build with the Command Line Tools

All commands are typed into Terminal (press Command-Space, type "Terminal", press Return).

1. **Install the tools.** Run this and click Install in the window that appears. If it says the tools are already installed, carry on.

   ```
   xcode-select --install
   ```

2. **Download the project.** Open `https://github.com/nikokorkalainen/SiivOS` in your browser. Click the green **Code** button, then **Download ZIP**. Double-click the ZIP in your Downloads folder to unpack it.

3. **Go to the project folder.** Type `cd ` (with a space after it), drag the unpacked folder from Finder into the Terminal window, and press Return.

4. **Build the app.** The first build takes a minute or two.

   ```
   bash Scripts/make-app.sh
   ```

5. **Open it.**

   ```
   open dist/SiivOS.app
   ```

To get a newer version later, download the ZIP again and repeat steps 2 to 5.

### Build with Xcode

1. **Install Xcode** from the App Store. If the App Store says your macOS is too old, download an older Xcode from [developer.apple.com/download/all](https://developer.apple.com/download/all) (free, sign in with your Apple ID).
2. **Open Xcode once.** Accept the licence and let it install the macOS components it asks for.
3. **Download the project.** On Xcode's welcome window choose "Clone Git Repository", paste `https://github.com/nikokorkalainen/SiivOS` and pick a folder to save it in.
4. **Run the app.** In the bar at the top of the Xcode window, make sure the scheme is **SiivOS** (not SiivOS-Package) and the destination is **My Mac**, then press the Run button (or Command-R).

To get a newer version later, choose Integrate, then Pull in Xcode's menu bar.

## Permissions

SiivOS works without any special permission, but macOS hides some things from every app until you allow it:

- **Full Disk Access** lets SiivOS show which apps hold which permissions. Without it that list stays empty and a few folders that macOS protects are skipped.
- **App Management** lets SiivOS move apps out of the Applications folder when you uninstall them.

Both are in System Settings, under Privacy & Security. SiivOS tells you when one of them would help and never asks for your password.

## Malware scanning (optional)

SiivOS can scan files for malware with [ClamAV](https://www.clamav.net), free software that you install yourself. SiivOS does not include it. To add it, install Homebrew from `https://brew.sh`, then run this in Terminal:

```
brew install clamav
```

In SiivOS, open Protection and click **Download Definitions**. That download, from ClamAV's servers, is the only time SiivOS uses the network, and it only happens when you click the button.

## Where SiivOS keeps its data

Everything stays on your Mac, in `~/Library/Application Support/SiivOS`:

- `HoldingArea` holds the items SiivOS has removed, until you put them back or delete them permanently from the History screen.
- `action-log.json` is the list of changes SiivOS has made. It is a plain text file you can open and read.
- `health-history.json` is the Health Timeline: the health score and free space each time SiivOS looked, and what had changed on the Mac. It is a plain text file too, and deleting it only starts the timeline again.
- `ClamAV` holds virus definitions, if you have chosen to download them.

To remove SiivOS completely, first put back or delete what is in History, then quit SiivOS and delete the app and that folder.

## For developers

SiivOS is a Swift package with no third-party dependencies.

- `Sources/SiivOSCore/` is the engine: everything that inspects or changes the Mac. It has no interface code, is covered by tests, and also compiles on Linux.
- `Sources/SiivOS/` is the app: the SwiftUI interface only. It calls into the engine.
- `Tests/SiivOSCoreTests/` holds the engine's tests.
- `docs/design.md` describes how the screens look and behave.
- `PLAN.md` holds the plan, the principles and what is done.

### Run the tests

The tests only touch temporary files that they create themselves, apart from a few that read (never change) the Mac they run on.

- **In Terminal:** from the project folder, run `swift test`. This needs Xcode; with only the Command Line Tools it fails with an error about `XCTest`.
- **In Xcode:** switch the scheme to **SiivOS-Package** and press Command-U.
- **On Linux:** `./Scripts/check-engine-on-linux.sh` compiles and tests the engine, checks the app's syntax and checks that every text has a Finnish translation.

### Rules a change must follow

1. Nothing destructive without an explanation shown first and a way to undo it. Removals go through `SafetyCore`, which moves items to the holding area and records the change.
2. No network calls and no third-party dependencies.
3. Code that inspects or changes the Mac belongs in the engine, with tests.
4. Every text shown to people is written as `tr("English text")`, with its Finnish added to `Sources/SiivOSCore/Localization/FinnishTexts.swift` in the same change.
5. Plain words. No scare tactics, and no feature that only looks useful.
