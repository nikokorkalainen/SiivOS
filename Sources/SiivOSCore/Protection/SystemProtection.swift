import Foundation

/// Who signed a program, as far as macOS can tell.
public enum CodeSignature: Equatable, Sendable {
    /// Signed by Apple itself.
    case apple
    /// Signed by a developer Apple knows, with their name when it is given.
    case developer(name: String?)
    /// Signed only for the Mac it was built on, which proves nothing about who made it.
    case adHoc
    /// Not signed at all.
    case unsigned
    /// Could not be checked.
    case unknown

    /// Reads what `codesign -dv --verbose=2 <path>` prints.
    static func parse(_ output: String) -> CodeSignature {
        if output.contains("not signed at all") {
            return .unsigned
        }
        if output.contains("Signature=adhoc") {
            return .adHoc
        }
        let authorities = output
            .split(whereSeparator: { $0.isNewline })
            .filter { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }
        guard let first = authorities.first else {
            return .unknown
        }
        if first == "Software Signing" || first.hasPrefix("Apple Mac OS Application Signing") {
            return .apple
        }
        // "Developer ID Application: Example Ltd (ABCDE12345)" gives "Example Ltd".
        if let colon = first.range(of: ": ") {
            var name = String(first[colon.upperBound...])
            if name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) {
                name = String(name[..<open.lowerBound])
            }
            return .developer(name: name.isEmpty ? nil : name)
        }
        return .developer(name: nil)
    }

    /// Asks macOS who signed the program at the path. Read-only.
    static func read(path: String) -> CodeSignature {
        guard let output = SystemCommand.output(
            of: "/usr/bin/codesign",
            ["-dv", "--verbose=2", path],
            includingErrors: true
        ) else {
            return .unknown
        }
        return parse(output)
    }
}

/// Looks at the protection that is built into macOS itself. Read-only.
///
/// macOS does most of the work of keeping a Mac safe. SiivOS says so plainly, shows
/// whether those protections are switched on, and does not pretend to replace them.
enum SystemProtection {
    static func section(
        gatekeeper: String?,
        integrityProtection: String?,
        fileVault: String?,
        firewall: String?,
        xprotectVersion: String?
    ) -> ProtectionSection {
        var findings: [ProtectionFinding] = []

        if let gatekeeper {
            let isOn = gatekeeper.contains("assessments enabled")
            findings.append(
                ProtectionFinding(
                    id: "gatekeeper",
                    level: isOn ? .fine : .attention,
                    title: tr("Gatekeeper"),
                    explanation: isOn
                        ? tr("On. macOS checks apps before they open for the first time.")
                        : tr("Off. macOS is not checking apps before they open. Unless you turned this off on purpose, turn it back on in System Settings, under Privacy & Security.")
                )
            )
        }

        if let integrityProtection {
            let isOn = integrityProtection.lowercased().contains("enabled")
            findings.append(
                ProtectionFinding(
                    id: "system-integrity-protection",
                    level: isOn ? .fine : .attention,
                    title: tr("System Integrity Protection"),
                    explanation: isOn
                        ? tr("On. macOS's own files cannot be changed by other software.")
                        : tr("Off. Software can change macOS's own files. This is only ever turned off on purpose, by someone who knows why.")
                )
            )
        }

        if let xprotectVersion {
            findings.append(
                ProtectionFinding(
                    id: "xprotect",
                    level: .fine,
                    title: tr("Built-in malware protection"),
                    explanation: tr("Present (XProtect, version %1$@). macOS blocks known malware by itself and keeps this list up to date.", xprotectVersion)
                )
            )
        }

        if let fileVault {
            let isOn = fileVault.contains("FileVault is On")
            findings.append(
                ProtectionFinding(
                    id: "filevault",
                    level: isOn ? .fine : .note,
                    title: tr("FileVault"),
                    explanation: isOn
                        ? tr("On. The disk is encrypted, so nobody can read it without your password.")
                        : tr("Off. If this Mac is lost or stolen, its disk can be read without your password. You can turn FileVault on in System Settings, under Privacy & Security.")
                )
            )
        }

        if let firewall {
            let isOn = firewall.lowercased().contains("enabled")
            findings.append(
                ProtectionFinding(
                    id: "firewall",
                    level: isOn ? .fine : .note,
                    title: tr("Firewall"),
                    explanation: isOn
                        ? tr("On. Other devices cannot connect to apps on this Mac unless you allow it.")
                        : tr("Off. This is the macOS default and fine on a home network. On shared or public networks, turning it on in System Settings, under Network, adds some protection.")
                )
            )
        }

        return ProtectionSection(
            id: "macos",
            title: tr("Protection built into macOS"),
            summary: tr("macOS does most of the work of keeping a Mac safe. These are its own protections and whether they are switched on."),
            findings: findings
        )
    }

    /// Runs macOS's own tools to read the settings, then builds the section.
    static func check() -> ProtectionSection {
        section(
            gatekeeper: SystemCommand.output(of: "/usr/sbin/spctl", ["--status"], includingErrors: true),
            integrityProtection: SystemCommand.output(of: "/usr/bin/csrutil", ["status"], includingErrors: true),
            fileVault: SystemCommand.output(of: "/usr/bin/fdesetup", ["status"], includingErrors: true),
            firewall: SystemCommand.output(
                of: "/usr/libexec/ApplicationFirewall/socketfilterfw",
                ["--getglobalstate"],
                includingErrors: true
            ),
            xprotectVersion: xprotectVersion()
        )
    }

    private static func xprotectVersion() -> String? {
        let paths = [
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
            "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
        ]
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let info = plist as? [String: Any],
                  let version = info["CFBundleShortVersionString"] as? String
            else {
                continue
            }
            return version
        }
        return nil
    }
}
