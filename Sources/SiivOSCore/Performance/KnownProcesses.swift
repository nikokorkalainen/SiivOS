import Foundation

/// Says in plain words what well-known parts of macOS do, for the many background
/// programs whose names mean nothing to most people.
public enum KnownProcesses {
    /// A short description of the program, or `nil` when SiivOS has nothing to add.
    public static func explanation(for name: String) -> String? {
        let lowered = name.lowercased()
        switch lowered {
        case "kernel_task":
            return tr("macOS itself. When this is busy, macOS is usually keeping the Mac from getting too hot.")
        case "windowserver":
            return tr("Draws everything you see on the screen.")
        case "mds", "mds_stores", "mdworker", "mdworker_shared", "mdsync", "corespotlightd", "spotlight":
            return tr("Spotlight, updating its search index. It settles down by itself.")
        case "backupd", "backupd-helper":
            return tr("Time Machine, making a backup.")
        case "photoanalysisd", "photolibraryd", "mediaanalysisd":
            return tr("Photos, sorting and recognising pictures. It works while the Mac is idle.")
        case "bird", "cloudd", "fileproviderd":
            return tr("iCloud, keeping your files up to date.")
        case "softwareupdated", "softwareupdate":
            return tr("Checking for or installing macOS updates.")
        case "trustd", "syspolicyd", "xprotectservice", "xprotect":
            return tr("macOS checking that apps are safe to open.")
        case "coreaudiod":
            return tr("Handles sound for all apps.")
        case "launchd":
            return tr("Starts and looks after every other program on the Mac.")
        default:
            return nil
        }
    }
}
