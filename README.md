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
| **Cleanup** | Caches, logs, old downloads, large files, duplicate files, leftovers from apps you have removed, and data piled up by developer tools such as Xcode, npm and Docker. Every item is labelled Safe to remove or Check first. Data of macOS, password managers, iCloud and security software is never listed. A Disk Map shows where the space in your home folder goes. |
| **Apps** | Every app with its size and last use. Uninstalling takes the app's leftovers with it. Background items can be reviewed and removed. |
| **Performance** | Processor, memory, disk and battery right now, with a plain-language explanation when something is holding the Mac back. |
| **Protection** | The protection built into macOS, what starts by itself, browser extensions, configuration profiles and app permissions, plus an optional malware scan with ClamAV. |
| **Health Timeline** | The health score with a reason for every point, charts over time, and the list of changes. |
| **History** | Everything SiivOS has changed, with a way to put it back or delete it for good. |

SiivOS also sits in the menu bar, where it shows the health score and marks its icon when something new starts by itself. It stays there after you close its window, and is in the Dock only while the window is open. This can be turned off in Settings.

## What it does not do

- It does not delete anything without showing you first. It only empties the holding area by itself if you choose a waiting time in Settings, and then only of what has waited that long.
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

## For AI agents (optional)

If you use an AI agent, such as Claude, it can ask SiivOS what it has found instead of digging through your Mac itself. SiivOS comes with a small command-line tool for this, `siivos-cli`. It is off until you turn it on.

- **It only reads.** It can say what is taking space, what has changed lately, why the Mac is slow and what Protection flagged, in the same words the app uses. It cannot remove, move or change anything. Removing stays in the app, where you read the explanation and confirm.
- **SiivOS still sends nothing anywhere.** The tool prints its answer and stops. But an agent that runs on the internet sends what it reads to its own service, including the names of your files and apps. Turn the tool on only if you are comfortable with that.
- **The switch is a courtesy, not a lock.** It controls what SiivOS's own tool will answer. It cannot stop other programs you run from looking at your Mac.

To use it:

1. Build the app with `bash Scripts/make-app.sh`. The tool is put inside the app.
2. In SiivOS, open **Settings** at the bottom of the sidebar (or press Command-comma) and turn on **Let AI agents ask SiivOS questions**.
3. Click **Copy Path** there and give the path to your agent, with a sentence such as "use this tool to look at my Mac; run it with the word help first".

You can try it yourself in Terminal from the project folder:

```
swift run siivos-cli help
```

| Question | What it answers |
|----------|-----------------|
| `status` | Whether the tool is switched on, and where SiivOS keeps its data. |
| `overview` | Disk space, memory, the health score and what waits in the holding area. |
| `health` | The health score with the reason for every point, and recent readings. |
| `changes` | What has changed on the Mac lately. `--days 7` sets how far back. |
| `cleanup` | What could be removed, each item labelled Safe to remove or Check first. |
| `performance` | Processor, memory and battery right now, with what SiivOS makes of them. |
| `protection` | macOS's own protection, background items, browser extensions and profiles. |
| `apps` | Installed apps with their size and last use, largest first. |
| `folders` | Where the space in your home folder goes: the largest folders and what is in them. |
| `history` | What SiivOS itself has changed, and what can still be put back. |

Answers are in JSON and in English. The tool sees what the program that runs it is allowed to see: started from Terminal, it has Terminal's permissions, not SiivOS's. Longer questions print a line for each check as they go, so you can see the tool is working.

### As an MCP server

Many agents can add helpers called MCP servers, which lets them use SiivOS's questions as tools without being told the command by hand. `siivos-cli mcp` is such a server. The agent starts it itself and talks to it directly; nothing listens on the network.

Add it to your agent as a local (stdio) server with:

- **command:** the path from **Copy Path** in SiivOS's Settings
- **argument:** `mcp`

In the Claude desktop app, for example, that is an entry like this in its `claude_desktop_config.json` file:

```
{
  "mcpServers": {
    "siivos": {
      "command": "/path/from/Copy Path/siivos-cli",
      "args": ["mcp"]
    }
  }
}
```

That file usually holds the app's other settings already. Add the `mcpServers` part next to them; do not replace the file. Quit the app before you change the file and open it again afterwards. The file is `~/Library/Application Support/Claude/claude_desktop_config.json`. Ask in a plain chat, not in a coding session that runs in the cloud, because only the app on your Mac can reach a tool on your Mac.

Where this is set differs between agents and changes over time, so check your agent's own instructions for adding a local MCP server. The tools are the same ten questions as above, named `siivos_overview`, `siivos_cleanup` and so on, and the switch in Settings applies to them in the same way.

## Where SiivOS keeps its data

Everything stays on your Mac, in `~/Library/Application Support/SiivOS`:

- `HoldingArea` holds the items SiivOS has removed, until you put them back or delete them permanently from the History screen.
- `action-log.json` is the list of changes SiivOS has made. It is a plain text file you can open and read.
- `health-history.json` is the Health Timeline: the health score and free space each time SiivOS looked, and what had changed on the Mac. It keeps the last 2,000 readings and 1,000 changes, which is well over a year in ordinary use; older ones drop off. It is a plain text file too, and deleting it only starts the timeline again.
- `ClamAV` holds virus definitions, if you have chosen to download them.
- `agent-door.json` remembers whether the tool for AI agents is switched on.
- `cleanup-settings.json` holds your Cleanup settings: how old, how large, which checks run, and folders to leave out.
- `holding-area-settings.json` holds your choices about the holding area.

To remove SiivOS completely, first put back or delete what is in History, then quit SiivOS and delete the app and that folder.

## For developers

SiivOS is a Swift package with no third-party dependencies.

- `Sources/SiivOSCore/` is the engine: everything that inspects or changes the Mac. It has no interface code, is covered by tests, and also compiles on Linux.
- `Sources/SiivOS/` is the app: the SwiftUI interface only. It calls into the engine.
- `Sources/SiivOSCLI/` is the `siivos-cli` tool for AI agents: a few lines that pass the question to the engine.
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

## Licence

Copyright © 2026 Niko Korkalainen.

SiivOS is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

SiivOS is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU General Public License](LICENSE) for more details.

In plain words: you may use, change and share SiivOS freely, and if you share a changed version, it has to stay open source under the same licence.

ClamAV is separate software under its own licence. SiivOS does not include it; it only runs a copy you have installed yourself.
