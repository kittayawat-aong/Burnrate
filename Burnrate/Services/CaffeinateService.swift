import Foundation
import Combine
import IOKit.pwr_mgt

/// What a keep-awake session prevents.
enum CaffeinateMode: String, CaseIterable, Identifiable {
    /// Mac stays awake; the display may still turn off.
    case system
    /// Mac and display both stay on.
    case display

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Keep Mac awake (display can sleep)"
        case .display: return "Keep Mac and display awake"
        }
    }

    fileprivate var assertionType: String {
        switch self {
        case .system: return kIOPMAssertionTypePreventUserIdleSystemSleep as String
        case .display: return kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }
    }
}

/// Keeps the Mac awake like `caffeinate`, using an IOKit power assertion
/// instead of a child process. The system drops the assertion automatically
/// if Burnrate quits or crashes, so nothing can be left running.
/// Closing the lid still sleeps the Mac (unless in clamshell mode with an
/// external display and power) — a macOS limit that `caffeinate` shares.
final class CaffeinateService: ObservableObject {
    static let shared = CaffeinateService()

    /// Durations offered in the UI; nil means until turned off.
    static let durations: [TimeInterval?] = [nil, 30 * 60, 60 * 60, 2 * 60 * 60, 4 * 60 * 60]

    @Published private(set) var isActive = false
    /// When the session turns itself off; nil while inactive or indefinite.
    @Published private(set) var endsAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var expiryTimer: Timer?
    private var activeMode: CaffeinateMode?

    private init() {}

    /// Starts (or restarts) a keep-awake session.
    func start(duration: TimeInterval?, mode: CaffeinateMode) {
        releaseAssertion()
        guard createAssertion(mode: mode) else {
            stop()
            return
        }
        isActive = true
        activeMode = mode

        expiryTimer?.invalidate()
        expiryTimer = nil
        if let duration {
            let end = Date().addingTimeInterval(duration)
            endsAt = end
            let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    LogService.shared.log(.info, .caffeinate, "Keep-awake timer finished")
                    self?.stop()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        } else {
            endsAt = nil
        }
        LogService.shared.log(.info, .caffeinate, "Keep-awake on (\(mode.rawValue), \(Self.label(for: duration)))")
    }

    func stop() {
        let wasActive = isActive
        releaseAssertion()
        expiryTimer?.invalidate()
        expiryTimer = nil
        isActive = false
        endsAt = nil
        activeMode = nil
        if wasActive {
            LogService.shared.log(.info, .caffeinate, "Keep-awake off")
        }
    }

    /// Applies a mode change to a running session without touching its timer.
    func updateMode(_ mode: CaffeinateMode) {
        guard isActive, mode != activeMode else { return }
        releaseAssertion()
        if createAssertion(mode: mode) {
            activeMode = mode
            LogService.shared.log(.info, .caffeinate, "Keep-awake mode changed to \(mode.rawValue)")
        } else {
            stop()
        }
    }

    static func label(for duration: TimeInterval?) -> String {
        guard let duration else { return "Until turned off" }
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private func createAssertion(mode: CaffeinateMode) -> Bool {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            mode.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Burnrate keep-awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            LogService.shared.log(.error, .caffeinate, "Could not create power assertion (IOReturn \(result))")
            return false
        }
        assertionID = id
        return true
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}
