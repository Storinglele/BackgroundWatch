import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = ProcessStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("BackgroundWatch: initializing status item")
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "后台服务") {
            icon.isTemplate = true
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageOnly
        } else {
            // `.imageOnly` without an image draws an empty, unclickable-looking item.
            statusItem.button?.title = "后台"
            statusItem.button?.imagePosition = .noImage
        }
        statusItem.button?.toolTip = "后台服务"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        let hosting = NSHostingController(rootView: MenuView(store: store))
        // Without this the popover keeps a fixed height and collapsed groups leave a large
        // empty gap below the content.
        hosting.sizingOptions = [.preferredContentSize]
        popover = NSPopover(); popover.contentViewController = hosting; popover.behavior = .transient; popover.delegate = self
        NSLog("BackgroundWatch: status item ready")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.setActive(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // An .accessory app is never frontmost on its own, so the popover would open
            // without key focus and swallow the first click.
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setActive(false)
    }
}

@main
@MainActor
struct BackgroundWatchMain {
    static var delegate: AppDelegate?
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
