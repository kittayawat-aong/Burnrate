# Burnrate

A macOS status bar app that shows your Claude Code usage in real time. It reads
the OAuth token Claude Code stores in your Keychain, polls Anthropic's
(undocumented) `/api/oauth/usage` endpoint, and parses local JSONL logs for a
token breakdown.

> Built per `PLAN_claude_usage_statusbar.md`.

## Requirements

- macOS 13 Ventura or later
- Xcode
- Claude Code logged in (so credentials exist in the Keychain under the
  `Claude Code-credentials` service)

## Build & run

Open `Burnrate.xcodeproj` in Xcode and press **Run** (⌘R), or from the CLI:

```bash
xcodebuild -project Burnrate.xcodeproj -scheme Burnrate -configuration Release build
```

The app is a menu-bar agent (`LSUIElement = YES`) — it has no Dock icon and no
main window; look for the icon in the menu bar.

> **App Sandbox is disabled** for this target. It must be: a sandboxed app
> cannot read Claude Code's Keychain item (it belongs to another app's keychain
> group) and cannot read `~/.claude/projects/**` (the sandbox redirects the home
> directory to a private container). This is fine for a personal utility but
> means it is not App Store distributable as-is.

On first launch macOS may prompt to allow access to the
`Claude Code-credentials` Keychain item — choose **Always Allow**.

## What you see

Menu bar: `⚡37% 📅12%` — session (5h) and weekly (7d) utilization, colored
🟢 `<50%` / 🟡 `50–80%` / 🔴 `>80%`.

Click the icon for a popover with progress bars, reset countdowns, today's
token breakdown (input / output / cache), a **Launch at login** toggle, a
manual refresh, and quit.

## Behavior

- Polls every **5 minutes**; on HTTP `429` it backs off to **10 minutes**.
- On `401` / expired token it shows a "re-login via Claude Code" message
  (automatic token refresh is a future phase).
- Sends a notification when a window exceeds **80%**.
- All caching is in-memory only.

## Project layout

```
Burnrate/
├── BurnrateApp.swift          # @main, NSApplicationDelegateAdaptor
├── AppDelegate.swift          # NSStatusItem + NSPopover + polling
├── Models/
│   ├── UsageResponse.swift    # flexible parse of /api/oauth/usage
│   └── TokenUsage.swift       # token summary model
├── Services/
│   ├── KeychainService.swift  # reads Claude Code-credentials
│   ├── UsageAPIService.swift  # calls the OAuth usage endpoint
│   └── JournalService.swift   # parses ~/.claude/projects/**/*.jsonl
├── ViewModels/
│   └── UsageViewModel.swift   # @MainActor ObservableObject
├── Views/
│   └── UsagePopover.swift     # SwiftUI popover content
└── Utilities/
    ├── TimeFormatter.swift    # reset countdown formatting
    ├── UsageColor.swift       # traffic-light thresholds
    └── LaunchAtLogin.swift    # SMAppService wrapper
```

## Notes

- The `/api/oauth/usage` endpoint is undocumented and may change; parsing is
  intentionally defensive about field names.
- `expiresAt` from the Keychain is Unix milliseconds.
