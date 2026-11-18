import Foundation

/// Looks at background items the way adware uses them: to keep itself running. Read-only.
///
/// The rules are deliberately few and explainable. Most background items are harmless
/// updaters and helpers, and SiivOS says so instead of making a list look alarming.
enum BackgroundItemReview {
    /// Names of adware and other unwanted software that has been common on the Mac. A match
    /// is a reason to look, not proof.
    private static let knownUnwantedNames = [
        "genieo", "vsearch", "pirrit", "shlayer", "bundlore", "crossrider", "installmac",
        "searchmine", "safefinder", "operatormac", "mughthesec",
        "advancedmaccleaner", "macautofixer", "smartmacbooster", "maccleanuppro"
    ]

    /// The known name that the item's own name or program matches, if any.
    ///
    /// Short names must match a whole word or the start of one ("com.genieo.completer"),
    /// so that an innocent name which merely contains the letters is not flagged. Long
    /// names are distinctive enough to be looked for with spaces and dots ignored.
    static func knownUnwantedName(in text: String) -> String? {
        let lowered = text.lowercased()
        let words = lowered.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let joined = lowered.filter { $0.isLetter || $0.isNumber }
        return knownUnwantedNames.first { name in
            if words.contains(where: { $0.hasPrefix(name) }) {
                return true
            }
            return name.count >= 12 && joined.contains(name)
        }
    }

    /// Programs that run a command or script handed to them, instead of being the app itself.
    private static let scriptRunners: Set<String> = [
        "sh", "bash", "zsh", "osascript", "python", "python3", "perl", "ruby", "curl", "node"
    ]

    /// - Parameter signature: Looks up who signed the program at a path.
    static func section(
        items: [BackgroundItem],
        homeDirectory: URL,
        signature: (String) -> CodeSignature
    ) -> ProtectionSection {
        ProtectionSection(
            id: "background-items",
            title: tr("Background items"),
            summary: tr("Programs that macOS starts by itself. Most are harmless updaters and helpers, but this is also how adware keeps itself running, so SiivOS looks at where each one lives, what it runs and who made it."),
            findings: items.map { review($0, homeDirectory: homeDirectory, signature: signature) }
        )
    }

    static func review(
        _ item: BackgroundItem,
        homeDirectory: URL,
        signature: (String) -> CodeSignature
    ) -> ProtectionFinding {
        let canRemove = item.scope == .user
        func finding(_ level: ProtectionFinding.Level, _ explanation: String) -> ProtectionFinding {
            ProtectionFinding(
                id: item.url.path,
                level: level,
                title: item.label,
                explanation: explanation,
                detail: item.program ?? item.url.path,
                fileURL: item.url,
                canRemove: canRemove
            )
        }

        if let name = knownUnwantedName(in: item.label + " " + (item.program ?? "")) {
            return finding(.attention, tr("Its name matches adware that has been common on the Mac (%1$@). That is not proof, but it is worth checking whether you installed it.", name))
        }

        guard let program = item.program else {
            return finding(.fine, tr("Nothing unusual."))
        }

        if let place = unusualPlace(for: program, homeDirectory: homeDirectory) {
            return finding(.attention, tr("It starts a program kept in %1$@, a place ordinary software rarely uses for this.", place))
        }

        if !item.programExists {
            return finding(.note, tr("Its program is missing. It was probably left behind by an app you removed, and does nothing now."))
        }

        let programName = URL(fileURLWithPath: program).lastPathComponent.lowercased()
        if scriptRunners.contains(programName) {
            return finding(.note, tr("It runs a command or script directly instead of an app. That is often fine, but it is also a common trick of adware, so check that you recognise it."))
        }

        switch signature(program) {
        case .apple:
            return finding(.fine, tr("Its program is part of macOS."))
        case .developer(let name):
            if let name {
                return finding(.fine, tr("Its program is signed by %1$@.", name))
            }
            return finding(.fine, tr("Its program is signed by a developer Apple knows."))
        case .adHoc, .unsigned:
            return finding(.note, tr("Its program is not signed by a developer Apple knows, so there is no telling who made it. That is common for tools you built or installed yourself."))
        case .unknown:
            return finding(.fine, tr("Nothing unusual."))
        }
    }

    /// A plain description of the place when a program lives somewhere ordinary software
    /// rarely starts itself from, otherwise `nil`.
    private static func unusualPlace(for program: String, homeDirectory: URL) -> String? {
        let path = URL(fileURLWithPath: program).standardizedFileURL.path
        let lowered = path.lowercased()
        let home = homeDirectory.standardizedFileURL.path.lowercased()

        for prefix in ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/"] where lowered.hasPrefix(prefix) {
            return tr("a temporary folder")
        }
        if lowered.hasPrefix("/users/shared/") {
            return tr("the Shared folder")
        }
        for folder in ["downloads", "desktop", "documents"] where lowered.hasPrefix(home + "/" + folder + "/") {
            return tr("one of your own folders")
        }
        // A folder whose name starts with a dot is hidden in Finder.
        let folders = path.split(separator: "/").dropLast()
        if folders.contains(where: { $0.hasPrefix(".") }) {
            return tr("a hidden folder")
        }
        return nil
    }
}
