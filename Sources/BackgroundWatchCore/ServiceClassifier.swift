import Foundation

public struct ServiceClassifier {
    private let rules: [ServiceRule]
    public init(rules: [ServiceRule] = ServiceRules.load()) { self.rules = rules }

    public func classify(_ record: ProcessRecord) -> ClassifiedProcess {
        let haystack = record.command.lowercased()
        let match = rules.first { rule in
            guard !rule.requiresListeningPort || !record.ports.isEmpty else { return false }
            return !rule.matches.isEmpty && rule.matches.allSatisfy { haystack.contains($0.lowercased()) }
        }
        return ClassifiedProcess(process: record, service: match)
    }
}
