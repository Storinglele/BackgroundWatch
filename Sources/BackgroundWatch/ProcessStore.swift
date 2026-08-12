import BackgroundWatchCore
import Foundation

@MainActor public final class ProcessStore: ObservableObject {
    @Published public private(set) var targets: [ClassifiedProcess] = []
    @Published public private(set) var apps: [GroupedProcess] = []
    @Published public private(set) var dev: [GroupedProcess] = []

    private let scanner = ProcessScanner()
    private let classifier = ServiceClassifier()
    private let grouper = ProcessGrouper()
    private let terminator = ProcessTerminator()
    private var isScanning = false

    public init() {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    /// `ps` and `lsof` cost roughly half a second together. Running that on the main thread
    /// froze the panel for a fifth of every tick, so only the assignment happens here.
    public func refresh() {
        guard !isScanning else { return } // a scan outliving the 3s tick must not pile up
        isScanning = true
        let scanner = scanner, classifier = classifier, grouper = grouper
        Task.detached(priority: .utility) {
            let all = (try? scanner.scan().map(classifier.classify)) ?? []
            let grouped = grouper.group(all)
            let targets = all.filter(\.isTarget)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.targets = targets
                self.apps = grouped.apps
                self.dev = grouped.dev
                self.isScanning = false
            }
        }
    }

    public func stop(_ item: ClassifiedProcess) async -> StopOutcome { await terminate(item, signal: SIGTERM, graceSeconds: 5) }
    public func forceStop(_ item: ClassifiedProcess) async -> StopOutcome { await terminate(item, signal: SIGKILL, graceSeconds: 2) }

    /// Reporting success the moment kill(2) returns is what made a stuck JVM look stopped
    /// while it kept running, so the outcome is decided by polling the pid instead.
    private func terminate(_ item: ClassifiedProcess, signal: Int32, graceSeconds: Int) async -> StopOutcome {
        if case .failure(let error) = terminator.send(signal, to: item) { return .failed(error.localizedDescription) }
        for _ in 0..<(graceSeconds * 4) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !terminator.isRunning(item.process.pid) { refresh(); return .terminated }
        }
        refresh()
        return .stillRunning
    }
}
