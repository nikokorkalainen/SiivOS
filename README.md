# SiivOS

A Mac app that cleans up clutter, manages and uninstalls apps, shows what is slowing the Mac down, and checks for malware and adware. It explains every change before making it, lets you undo it, and keeps everything on your Mac.

SiivOS is in early development. See [PLAN.md](PLAN.md) for the plan and current status.

## Requirements

- macOS 14 or newer
- Xcode (free, from the Mac App Store)

## First-time setup

1. **Install Xcode.** Open the App Store on your Mac, search for "Xcode" and install it. It is a large download.
2. **Open Xcode once.** Accept the licence and let it install the macOS components it asks for.
3. **Sign in to GitHub.** In Xcode, open Settings, then Accounts, press the + button and add your GitHub account. This repository is private, so Xcode needs your login to download it.
4. **Download the project.** On Xcode's welcome window choose "Clone Git Repository", paste `https://github.com/nikokorkalainen/SiivOS` and pick a folder to save it in.
5. **Open the project.** Xcode opens it automatically after cloning. Later, open the `Package.swift` file in the project folder.

## Run the app

1. In the bar at the top of the Xcode window, make sure the scheme is **SiivOS** and the destination is **My Mac**.
2. Press the Run button (or Command-R).

The SiivOS window should open with an Overview of your Mac.

## Run the tests

1. Switch the scheme to **SiivOS-Package**.
2. Press Command-U.

## Get the latest changes

In Xcode's menu bar choose Integrate, then Pull.

## Build a standalone app (optional)

To get a `SiivOS.app` you can double-click without Xcode, open Terminal in the project folder and run:

```
./Scripts/make-app.sh
```

The app is saved to `dist/SiivOS.app`.
