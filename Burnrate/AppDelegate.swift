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
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    /// Normal poll interval, from user settings (clamped to a sane minimum).
    private var normalInterval: TimeInterval { TimeInterval(max(1, settings.pollIntervalMinutes) * 60) }
    private let backoffInterval: TimeInterval = 10 * 60 // 10 minutes on 429

    func applicationDidFinishLaunching(_ notification: Notification) {
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
                    self?.viewModel.runThresholdCheck()
                }
            }
            .store(in: &cancellables)

        updateStatusItem()
        poll() // initial fetch (also schedules the next poll)
        startDisplayTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        displayTimer?.invalidate()
        popoverTickTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

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
        closePopover()

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Burnrate Settings"
            window.styleMask = [.titled, .closable]
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
        Task { @MainActor in
            let outcome = await viewModel.refresh()
            let next: TimeInterval = (outcome == .rateLimited) ? backoffInterval : normalInterval
            scheduleNext(after: next)
        }
    }

    private func scheduleNext(after interval: TimeInterval) {
        viewModel.setNextUpdate(Date().addingTimeInterval(interval))
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }
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
