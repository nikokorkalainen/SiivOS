# SiivOS

A Mac app that cleans up clutter, manages and uninstalls apps, shows what is slowing the Mac down, and checks for malware and adware. It explains every change before making it, lets you undo it, and keeps everything on your Mac.

SiivOS is in early development. See [PLAN.md](PLAN.md) for the plan and current status.

## Requirements

- macOS 14 or newer
- Apple's developer tools: either the Command Line Tools (small, no sign-in needed) or Xcode (large, with a visual editor)

## Build and run with the Command Line Tools

This is the quickest way, and it does not need Xcode. All commands are typed into Terminal (press Command-Space, type "Terminal", press Return).

1. **Install the tools.** Run this and click Install in the window that appears. If it says the tools are already installed, carry on.

   ```
   xcode-select --install
   ```

2. **Download the project.** Open `https://github.com/nikokorkalainen/SiivOS` in your browser while signed in to GitHub. Click the green **Code** button, then **Download ZIP**. Double-click the ZIP in your Downloads folder to unpack it.

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

## Build and run with Xcode

1. **Install Xcode.** Open the App Store, search for "Xcode" and install it. If the App Store says your macOS is too old, download an older Xcode from [developer.apple.com/download/all](https://developer.apple.com/download/all) (free, sign in with your Apple ID).
2. **Open Xcode once.** Accept the licence and let it install the macOS components it asks for.
3. **Sign in to GitHub.** In Xcode, open Settings, then Accounts, press the + button and add your GitHub account. This repository is private, so Xcode needs your login to download it.
4. **Download the project.** On Xcode's welcome window choose "Clone Git Repository", paste `https://github.com/nikokorkalainen/SiivOS` and pick a folder to save it in.
5. **Run the app.** In the bar at the top of the Xcode window, make sure the scheme is **SiivOS** and the destination is **My Mac**, then press the Run button (or Command-R).

To get a newer version later, choose Integrate, then Pull in Xcode's menu bar.

## Run the tests

The tests check the engine that inspects and changes the Mac. They only touch temporary files that they create themselves.

- **In Terminal:** from the project folder, run `swift test`. This may fail with an error about `XCTest` if only the Command Line Tools are installed, because the test library traditionally ships with Xcode.
- **In Xcode:** switch the scheme to **SiivOS-Package** and press Command-U.

## Where SiivOS keeps its data

Everything stays on your Mac, in `~/Library/Application Support/SiivOS`:

- `HoldingArea` holds the items SiivOS has removed, until you put them back or delete them permanently from the History screen.
- `action-log.json` is the list of changes SiivOS has made. It is a plain text file you can open and read.
