import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: LimitMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 52)
        monitor = LimitMonitor()
        monitor.onChange = { [weak self] in self?.render() }
        render()
    }

    private func render() {
        guard statusItem != nil, monitor != nil else { return }
        statusItem.length = monitor.sparkSnapshot == nil ? 52 : 96
        statusItem.button?.title = monitor.compactTitle
        statusItem.button?.image = NSImage(systemSymbolName: monitor.statusSymbol, accessibilityDescription: "Codex limits")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if monitor.hasSnapshots {
            for (index, snapshotData) in monitor.sectionSnapshots.enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                add(section: snapshotData.title, snapshot: snapshotData.snapshot, to: menu)
            }
            menu.addItem(.separator())
            if let plan = monitor.generalSnapshot?.planType {
                menu.addItem(disabledItem("Тариф: \(plan.capitalized)"))
            }
            if let mostRecentCapturedAt = monitor.sectionSnapshots.map({ $0.snapshot.capturedAt }).max() {
                menu.addItem(disabledItem("Данные: \(mostRecentCapturedAt.formatted(date: .omitted, time: .shortened))"))
            }
            if monitor.isStale {
                menu.addItem(disabledItem("Сохранённый снимок — откройте Codex для обновления"))
            }
        } else {
            menu.addItem(disabledItem(monitor.errorMessage ?? "Ищу данные Codex…"))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: monitor.isRefreshing ? "Обновление…" : "Обновить сейчас", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !monitor.isRefreshing
        menu.addItem(refresh)

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = monitor.launchAtLogin ? .on : .off
        menu.addItem(login)

        if let error = monitor.errorMessage { menu.addItem(disabledItem(error)) }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить Codex Limits", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func add(section title: String, snapshot: LimitSnapshot, to menu: NSMenu) {
        menu.addItem(disabledItem(title))
        if let plan = snapshot.planType {
            menu.addItem(disabledItem("Тариф: \(plan.capitalized)"))
        }
        menu.addItem(disabledItem("Данные: \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))"))
        if let primary = snapshot.primary { add(window: primary, to: menu) }
        if let secondary = snapshot.secondary { add(window: secondary, to: menu) }
    }

    private func add(window: LimitWindow, to menu: NSMenu) {
        let title: String
        switch window.windowMinutes {
        case 300: title = "5 часов"
        case 10_080: title = "7 дней"
        default: title = "\(window.windowMinutes) мин."
        }
        menu.addItem(disabledItem("\(title): осталось \(window.remainingPercent)%"))
        menu.addItem(disabledItem("Сброс: \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func refreshNow() { monitor.refresh() }
    @objc private func toggleLaunchAtLogin() { monitor.setLaunchAtLogin(!monitor.launchAtLogin) }
}

private final class SingleInstanceGuard {
    private let fileDescriptor: Int32

    init?() {
        let lockFile = FileManager.default.temporaryDirectory.appendingPathComponent("com.codex.limitbar.instance.lock")
        let path = lockFile.path
        let createdDescriptor = path.withCString { pathCString in
            open(pathCString, O_CREAT | O_RDWR, 0o644)
        }

        guard createdDescriptor >= 0 else { return nil }
        fileDescriptor = createdDescriptor

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == -1 {
            close(fileDescriptor)
            return nil
        }
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

@main
@MainActor
enum CodexLimitBarMain {
    private static var singleInstanceGuard: SingleInstanceGuard?
    private static var appDelegate: AppDelegate?

    static func main() {
        guard let guardInstance = SingleInstanceGuard() else { return }
        singleInstanceGuard = guardInstance

        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
