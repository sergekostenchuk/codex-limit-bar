import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LimitMonitor {
    private(set) var snapshotsByLimitID: [String: LimitSnapshot] = [:]
    private(set) var isRefreshing = false
    private(set) var lastCheckedAt: Date?
    private(set) var errorMessage: String?
    private(set) var launchAtLogin = false
    var onChange: (() -> Void)?

    private let reader = SessionLimitReader()
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private let defaultsKey = "lastLimitSnapshots"
    private let legacyDefaultsKey = "lastLimitSnapshot"

    var generalSnapshot: LimitSnapshot? {
        snapshotsByLimitID[LimitSnapshot.generalLimitID]
    }

    var sparkSnapshot: LimitSnapshot? {
        snapshotsByLimitID.values
            .filter(\.isSpark)
            .max { $0.capturedAt < $1.capturedAt }
    }

    private var sectionedSnapshots: [(title: String, snapshot: LimitSnapshot)] {
        var result: [(String, LimitSnapshot)] = []
        if let general = generalSnapshot { result.append((general.sectionTitle, general)) }
        if let spark = sparkSnapshot { result.append((spark.sectionTitle, spark)) }
        return result
    }

    private var displayRemainingPercent: Int? {
        if let remaining = generalSnapshot?.primary?.remainingPercent { return remaining }
        return sparkSnapshot?.primary?.remainingPercent
    }

    init() {
        restoreSnapshot()
        updateLaunchAtLoginState()
        enableLaunchAtLoginOnFirstLaunch()
        startTimer()
        observeWake()
        refresh()
    }

    var menuTitle: String {
        guard let remaining = displayRemainingPercent else { return "Codex —" }
        return "Codex \(remaining)%"
    }

    var compactTitle: String {
        guard let general = generalSnapshot?.primary else {
            return if let spark = sparkSnapshot?.primary?.remainingPercent { "S \(spark)%" } else { "—" }
        }
        if let spark = sparkSnapshot?.primary?.remainingPercent {
            return "\(general.remainingPercent)% · S \(spark)%"
        }
        return "\(general.remainingPercent)%"
    }

    var statusSymbol: String {
        guard let remaining = displayRemainingPercent else { return "gauge.with.dots.needle.0percent" }
        if remaining <= 10 { return "exclamationmark.triangle.fill" }
        if remaining <= 30 { return "gauge.with.dots.needle.33percent" }
        return "gauge.with.dots.needle.67percent"
    }

    var isStale: Bool {
        guard let latestCapturedAt = snapshotsByLimitID.values.map(\.capturedAt).max() else { return true }
        return Date().timeIntervalSince(latestCapturedAt) > 15 * 60
    }

    var hasSnapshots: Bool {
        !snapshotsByLimitID.isEmpty
    }

    var sectionSnapshots: [(title: String, snapshot: LimitSnapshot)] {
        sectionedSnapshots
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        onChange?()

        Task {
            let found = await Task.detached(priority: .utility) { [reader] in
                reader.latestSnapshots()
            }.value

            lastCheckedAt = Date()
            isRefreshing = false
            if found.isEmpty {
                if snapshotsByLimitID.isEmpty {
                    errorMessage = "Данные Codex пока не найдены"
                }
            } else {
                errorMessage = nil
                let merged = merge(snapshotsByLimitID, with: found)
                if merged != snapshotsByLimitID {
                    snapshotsByLimitID = merged
                    persist(merged)
                }
            }
            if snapshotsByLimitID.isEmpty && errorMessage == nil {
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
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([String: LimitSnapshot].self, from: data) {
            snapshotsByLimitID = saved
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let saved = try? JSONDecoder().decode(LimitSnapshot.self, from: data) {
            snapshotsByLimitID = [saved.limitID: saved]
        }
    }

    private func persist(_ snapshots: [String: LimitSnapshot]) {
        if snapshots.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }

    private func merge(_ current: [String: LimitSnapshot], with discovered: [String: LimitSnapshot]) -> [String: LimitSnapshot] {
        let cutoff = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        var merged = current.filter { $0.value.capturedAt >= cutoff }
        for (id, snapshot) in discovered {
            if let existing = merged[id], existing.capturedAt >= snapshot.capturedAt { continue }
            merged[id] = snapshot
        }
        return merged
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
