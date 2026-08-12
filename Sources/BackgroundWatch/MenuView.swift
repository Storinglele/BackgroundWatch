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
            Text(L("services.title")).font(.headline)
            if let error = store.scanError {
                Text(L("services.scanFailed", error)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if store.targets.isEmpty {
                Text(L("services.empty")).foregroundStyle(.secondary)
            }
            ForEach(store.targets) { target($0) }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    DisclosureGroup(L("group.heading", L("group.apps"), String(store.apps.count))) { ForEach(store.apps) { row($0) } }
                    DisclosureGroup(L("group.heading", L("group.dev"), String(store.dev.count))) { ForEach(store.dev) { row($0) } }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(L("login.toggle"), isOn: Binding(get: { launchAtLogin }, set: { @MainActor value in setLaunchAtLogin(value) }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(!LoginItem.isInstalled)
                Spacer()
                Button(L("action.quit")) { NSApplication.shared.terminate(nil) }
            }
            if !LoginItem.isInstalled {
                Text(L("login.needsInstall")).font(.caption).foregroundStyle(.secondary)
            } else if LoginItem.needsApproval {
                HStack(spacing: 6) {
                    Text(L("login.needsApproval")).font(.caption).foregroundStyle(.secondary)
                    Button(L("login.openSettings")) { LoginItem.openSettings() }.controlSize(.small)
                }
            }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func target(_ item: ClassifiedProcess) -> some View {
        let pid = item.process.pid
        let state = rows[pid]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.service?.name ?? L("services.unnamed"))
                    Text(detail(item.process)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state == .stopping { ProgressView().controlSize(.small) }
                else if state == nil { Button(L("action.stop")) { rows[pid] = .confirming }.buttonStyle(.borderedProminent) }
            }
            switch state {
            case .confirming:
                ask(L("confirm.stop", item.service?.name ?? L("services.unnamed")), confirm: L("action.stop"), pid: pid) {
                    Task { await run(item, force: false) }
                }
            case .forceConfirm:
                ask(L("confirm.force"), confirm: L("action.force"), pid: pid) {
                    Task { await run(item, force: true) }
                }
            case .failed(let message):
                HStack {
                    Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("action.ok")) { rows[pid] = nil }.controlSize(.small)
                }
            case .stopping:
                Text(L("status.stopping")).font(.caption).foregroundStyle(.secondary)
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
                Button(L("action.cancel")) { rows[pid] = nil }.controlSize(.small)
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
        case .stillRunning: rows[pid] = force ? .failed(L("error.forceFailed")) : .forceConfirm
        case .failed(let message): rows[pid] = .failed(message)
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

    // pids go through String() first: a LocalizedStringKey would render 1506 as "1,506".
    private func detail(_ record: ProcessRecord) -> String {
        let ports = record.ports.map(String.init).joined(separator: ", ")
        return ports.isEmpty ? L("detail.pid", String(record.pid)) : L("detail.pidPorts", String(record.pid), ports)
    }

    private func summary(_ item: GroupedProcess) -> String {
        item.count > 1
            ? L("group.processCount", String(item.count), String(item.representative.pid))
            : L("detail.pid", String(item.representative.pid))
    }
}
