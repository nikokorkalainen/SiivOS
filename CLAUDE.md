# Notes for Claude

SiivOS is a macOS optimizer app. Read `PLAN.md` first: it holds the approved plan, principles, and phase status. Update its status table when a phase changes state.

## Constraints

- Claude's cloud workspace has no Swift toolchain, so code here is never compiled before it is committed. Prefer well-established APIs and re-read new Swift carefully. The owner builds on a Mac and reports errors.
- The owner's Mac runs macOS 15.8.3 with the Command Line Tools (Swift 6.1.2) and no Xcode yet. They build with `bash Scripts/make-app.sh` from a ZIP download of the repository. `swift test` may not work without Xcode.
- Target macOS 14+, Swift tools 5.9 (Swift 5 language mode). Do not raise these without asking.
- The owner is new to Xcode and Terminal. Keep build and test instructions step by step, in plain language.

## Architecture rules

- `Sources/SiivOSCore/`: all logic that inspects or changes the system. No SwiftUI or AppKit UI code. Covered by tests.
- `Sources/SiivOS/`: SwiftUI interface only. It calls into SiivOSCore.
- No third-party dependencies and no network calls unless the owner approves them (privacy-first principle).
- Nothing destructive without an explanation shown first and an undo path. Removed items go to a restorable holding area.

## Workflow

- Work one plan phase at a time. Do not start the next phase until the owner confirms the current one builds and works.
