# Swift waiting for a syntax check

The Swift files in this folder come from the design session, whose workspace cannot download
Swift, so they have **not** been through `swiftc -parse`. They sit outside `Sources/`, so the
app's build does not see them and cannot break because of them.

To use them, in the coding session (which has Swift):

1. Merge `claude/design-notes`.
2. Check each file: `swiftc -parse design/swift-pending/<File>.swift`
   (or run `./Scripts/check-engine-on-linux.sh` after moving them).
3. Move them into place, replacing the current file where one exists:
   - `SiivOSIcons.swift` → `Sources/SiivOS/SiivOSIcons.swift`
     (the current file plus one new case, `.settings`, a gear; nothing else changed)
   - `SiivOSSettingsControls.swift` → `Sources/SiivOS/SiivOSSettingsControls.swift` (new)
4. Delete this folder once it is empty.

The design for both is in the "Settings" section of `docs/design.md`.
