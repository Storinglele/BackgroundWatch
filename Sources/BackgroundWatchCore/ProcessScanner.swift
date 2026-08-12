import Foundation

public protocol CommandRunning: Sendable { func run(_ command: String, arguments: [String]) throws -> String }
public struct SystemCommandRunner: CommandRunning, Sendable {
    public init() {}
    public func run(_ command: String, arguments: [String]) throws -> String {
        let p = Process(); let out = Pipe(); p.executableURL = URL(fileURLWithPath: command); p.arguments = arguments; p.standardOutput = out; p.standardError = FileHandle.nullDevice; try p.run()
        // Drain the pipe before waiting: `ps -axo` emits ~200KB, well past the 64KB pipe
        // buffer, and a child blocked writing into a full pipe never exits.
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "BackgroundWatch", code: Int(p.terminationStatus)) }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct ProcessScanner: Sendable {
    let runner: CommandRunning
    public init(runner: CommandRunning = SystemCommandRunner()) { self.runner = runner }

    public func scan() throws -> [ProcessRecord] {
        let executables = parseExecutables(try runner.run("/bin/ps", arguments: ["-axo", "pid=,comm="]))
        let listing = try runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,user=,etime=,command="])
        let portMap = parsePorts((try? runner.run("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"])) ?? "")
        return listing.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 4, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 5, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }
            let command = String(parts[4])
            return ProcessRecord(pid: pid, parentPID: ppid, user: String(parts[2]), executable: executables[pid] ?? command.split(separator: " ").first.map(String.init) ?? command, command: command, elapsed: String(parts[3]), ports: portMap[pid] ?? [])
        }
    }

    /// `comm` carries the binary path on its own, so paths containing spaces
    /// ("/Applications/Google Chrome.app/...") survive intact; splitting the full
    /// command line on spaces would truncate them at "/Applications/Google".
    private func parseExecutables(_ output: String) -> [Int: String] {
        var result = [Int: String]()
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            result[pid] = String(parts[1])
        }
        return result
    }

    private func parsePorts(_ output: String) -> [Int: [Int]] {
        var result = [Int: [Int]]()
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count > 8, let pid = Int(fields[1]) else { continue }
            // The NAME column ("127.0.0.1:10000", "*:24282", "[::1]:8080") is followed by
            // "(LISTEN)", so the address is never the last field.
            guard let address = fields.last(where: { $0.contains(":") }),
                  let port = Int(address.split(separator: ":").last ?? "") else { continue }
            if !(result[pid]?.contains(port) ?? false) { result[pid, default: []].append(port) }
        }
        return result
    }
}
