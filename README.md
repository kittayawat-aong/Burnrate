# 🔥 Burnrate

A macOS menu bar app that shows your [Claude Code](https://claude.ai/code) usage at a glance — session %, reset countdown, and token breakdown.

![Burnrate popover](screenshot/SCR-20260630-bplp.png)

---

## Features

- **Menu bar** — flame icon + session % (traffic-light colored) + countdown to reset
- **Popover** — session & weekly progress bars with reset times (day of week), today's token breakdown, account info
- **Notifications** — alert when usage crosses a configurable threshold; works even when the app is in the foreground
- **Persists last fetch** — shows cached values on 429 / offline with a stale warning
- **Refreshes on wake** — polls immediately when the Mac wakes from sleep
- **Settings** — 6-tab window: toggle what shows in the menu bar / popover, adjust poll interval, configure notifications
- **Debug tab** — simulate usage % for testing UI and notifications without burning real quota

## Requirements

- macOS 13 Ventura or later
- [Claude Code](https://claude.ai/code) installed and signed in

## Installation

Build from source:

```bash
git clone https://github.com/yourname/burnrate.git
cd burnrate
xcodebuild -scheme Burnrate -configuration Release -derivedDataPath build/release build
cp -R build/release/Build/Products/Release/Burnrate.app /Applications/
open /Applications/Burnrate.app
```

On first launch macOS may prompt to allow access to the `Claude Code-credentials` Keychain item — choose **Always Allow**.

> **Note:** App Sandbox is disabled so the app can read Claude Code's Keychain entry and `~/.claude/` logs. No data leaves your machine except the usage API call to `api.anthropic.com`.

## How it works

1. Reads `Claude Code-credentials` from Keychain → extracts OAuth access token
2. Calls `GET https://api.anthropic.com/api/oauth/usage` to fetch session & weekly utilization
3. Parses `~/.claude/projects/**/*.jsonl` for today's token counts
4. Reads `~/.claude.json` for account info (email, plan, etc.)

## Settings

| Tab | Options |
|-----|---------|
| General | Launch at login |
| Menu Bar | Show session %, countdown, weekly % |
| Popover | Show account info, weekly usage, token breakdown |
| Notifications | Enable alerts, set threshold % |
| Polling | Poll interval (1–30 min) |
| Debug | Simulate session / weekly % for UI testing |

## Project layout

```
Burnrate/
├── BurnrateApp.swift
├── AppDelegate.swift          # NSStatusItem, NSPopover, polling, wake observer
├── Models/
│   ├── UsageResponse.swift    # defensive parser for /api/oauth/usage
│   ├── AccountInfo.swift      # ~/.claude.json account fields
│   └── TokenSummary.swift
├── Services/
│   ├── KeychainService.swift  # reads Claude Code-credentials
│   ├── UsageAPIService.swift  # OAuth usage endpoint
│   ├── AccountService.swift   # parses ~/.claude.json
│   ├── JournalService.swift   # parses ~/.claude/projects/**/*.jsonl
│   ├── NotificationService.swift
│   └── UsageCache.swift       # UserDefaults persistence
├── ViewModels/
│   ├── UsageViewModel.swift
│   └── AppSettings.swift
├── Views/
│   ├── UsagePopover.swift
│   └── SettingsView.swift
└── Utilities/
    ├── TimeFormatter.swift
    └── UsageColor.swift
```

## Notes

- The `/api/oauth/usage` endpoint is undocumented and may change without notice; the response parser is intentionally defensive about field names.
- App Sandbox must be disabled to access another app's Keychain item and `~/.claude/` — this means the app is not App Store distributable as-is.

## License

MIT
