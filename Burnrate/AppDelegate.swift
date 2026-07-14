import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let viewModel = UsageViewModel()
    private let settings = AppSettings.shared

    private var pollTimer: Timer?
    private var displayTimer: Timer?
    private var popoverTickTimer: Timer?
    private var resetTimer: Timer?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    /// True while the display is off (manual display sleep, full system
    /// sleep, or a dark wake — which by definition never turns the screen
    /// back on). Used to skip poll() entirely rather than attempt a fetch
    /// that's likely to hit a Keychain "no UI possible" failure.
    private var isDisplayAsleep = false

    /// Set when a scheduled poll fired while the display was asleep and was
    /// skipped, so the data can refresh immediately on display wake instead
    /// of waiting out the rest of the poll interval.
    private var didSkipPollWhileAsleep = false

    /// Normal poll interval, from user settings (clamped to a sane minimum).
    private var normalInterval: TimeInterval { TimeInterval(max(1, settings.pollIntervalMinutes) * 60) }
    private let backoffInterval: TimeInterval = 10 * 60 // fallback on 429 when the server gives no Retry-After
    private let maxBackoffInterval: TimeInterval = 60 * 60 // never wait longer than this, however large Retry-After is
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogService.shared.log(.info, .ui, "App launched (\(AppInfo.version))")

        // Menu-bar-only agent: no Dock icon, even if Info.plist isn't set.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()

        viewModel.onUpdate = { [weak self] in
            self?.updateStatusItem()
        }

        // Show notifications even while Burnrate is the active app, then ask
        // for permission up front.
        UNUserNotificationCenter.current().delegate = self
        NotificationService.requestAuthorization()

        // React to display/preference changes: redraw the menu bar and
        // re-evaluate notification thresholds (so the debug simulator alerts).
        settings.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)

        updateStatusItem()
        poll() // initial fetch (also schedules the next poll)
        startDisplayTimer()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogService.shared.log(.info, .ui, "App terminating")
        pollTimer?.invalidate()
        displayTimer?.invalidate()
        popoverTickTimer?.invalidate()
        resetTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    @objc private func didWakeFromSleep() {
        LogService.shared.log(.info, .polling, "Woke from sleep — refreshing immediately")
        // Cancel whatever stale timer remained and fetch immediately.
        pollTimer?.invalidate()
        poll()
    }

    @objc private func screensDidSleep() {
        isDisplayAsleep = true
        LogService.shared.log(.debug, .polling, "Display asleep — polls will be skipped until wake")
    }

    @objc private func screensDidWake() {
        isDisplayAsleep = false
        if didSkipPollWhileAsleep {
            LogService.shared.log(.info, .polling, "Display woke — running the poll that was skipped during display sleep")
            pollTimer?.invalidate()
            poll()
        } else {
            LogService.shared.log(.debug, .polling, "Display woke")
        }
    }

    /// Re-renders the menu bar every minute so the reset countdown ticks down
    /// between network polls (cheap — no fetch).
    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItem()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = flameIcon()
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.title = "…"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    /// The "burn" brand icon shown before the usage numbers.
    private func flameIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(paletteColors: [.systemOrange]))
        let image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Burnrate")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let content = UsagePopover(
            viewModel: viewModel,
            settings: settings,
            onRefresh: { [weak self] in self?.poll() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: content)
    }

    // MARK: - Status item rendering

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        // A leading space gives the flame icon a little breathing room.
        let title = NSMutableAttributedString(string: " ")

        if let session = viewModel.effectiveSession {
            // Session: percentage (traffic-light colored) and/or reset countdown.
            if settings.menuBarShowSession {
                title.append(segment("\(Int(session.utilization))%", color: UsageColor.nsColor(for: session.utilization)))
            }
            if settings.menuBarShowCountdown, let resetsAt = session.resetsAt {
                let prefix = settings.menuBarShowSession ? " · " : ""
                title.append(segment(prefix + TimeFormatter.compactCountdown(to: resetsAt), color: .secondaryLabelColor))
            }
        }

        if settings.menuBarShowWeekly, let weekly = viewModel.effectiveWeekly {
            if title.length > 1 { title.append(NSAttributedString(string: "  ")) }
            title.append(segment("📅", color: .secondaryLabelColor))
            title.append(segment("\(Int(weekly.utilization))%", color: UsageColor.nsColor(for: weekly.utilization)))
        }

        // Nothing to show (no data yet, or all toggles off with no data).
        if title.length <= 1 {
            if viewModel.effectiveSession == nil && viewModel.effectiveWeekly == nil {
                let symbol = viewModel.errorMessage != nil && !viewModel.isLoading ? "⚠︎" : "…"
                title.append(segment(symbol, color: .secondaryLabelColor))
            }
        }

        button.attributedTitle = title
        button.toolTip = tooltip()
    }

    private func segment(_ string: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.menuBarFont(ofSize: 0)
            ]
        )
    }

    private func tooltip() -> String {
        var lines = ["Burnrate — Claude usage"]
        if let s = viewModel.session {
            lines.append("Session (5h): \(Int(s.utilization))%")
        }
        if let w = viewModel.weekly {
            lines.append("Weekly (7d): \(Int(w.utilization))%")
        }
        if let error = viewModel.errorMessage {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Popover toggle

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        LogService.shared.log(.debug, .ui, "Popover shown")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Let the popover surface over a fullscreen app's Space instead of
        // just switching to the desktop Space without showing anything.
        if let window = popover.contentViewController?.view.window {
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.makeKey()
        }

        // Tick the popover every second so countdowns update live while open.
        // Added in .common mode so it keeps firing during UI tracking.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        popoverTickTimer = timer

        // Close the popover when the user clicks elsewhere.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        popoverTickTimer?.invalidate()
        popoverTickTimer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Settings window

    private func openSettings() {
        LogService.shared.log(.debug, .ui, "Settings window opened")
        closePopover()

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Burnrate Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.minSize = NSSize(width: 460, height: 360)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    // MARK: - Polling

    private func poll() {
        guard !isRefreshing else {
            LogService.shared.log(.debug, .polling, "Refresh already in progress — ignoring duplicate poll() call")
            return
        }
        guard !isDisplayAsleep else {
            // Almost certainly a dark wake: the CPU briefly woke to run
            // timers like this one but the screen never turned back on. A
            // live Keychain read would fail here anyway (macOS blocks it
            // with "no UI possible"), so skip the fetch rather than burn a
            // request on a call likely to fail. didWakeFromSleep() will
            // trigger an immediate poll once a real wake happens.
            LogService.shared.log(.debug, .polling, "Skipping poll — display is asleep")
            didSkipPollWhileAsleep = true
            scheduleNext(after: normalInterval)
            return
        }
        didSkipPollWhileAsleep = false
        isRefreshing = true
        Task { @MainActor in
            defer { isRefreshing = false }
            let outcome = await viewModel.refresh()
            let next: TimeInterval
            if case .rateLimited(let retryAfter) = outcome {
                next = min(max(retryAfter ?? backoffInterval, backoffInterval), maxBackoffInterval)
                LogService.shared.log(.warning, .polling, "Backing off to \(Int(next / 60)) minutes after 429")
            } else {
                next = normalInterval
            }
            scheduleNext(after: next)
            if outcome == .success {
                scheduleResetTimer()
            }
        }
    }

    /// Fires a one-shot timer exactly when the soonest period resets,
    /// so the data refreshes right at the boundary instead of waiting
    /// for the next regular poll interval.
    private func scheduleResetTimer() {
        resetTimer?.invalidate()
        resetTimer = nil

        let dates = [viewModel.session?.resetsAt, viewModel.weekly?.resetsAt].compactMap { $0 }
        guard let soonest = dates.min(), soonest.timeIntervalSinceNow > 0 else { return }

        LogService.shared.log(.debug, .polling, "Reset timer armed for \(Self.logFormatter.string(from: soonest)) (in \(Int(soonest.timeIntervalSinceNow))s)")
        resetTimer = Timer(fire: soonest, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(resetTimer!, forMode: .common)
    }

    private func scheduleNext(after interval: TimeInterval) {
        let next = Date().addingTimeInterval(interval)
        viewModel.setNextUpdate(next)
        LogService.shared.log(.debug, .polling, "Next poll scheduled for \(Self.logFormatter.string(from: next)) (in \(Int(interval))s)")
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    private static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Present banners/sound even when Burnrate is the foreground app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
