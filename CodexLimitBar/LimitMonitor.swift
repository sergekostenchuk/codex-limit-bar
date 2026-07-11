import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LimitMonitor {
    private(set) var snapshot: LimitSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastCheckedAt: Date?
    private(set) var errorMessage: String?
    private(set) var launchAtLogin = false
    var onChange: (() -> Void)?

    private let reader = SessionLimitReader()
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private let defaultsKey = "lastLimitSnapshot"

    init() {
        restoreSnapshot()
        updateLaunchAtLoginState()
        enableLaunchAtLoginOnFirstLaunch()
        startTimer()
        observeWake()
        refresh()
    }

    var menuTitle: String {
        guard let primary = snapshot?.primary else { return "Codex —" }
        return "Codex \(primary.remainingPercent)%"
    }

    var compactTitle: String {
        guard let remaining = snapshot?.primary?.remainingPercent else { return "—" }
        return "\(remaining)%"
    }

    var statusSymbol: String {
        guard let remaining = snapshot?.primary?.remainingPercent else { return "gauge.with.dots.needle.0percent" }
        if remaining <= 10 { return "exclamationmark.triangle.fill" }
        if remaining <= 30 { return "gauge.with.dots.needle.33percent" }
        return "gauge.with.dots.needle.67percent"
    }

    var isStale: Bool {
        guard let capturedAt = snapshot?.capturedAt else { return true }
        return Date().timeIntervalSince(capturedAt) > 15 * 60
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        onChange?()

        Task {
            let found = await Task.detached(priority: .utility) { [reader] in
                reader.latestSnapshot()
            }.value

            lastCheckedAt = Date()
            isRefreshing = false
            if let found {
                if snapshot == nil || found.capturedAt >= snapshot!.capturedAt {
                    snapshot = found
                    persist(found)
                }
            } else if snapshot == nil {
                errorMessage = "Данные Codex пока не найдены"
            }
            onChange?()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            errorMessage = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            updateLaunchAtLoginState()
        }
        onChange?()
    }

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
        source.setEventHandler { [weak self] in self?.refresh() }
        source.resume()
        timer = source
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(LimitSnapshot.self, from: data) else { return }
        snapshot = saved
    }

    private func persist(_ snapshot: LimitSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func updateLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func enableLaunchAtLoginOnFirstLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let key = "didConfigureLaunchAtLogin"
        let pathKey = "launchAtLoginBundlePath"
        let firstLaunch = !UserDefaults.standard.bool(forKey: key)
        if firstLaunch { UserDefaults.standard.set(true, forKey: key) }
        let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
        let registeredPath = UserDefaults.standard.string(forKey: pathKey)
        if firstLaunch || registeredPath != currentPath {
            Task { @MainActor [weak self] in
                do {
                    if SMAppService.mainApp.status == .enabled {
                        try await SMAppService.mainApp.unregister()
                        try await Task.sleep(for: .seconds(1))
                    }
                    try SMAppService.mainApp.register()
                    self?.launchAtLogin = true
                    UserDefaults.standard.set(currentPath, forKey: pathKey)
                } catch {
                    self?.errorMessage = "Не удалось настроить автозапуск: \(error.localizedDescription)"
                    UserDefaults.standard.set(error.localizedDescription, forKey: "launchAtLoginError")
                    self?.updateLaunchAtLoginState()
                }
                self?.onChange?()
            }
        }
    }
}
