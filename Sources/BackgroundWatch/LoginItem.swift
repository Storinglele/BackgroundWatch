import AppKit
import Foundation
import ServiceManagement

enum LoginItem {
    /// Registering from a build directory would leave a login item pointing at a path the
    /// next `swift build` can wipe, so this is only offered for an installed copy.
    static var isInstalled: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS parks the item here when the user has to approve it in System Settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
