import BackgroundWatchCore
import Foundation

/// Top-level code is main-actor isolated under strict concurrency but not under the
/// default settings, so the counter lives behind a lock rather than in a global var.
final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var failures: Int { lock.lock(); defer { lock.unlock() }; return count }
    func record() { lock.lock(); count += 1; lock.unlock() }
}
let results = Results()

func check(_ condition: Bool, _ label: String) {
    if condition { print("  ok   \(label)") } else { results.record(); print("  FAIL \(label)") }
}
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected { print("  ok   \(label)") } else { results.record(); print("  FAIL \(label)\n         expected: \(expected)\n         actual:   \(actual)") }
}

/// Keyed by argument list so one fake serves the two `ps` calls and `lsof`.
struct FakeRunner: CommandRunning {
    var responses: [String: String]
    func run(_ command: String, arguments: [String]) throws -> String {
        responses[arguments.joined(separator: " ")] ?? ""
    }
}

let commOutput = """
  568 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
  600 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
  700 /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
  800 /opt/homebrew/bin/node
  801 /opt/homebrew/bin/node
  900 /usr/libexec/logd
  950 /bin/zsh
  999 /opt/homebrew/opt/openjdk/bin/java
"""

let commandOutput = """
  568 1 devuser 20-20:45 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --enable-features=x
  600 568 devuser 20-20:45 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=renderer
  700 1 devuser 20-20:45 /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
  800 1 devuser 01:02 /opt/homebrew/bin/node build.js
  801 1 devuser 01:02 /opt/homebrew/bin/node worker.js
  900 1 root 20-20:45 /usr/libexec/logd
  950 1 devuser 00:10 -zsh
  999 1 devuser 20-20:45 /opt/homebrew/opt/openjdk/bin/java -jar app.jar --server.port=8888
"""

// Real lsof puts "(LISTEN)" after the address, so the address is not the last column.
let lsofOutput = """
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
java        999 devuser   10u  IPv4 0xe59f7329c2f91d2f      0t0  TCP 127.0.0.1:8888 (LISTEN)
java        999 devuser   11u  IPv6 0x8bbe32e41132e0cd      0t0  TCP [::1]:8888 (LISTEN)
java        999 devuser   12u  IPv4 0x8bbe32e41132e0ce      0t0  TCP *:9999 (LISTEN)
"""

let fake = FakeRunner(responses: [
    "-axo pid=,comm=": commOutput,
    "-axo pid=,ppid=,user=,etime=,command=": commandOutput,
    "-nP -iTCP -sTCP:LISTEN": lsofOutput,
])

print("scanner")
let records = try ProcessScanner(runner: fake).scan()
checkEqual(records.count, 8, "parses every ps row")
let chrome = records.first { $0.pid == 568 }
checkEqual(chrome?.executable, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "executable keeps spaces in path")
checkEqual(chrome?.user, "devuser", "parses owning user")
checkEqual(chrome?.parentPID, 1, "parses parent pid")
checkEqual(records.first { $0.pid == 900 }?.user, "root", "parses root-owned process")
checkEqual(records.first { $0.pid == 999 }?.ports, [8888, 9999], "parses listening ports and drops the IPv4/IPv6 duplicate")
checkEqual(records.first { $0.pid == 800 }?.ports, [], "process without a listening socket has no ports")

print("rules")
let javaRule = ServiceRule(name: "Java service", matches: ["java"], requiresListeningPort: true)
let classifier = ServiceClassifier(rules: [javaRule])
let classified = records.map(classifier.classify)
checkEqual(classified.first { $0.process.pid == 999 }?.service, javaRule, "matches a rule when the port requirement is met")
checkEqual(classified.first { $0.process.pid == 800 }?.service, nil, "no match without the required listening port")

let bothRule = ServiceRule(name: "Chrome renderer", matches: ["chrome", "--type=renderer"])
checkEqual(ServiceClassifier(rules: [bothRule]).classify(records.first { $0.pid == 600 }!).service, bothRule, "requires every match string to be present")
checkEqual(ServiceClassifier(rules: [bothRule]).classify(records.first { $0.pid == 568 }!).service, nil, "rejects when only some match strings are present")
checkEqual(ServiceClassifier(rules: [ServiceRule(name: "empty", matches: [])]).classify(records[0]).service, nil, "an empty rule never matches everything")

