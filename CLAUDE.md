# Notes for Claude

SiivOS is a macOS optimizer app. Read `PLAN.md` first: it holds the approved plan, principles, and phase status. Update its status table when a phase changes state.

## Constraints

- Claude's cloud workspace is Linux. Run `./Scripts/check-engine-on-linux.sh` before committing engine changes: it installs Swift from download.swift.org (allowed in the owner's environment), compiles and tests `SiivOSCore`, and checks the app's syntax. Keep `SiivOSCore` compiling on Linux; put Mac-only calls behind `#if os(macOS)`.
- The SwiftUI app in `Sources/SiivOS` cannot be compiled here beyond that syntax check, so it is never type-checked before it is committed. Prefer well-established APIs and re-read new SwiftUI carefully. The owner builds on a Mac and reports errors.
- The owner's Mac runs macOS 15.8.3 with Xcode (installed 18 November 2026, version not yet confirmed). They build with `bash Scripts/make-app.sh` and can run `swift test`, so far from a ZIP download of the repository. All 79 engine tests passed on the Mac on 18 November 2026. Ask for `swift test` output whenever the engine changes.
- Target macOS 14+, Swift tools 5.9 (Swift 5 language mode). Do not raise these without asking.
- The owner is new to Xcode and Terminal. Keep build and test instructions step by step, in plain language.

## Architecture rules

- `Sources/SiivOSCore/`: all logic that inspects or changes the system. No SwiftUI or AppKit UI code. Covered by tests.
- `Sources/SiivOS/`: SwiftUI interface only. It calls into SiivOSCore. Its look and wording follow `docs/design.md`; shared colours and building blocks are in `Sources/SiivOS/Theme.swift`.
- No third-party dependencies and no network calls unless the owner approves them (privacy-first principle).
- Nothing destructive without an explanation shown first and an undo path. Removed items go to a restorable holding area.

## Text and languages

- The app is in English and Finnish. Every text shown to people is written as `tr("English text")`, in the engine and in the screens alike. Changing parts are marked `%1$@`, `%2$@` and passed as extra arguments; never put `\(...)` inside `tr`.
- The Finnish wording lives in `Sources/SiivOSCore/Localization/FinnishTexts.swift`, one pair per line. Add the Finnish for every new text in the same change. `Scripts/check-translations.py` (run by the Linux check) fails if any is missing.
- Finnish terms in use, chosen by the owner where marked: app = sovellus (owner; not "appi"), health = terveys (owner; not "kunto"), Health Timeline = Terveystiedot (owner), holding area = välivarasto, cache = välimuisti, item = kohde, Cleanup = Siivous, History = Historia. The one exception is "Appien hallinta", which names a page in macOS's own System Settings.

## Workflow

- Work one plan phase at a time. Do not start the next phase until the owner confirms the current one builds and works.
