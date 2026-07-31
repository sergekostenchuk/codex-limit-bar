import Foundation

@MainActor
final class ResetRadarMonitor {
    private(set) var forecast: ResetRadarForecast?
    private(set) var isRefreshing = false
    private(set) var isEnabled: Bool
    private(set) var lastUpdatedAt: Date?
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?

    private let engine: ResetRadarEngine
    private let client: OpenAIStatusClient
    private var incidents: [RadarStatusIncident]
    private var timer: DispatchSourceTimer?
    private var refreshTask: Task<Void, Never>?
    private let defaultsKey = "resetRadarStatusIncidents"
    private let updatedAtDefaultsKey = "resetRadarUpdatedAt"
    private let enabledDefaultsKey = "resetRadarEnabled"

    init(
        engine: ResetRadarEngine = ResetRadarEngine(),
        client: OpenAIStatusClient = OpenAIStatusClient()
    ) {
        self.engine = engine
        self.client = client
        incidents = Self.restoreIncidents(key: defaultsKey)
        isEnabled = UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
        lastUpdatedAt = UserDefaults.standard.object(forKey: updatedAtDefaultsKey) as? Date
        recompute()

        guard isEnabled, !Self.isRunningTests else { return }
        startTimer()
        refresh()
    }

    func refresh() {
        guard isEnabled, !isRefreshing else { return }
        isRefreshing = true
        onChange?()

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await client.fetchIncidents()
                guard isEnabled, !Task.isCancelled else { return }
                let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
                incidents = fetched.filter { $0.mostRecentDate >= cutoff }
                lastUpdatedAt = Date()
                errorMessage = nil
                persist()
            } catch {
                if !Task.isCancelled {
                    errorMessage = "OpenAI Status временно недоступен"
                }
            }
            isRefreshing = false
            recompute()
            onChange?()
            refreshTask = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledDefaultsKey)

        if enabled {
            errorMessage = nil
            recompute()
            if !Self.isRunningTests {
                startTimer()
                refresh()
            }
        } else {
            timer?.cancel()
            timer = nil
            refreshTask?.cancel()
            refreshTask = nil
            isRefreshing = false
            forecast = nil
            errorMessage = nil
            onChange?()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 15 * 60, repeating: 15 * 60, leeway: .seconds(60))
        source.setEventHandler { [weak self] in self?.refresh() }
        source.resume()
        timer = source
    }

    private func recompute(now: Date = Date()) {
        forecast = isEnabled ? engine.forecast(now: now, incidents: incidents) : nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(incidents) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(lastUpdatedAt, forKey: updatedAtDefaultsKey)
    }

    private static func restoreIncidents(key: String) -> [RadarStatusIncident] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let restored = try? JSONDecoder().decode([RadarStatusIncident].self, from: data)
        else { return [] }
        return restored
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
