import BackgroundWatchCore
import Foundation

@MainActor public final class ProcessStore: ObservableObject {
    @Published public private(set) var targets: [ClassifiedProcess] = []
    @Published public private(set) var apps: [GroupedProcess] = []
    @Published public private(set) var dev: [GroupedProcess] = []
    @Published public private(set) var scanError: String?

    private let scanner = ProcessScanner()
    private let classifier = ServiceClassifier()
    private let grouper = ProcessGrouper()
    private let terminator = ProcessTerminator()
    private var timer: Timer?
    private var interval: TimeInterval = .infinity
    private var isScanning = false

    private static let activeInterval: TimeInterval = 3
    private static let idleInterval: TimeInterval = 30

    public init() {
        setActive(false) // also performs the first scan, so the panel is not blank on open
    }

    /// Nobody is reading the list while the panel is closed and every cycle costs three
    /// subprocesses, so the idle cadence is an order of magnitude slower.
    public func setActive(_ active: Bool) {
        refresh()
        let wanted = active ? Self.activeInterval : Self.idleInterval
        guard wanted != interval else { return }
        interval = wanted
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: wanted, repeats: true) { [weak self] _ in
            // Bind before the Task: capturing the weak optional itself is a capture of a
            // mutable var, which stricter toolchains reject.
            guard let store = self else { return }
            Task { @MainActor in store.refresh() }
        }
    }

    /// `ps` and `lsof` cost roughly a third of a second together. Running that on the main
    /// thread stalled the panel, so only the assignment happens here.
    public func refresh() {
        guard !isScanning else { return } // a scan outliving the tick must not pile up
        isScanning = true
        let scanner = scanner, classifier = classifier, grouper = grouper
        Task.detached(priority: .utility) {
            let outcome: Result<[ClassifiedProcess], Error>
            do { outcome = .success(try scanner.scan().map(classifier.classify)) } catch { outcome = .failure(error) }
            let grouped = (try? outcome.get()).map(grouper.group)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanning = false
                switch outcome {
                case .success(let all):
                    self.scanError = nil
                    self.targets = all.filter(\.isTarget)
                    self.apps = grouped?.apps ?? []
                    self.dev = grouped?.dev ?? []
                case .failure(let error):
                    // Keep the last good list on screen rather than blanking it.
                    self.scanError = error.localizedDescription
                }
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
