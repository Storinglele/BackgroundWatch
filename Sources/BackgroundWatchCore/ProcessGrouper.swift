import Foundation

/// Splits everything that is not a tracked service into the two lists the menu shows:
/// applications the user installed, and command-line development processes.
public struct ProcessGrouper: Sendable {
    private static let appMarker = ".app/Contents/MacOS/"
    private static let nestedMarkers = ["/Contents/Frameworks/", "/Contents/Helpers/", "/Contents/PlugIns/", "/Contents/Library/", "XPCServices", ".appex/"]
    private static let systemPrefixes = ["/System/", "/Library/Apple/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/"]
    private static let shellNoise: Set<String> = ["zsh", "bash", "sh", "fish", "login", "ps", "lsof", "sleep", "env", "tmux", "screen", "<defunct>"]

    private let currentUser: String
    public init(currentUser: String = NSUserName()) { self.currentUser = currentUser }

    public func group(_ items: [ClassifiedProcess]) -> (apps: [GroupedProcess], dev: [GroupedProcess]) {
        let mine = items.filter { !$0.isTarget && $0.process.user == currentUser }
        return (apps: groupApps(mine), dev: groupDev(mine))
    }

    private func groupApps(_ items: [ClassifiedProcess]) -> [GroupedProcess] {
        var buckets = [String: [ProcessRecord]]()
        for item in items {
            let path = item.process.executable
            guard path.contains(Self.appMarker), !path.hasPrefix("/System/"), let bundle = outermostAppName(path) else { continue }
            buckets[bundle, default: []].append(item.process)
        }
        return buckets.compactMap { name, records in
            // Helpers sit under Frameworks/PlugIns and often hold a lower pid than the app
            // itself, so pick the binary living directly in the bundle's MacOS directory.
            let main = records.filter { isMainBinary($0.executable) }.min { $0.pid < $1.pid }
            guard let representative = main ?? records.min(by: { $0.pid < $1.pid }) else { return nil }
            return GroupedProcess(name: name, group: .app, representative: representative, count: records.count)
        }.sorted(by: byCountThenName)
    }

    private func groupDev(_ items: [ClassifiedProcess]) -> [GroupedProcess] {
        var buckets = [String: [ProcessRecord]]()
        for item in items {
            let path = item.process.executable
            guard !path.contains(".app/"), !Self.systemPrefixes.contains(where: path.hasPrefix) else { continue }
            let name = (path as NSString).lastPathComponent
            guard !name.isEmpty, !name.hasPrefix("-"), !Self.shellNoise.contains(name) else { continue }
            buckets[name, default: []].append(item.process)
        }
        return buckets.compactMap { name, records in
            guard let representative = records.min(by: { $0.pid < $1.pid }) else { return nil }
            return GroupedProcess(name: name, group: .dev, representative: representative, count: records.count)
        }.sorted(by: byCountThenName)
    }

    /// The first ".app/" in the path is the outermost bundle, which is what attributes a
    /// nested helper back to the application that spawned it.
    private func outermostAppName(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        let name = (String(path[path.startIndex..<range.lowerBound]) as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private func isMainBinary(_ path: String) -> Bool {
        Self.nestedMarkers.allSatisfy { !path.contains($0) } && path.components(separatedBy: ".app/").count == 2
    }

    private func byCountThenName(_ a: GroupedProcess, _ b: GroupedProcess) -> Bool {
        a.count == b.count ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending : a.count > b.count
    }
}
