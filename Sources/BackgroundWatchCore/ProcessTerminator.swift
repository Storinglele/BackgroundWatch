import Foundation

public enum StopOutcome: Equatable, Sendable { case terminated, stillRunning, failed(String) }

public struct ProcessTerminator {
    public init() {}

    public func isRunning(_ pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM // alive, just not ours to signal
    }

    public func send(_ signal: Int32, to item: ClassifiedProcess) -> Result<Void, Error> {
        guard item.isTarget else { return .failure(NSError(domain: "BackgroundWatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only target services can be stopped"])) }
        guard kill(pid_t(item.process.pid), signal) == 0 else { return .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])) }
        append("\(Date()) signalled \(item.service?.name ?? "unknown") pid=\(item.process.pid) signal=\(name(of: signal))\n")
        return .success(())
    }

    private func name(of signal: Int32) -> String {
        switch signal { case SIGKILL: "SIGKILL"; case SIGTERM: "SIGTERM"; default: "\(signal)" }
    }

    private func append(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BackgroundWatch.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
