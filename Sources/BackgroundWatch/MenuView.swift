import BackgroundWatchCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var store: ProcessStore
    @State private var rows: [Int: RowState] = [:]
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    /// Confirmation happens inline rather than in an alert: an alert takes key window
    /// away from a .transient popover, which closes it, and the follow-up force prompt
    /// would then have no window to present from.
    private enum RowState: Equatable { case confirming, stopping, forceConfirm, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("业务 / 开发服务").font(.headline)
            if store.targets.isEmpty { Text("没有发现目标服务").foregroundStyle(.secondary) }
            ForEach(store.targets) { target($0) }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    DisclosureGroup(heading("应用", store.apps.count)) { ForEach(store.apps) { row($0) } }
                    DisclosureGroup(heading("开发进程", store.dev.count)) { ForEach(store.dev) { row($0) } }
                }
            }
            .frame(maxHeight: 260)

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("开机自动启动", isOn: Binding(get: { launchAtLogin }, set: { @MainActor value in setLaunchAtLogin(value) }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(!LoginItem.isInstalled)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            if !LoginItem.isInstalled {
                Text("把 App 移到「应用程序」后才能开启").font(.caption).foregroundStyle(.secondary)
            } else if LoginItem.needsApproval {
                HStack(spacing: 6) {
                    Text("需要在系统设置中批准").font(.caption).foregroundStyle(.secondary)
                    Button("打开设置") { LoginItem.openSettings() }.controlSize(.small)
                }
            }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }

    private func target(_ item: ClassifiedProcess) -> some View {
        let pid = item.process.pid
        let state = rows[pid]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.service?.name ?? "服务")
                    Text(detail(item.process)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state == .stopping { ProgressView().controlSize(.small) }
                else if state == nil { Button("停止") { rows[pid] = .confirming }.buttonStyle(.borderedProminent) }
            }
            switch state {
            case .confirming:
                ask("确认停止 \(item.service?.name ?? "该服务")？将发送 SIGTERM 并等待最多 5 秒。", confirm: "停止", pid: pid) {
                    Task { await run(item, force: false) }
                }
            case .forceConfirm:
                ask("5 秒内没有响应 SIGTERM。SIGKILL 会立即终止它，未写入的数据会丢失。", confirm: "强制停止", pid: pid) {
                    Task { await run(item, force: true) }
                }
            case .failed(let message):
                HStack {
                    Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("好") { rows[pid] = nil }.controlSize(.small)
                }
            case .stopping:
                Text("停止中…").font(.caption).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
    }

    private func ask(_ text: String, confirm: String, pid: Int, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(confirm, role: .destructive, action: action).controlSize(.small)
                Button("取消") { rows[pid] = nil }.controlSize(.small)
            }
        }
    }

    private func row(_ item: GroupedProcess) -> some View {
        HStack {
            Text(item.name).font(.caption).lineLimit(1)
            Spacer()
            Text(summary(item)).font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor private func run(_ item: ClassifiedProcess, force: Bool) async {
        let pid = item.process.pid
        rows[pid] = .stopping
        switch force ? await store.forceStop(item) : await store.stop(item) {
        case .terminated: rows[pid] = nil
        case .stillRunning: rows[pid] = force ? .failed("SIGKILL 也没能终止它，进程可能处于不可中断状态。") : .forceConfirm
        case .failed(let message): rows[pid] = .failed(message)
        }
    }

    // Built as String, not interpolated into Text directly: a LocalizedStringKey renders
    // a pid of 1506 as "1,506".
    private func detail(_ record: ProcessRecord) -> String {
        let ports = record.ports.map(String.init).joined(separator: ", ")
        return ports.isEmpty ? "PID \(record.pid)" : "PID \(record.pid)  端口 \(ports)"
    }

    private func summary(_ item: GroupedProcess) -> String {
        item.count > 1 ? "\(item.count) 个进程  PID \(item.representative.pid)" : "PID \(item.representative.pid)"
    }

    private func heading(_ title: String, _ count: Int) -> String { "\(title) (\(count))" }
}
