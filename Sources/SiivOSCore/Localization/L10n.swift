import Foundation

/// The languages SiivOS can show its text in.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case finnish = "fi"
}

/// Turns the app's English text into the language the Mac is set to.
///
/// All text shown to people goes through the `tr` function below. The English text itself is the
/// key: English is returned as written, and other languages are looked up in a table
/// (see `FinnishTexts`). Text with changing parts marks them `%1$@`, `%2$@` and so on,
/// so that a translation can put them in a different order.
public enum L10n {
    /// Set by tests to pin the language. Normally `nil`, which follows the Mac.
    public static var overrideLanguage: AppLanguage?

    /// The language the Mac, or this app in System Settings, is set to. Read once at launch.
    private static let systemLanguage: AppLanguage = {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("fi") ? .finnish : .english
    }()

    /// The language text is shown in right now.
    public static var language: AppLanguage {
        overrideLanguage ?? systemLanguage
    }

    /// The text in the given language, with its changing parts filled in.
    /// Text without a translation is shown in English.
    public static func text(_ english: String, _ arguments: [String] = [], in language: AppLanguage) -> String {
        let template: String
        switch language {
        case .english:
            template = english
        case .finnish:
            template = FinnishTexts.table[english] ?? english
        }
        return fill(template, with: arguments)
    }

    /// Replaces `%1$@`, `%2$@`, ... with the matching arguments, in one pass, so that an
    /// argument which itself contains such a marker (a file name, say) is left as it is.
    static func fill(_ template: String, with arguments: [String]) -> String {
        guard !arguments.isEmpty else {
            return template
        }
        var result = ""
        var rest = Substring(template)
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            let afterPercent = rest.index(after: percent)
            let digits = rest[afterPercent...].prefix { ("0"..."9").contains($0) }
            let afterDigits = digits.endIndex
            if let number = Int(digits),
               number >= 1,
               number <= arguments.count,
               rest[afterDigits...].hasPrefix("$@") {
                result += arguments[number - 1]
                rest = rest[rest.index(afterDigits, offsetBy: 2)...]
            } else {
                result += "%"
                rest = rest[afterPercent...]
            }
        }
        result += rest
        return result
    }

    /// The numbers of the changing parts a text uses: "%2$@ of %1$@" gives [1, 2].
    static func placeholders(in template: String) -> Set<Int> {
        var found = Set<Int>()
        var rest = Substring(template)
        while let percent = rest.firstIndex(of: "%") {
            let afterPercent = rest.index(after: percent)
            let digits = rest[afterPercent...].prefix { ("0"..."9").contains($0) }
            if let number = Int(digits), rest[digits.endIndex...].hasPrefix("$@") {
                found.insert(number)
            }
            rest = rest[afterPercent...]
        }
        return found
    }
}

/// The given English text in the language the Mac is set to.
///
/// - Parameters:
///   - english: The text in English. Mark changing parts as `%1$@`, `%2$@`, ...
///   - arguments: The values for the changing parts, in order.
public func tr(_ english: String, _ arguments: String...) -> String {
    L10n.text(english, arguments, in: L10n.language)
}
