import Foundation

/// A process counts as a watched service when its command line contains every string in
/// `matches`. Rules are data rather than code so the services worth watching live in the
/// user's own config instead of this repository.
public struct ServiceRule: Codable, Equatable, Sendable {
    public let name: String
    public let matches: [String]
    public let requiresListeningPort: Bool

    public init(name: String, matches: [String], requiresListeningPort: Bool = false) {
        self.name = name; self.matches = matches; self.requiresListeningPort = requiresListeningPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        matches = try container.decode([String].self, forKey: .matches)
        requiresListeningPort = try container.decodeIfPresent(Bool.self, forKey: .requiresListeningPort) ?? false
    }
}

public enum ServiceRules {
    /// Deliberately generic: a local process holding a listening port is the closest
    /// thing to a universally meaningful "background service".
    public static let bundled: [ServiceRule] = [
        ServiceRule(name: "Node service", matches: ["node"], requiresListeningPort: true),
        ServiceRule(name: "Python service", matches: ["python"], requiresListeningPort: true),
        ServiceRule(name: "Java service", matches: ["java"], requiresListeningPort: true),
        ServiceRule(name: "Ruby service", matches: ["ruby"], requiresListeningPort: true),
        ServiceRule(name: "Deno service", matches: ["deno"], requiresListeningPort: true),
    ]

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/background-watch/services.json")
    }

    /// Falls back to the bundled rules on a missing, empty or malformed file so a typo in
    /// the config cannot leave the menu permanently blank.
    public static func load(from url: URL = configURL) -> [ServiceRule] {
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([ServiceRule].self, from: data),
              !rules.isEmpty
        else { return bundled }
        return rules
    }
}
