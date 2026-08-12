import Foundation

public struct ProcessRecord: Identifiable, Equatable, Sendable {
    public let pid: Int
    public let parentPID: Int
    public let user: String
    public let executable: String
    public let command: String
    public let elapsed: String
    public let ports: [Int]
    public var id: Int { pid }

    public init(pid: Int, parentPID: Int, user: String, executable: String, command: String, elapsed: String, ports: [Int] = []) {
        self.pid = pid; self.parentPID = parentPID; self.user = user; self.executable = executable; self.command = command; self.elapsed = elapsed; self.ports = ports
    }
}

public struct ClassifiedProcess: Identifiable, Equatable, Sendable {
    public let process: ProcessRecord
    public let service: ServiceRule?
    public var id: Int { process.pid }
    public var isTarget: Bool { service != nil }

    public init(process: ProcessRecord, service: ServiceRule?) {
        self.process = process; self.service = service
    }
}

public enum OtherGroup: String, Equatable, Sendable { case app, dev }

/// One row in the read-only lists: every process of an app or tool collapsed into a
/// single entry, since Chrome alone accounts for ~80 processes.
public struct GroupedProcess: Identifiable, Equatable, Sendable {
    public let name: String
    public let group: OtherGroup
    public let representative: ProcessRecord
    public let count: Int
    public var id: String { "\(group.rawValue)-\(name)" }

    public init(name: String, group: OtherGroup, representative: ProcessRecord, count: Int) {
        self.name = name; self.group = group; self.representative = representative; self.count = count
    }
}
