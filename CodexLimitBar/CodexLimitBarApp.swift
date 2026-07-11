import AppKit

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
        statusItem.button?.title = monitor.compactTitle
        statusItem.button?.image = NSImage(systemSymbolName: monitor.statusSymbol, accessibilityDescription: "Codex limits")
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if let snapshot = monitor.snapshot {
            if let primary = snapshot.primary { add(window: primary, to: menu) }
            if let secondary = snapshot.secondary { add(window: secondary, to: menu) }
            menu.addItem(.separator())
            if let plan = snapshot.planType {
                menu.addItem(disabledItem("Тариф: \(plan.capitalized)"))
            }
            menu.addItem(disabledItem("Данные: \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))"))
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

@main
@MainActor
enum CodexLimitBarMain {
    private static var appDelegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
