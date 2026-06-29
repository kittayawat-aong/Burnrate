import Foundation
import ServiceManagement

/// Wraps `SMAppService` to toggle launch-at-login. Requires running from a
/// proper `.app` bundle (see scripts/build_app.sh).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Burnrate: LaunchAtLogin toggle failed: \(error)")
            return false
        }
    }
}