let missing = URL(fileURLWithPath: "/tmp/background-watch-does-not-exist.json")
checkEqual(ServiceRules.load(from: missing), ServiceRules.bundled, "falls back to bundled rules when config is absent")
let broken = URL(fileURLWithPath: "/tmp/background-watch-broken.json")
try? Data("not json".utf8).write(to: broken)
checkEqual(ServiceRules.load(from: broken), ServiceRules.bundled, "falls back to bundled rules when config is malformed")
let custom = URL(fileURLWithPath: "/tmp/background-watch-custom.json")
try? Data(#"[{"name":"My API","matches":["my-api"]}]"#.utf8).write(to: custom)
checkEqual(ServiceRules.load(from: custom).map(\.name), ["My API"], "loads user rules")
checkEqual(ServiceRules.load(from: custom).first?.requiresListeningPort, false, "requiresListeningPort defaults to false when omitted")

print("grouper")
let grouped = ProcessGrouper(currentUser: "devuser").group(classified)
checkEqual(grouped.apps.map(\.name), ["Google Chrome"], "only user-installed app bundles, deduped")
checkEqual(grouped.apps.first?.count, 2, "helper processes count toward their app")
checkEqual(grouped.apps.first?.representative.pid, 568, "representative is the main app process, not a helper")
check(!grouped.apps.contains { $0.name == "Dock" }, "excludes /System app bundles")
checkEqual(grouped.dev.map(\.name), ["node"], "dev tools grouped by executable name")
checkEqual(grouped.dev.first?.count, 2, "counts every process of a dev tool")
check(!grouped.dev.contains { $0.name == "logd" }, "excludes system daemons")
check(!grouped.dev.contains { $0.name == "zsh" }, "excludes shells")
check(!grouped.dev.contains { $0.name == "java" }, "excludes processes already shown as target services")

print("terminator")
let terminator = ProcessTerminator()
check(terminator.isRunning(Int(ProcessInfo.processInfo.processIdentifier)), "detects a live process")
check(!terminator.isRunning(999_999), "detects a dead process")
if case .success = terminator.send(SIGTERM, to: ClassifiedProcess(process: records.first { $0.pid == 800 }!, service: nil)) {
    results.record(); print("  FAIL refuses to signal non-target processes")
} else { print("  ok   refuses to signal non-target processes") }

// A real child that traps SIGTERM proves the escalation path, not just the happy path.
let stubborn = Process()
stubborn.executableURL = URL(fileURLWithPath: "/bin/sh")
stubborn.arguments = ["-c", "trap '' TERM; while :; do sleep 1; done"]
try stubborn.run()
Thread.sleep(forTimeInterval: 1) // let sh reach `trap`, or the default disposition kills it
let stubbornItem = ClassifiedProcess(
    process: ProcessRecord(pid: Int(stubborn.processIdentifier), parentPID: 0, user: NSUserName(),
                           executable: "/bin/sh", command: "/bin/sh -c trap", elapsed: "00:01"),
    service: javaRule)
_ = terminator.send(SIGTERM, to: stubbornItem)
Thread.sleep(forTimeInterval: 1)
check(terminator.isRunning(stubbornItem.process.pid), "SIGTERM alone does not stop a process that traps it")
_ = terminator.send(SIGKILL, to: stubbornItem)
stubborn.waitUntilExit() // reap, so kill(pid, 0) cannot still see a zombie
check(!terminator.isRunning(stubbornItem.process.pid), "SIGKILL stops it")

print("regression")
let done = DispatchSemaphore(value: 0)
final class Box: @unchecked Sendable { var count = -1 }
let box = Box()
Thread.detachNewThread { box.count = ((try? ProcessScanner().scan()) ?? []).count; done.signal() }
check(done.wait(timeout: .now() + 10) != .timedOut, "real scan() does not deadlock on >64KB of ps output")
check(box.count > 10, "real scan() returns records (got \(box.count))")

print(results.failures == 0 ? "\nALL PASS" : "\n\(results.failures) FAILED")
exit(results.failures == 0 ? 0 : 1)
