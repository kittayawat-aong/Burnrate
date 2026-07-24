# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Burnrate is a macOS menu bar app (SwiftUI + AppKit, `NSStatusItem`) that shows Claude Code and Codex usage. Claude data comes from local credentials/logs plus an undocumented Anthropic endpoint. Codex data comes from the local `codex app-server` protocol. No backend; everything runs client-side on the user's Mac.

## Build & run

```bash
# Build (Release, matches what Homebrew ships)
xcodebuild -scheme Burnrate -configuration Release -derivedDataPath build/release build

# Install/replace the running app
cp -R build/release/Build/Products/Release/Burnrate.app /Applications/
open /Applications/Burnrate.app

# Debug build via Xcode
open Burnrate.xcodeproj
```

There is no test target in this project (`xcodebuild -list` shows only the `Burnrate` scheme, Debug/Release configs). Verify changes by building and running the app manually — see the `run` skill for driving the actual menu bar app.

**Important:** the real running app the user interacts with is the Release build installed at `/Applications/Burnrate.app`, not the Xcode Debug build/simulator. After making changes the user wants to actually use, rebuild Release and copy it over as above.

## Versioning

- `CURRENT_PROJECT_VERSION` (build number) in `project.pbxproj` — bump on every commit that changes app code.
- `MARKETING_VERSION` — user-controlled; do not bump this yourself unless asked.
- Both appear twice in `project.pbxproj` (Debug and Release configs) — keep them in sync.

## Architecture

Single-target SwiftUI/AppKit app. One external dependency, Alamofire (SPM), for the two HTTP calls (`UsageAPIService`, `WebhookService`). Data flows one way: `AppDelegate` drives polling → `UsageViewModel` (the only `ObservableObject` of substance) fetches from services and republishes `@Published` state → SwiftUI views (`UsagePopover`, `SettingsView`) and the AppKit status item both read from it.

```
Burnrate/
├── BurnrateApp.swift            # @main entry point
├── AppDelegate.swift            # NSStatusItem, NSPopover, polling/timer orchestration, wake observer
├── Models/                      # Codable/plain structs — UsageResponse (defensive API parser), AccountInfo, TokenUsage
├── Services/                    # All I/O lives here; ViewModels never touch Keychain/network/filesystem directly
│   ├── KeychainService.swift      # reads "Claude Code-credentials" from the login Keychain
│   ├── CredentialsCache.swift     # last-known-good credentials, used when a Keychain read fails transiently
│   ├── UsageAPIService.swift      # GET https://api.anthropic.com/api/oauth/usage
│   ├── CodexUsageService.swift    # account/rateLimits/read + account/read over codex app-server stdio
│   ├── CodexUsageCache.swift      # last-known-good Codex usage/account snapshot
│   ├── AccountService.swift       # parses ~/.claude.json for account/plan info
│   ├── JournalService.swift       # parses ~/.claude/projects/**/*.jsonl for today's token counts
│   ├── ClaudeSettingsService.swift# reads/writes ~/.claude/settings.json (e.g. includeCoAuthoredBy)
│   ├── NotificationService.swift  # local UNUserNotificationCenter alerts
│   ├── WebhookService.swift       # POSTs usage JSON to a user-configured URL after each fetch
│   └── UsageCache.swift           # UserDefaults persistence of the last successful fetch (for cold start / offline)
├── ViewModels/
│   ├── UsageViewModel.swift     # @MainActor state machine: refresh(), threshold/reset notification logic
│   └── AppSettings.swift        # all user-facing toggles, UserDefaults-backed, singleton `.shared`
├── Views/                       # UsagePopover.swift, SettingsView.swift (7-tab settings window)
└── Utilities/                   # TimeFormatter, UsageColor, LaunchAtLogin
```

Key mechanics worth knowing before touching polling/notification code:

- **Polling loop** (`AppDelegate.poll()`): refreshes enabled Claude and Codex providers concurrently, then reschedules — normal interval from settings, or a fixed 10-minute backoff on Claude HTTP 429. On success it also arms a one-shot `resetTimer` for the soonest enabled-provider reset.
- **Codex app server**: `CodexUsageService` launches the installed Codex CLI and keeps stdin open until both async response IDs arrive. Do not close stdin immediately: app-server treats EOF as shutdown and may emit only the initialize response.
- **401 handling**: whether re-login is required is decided by the live `/usage` call's response, *not* a locally computed `expiresAt` — Keychain reads can fail transiently even when the token is still valid (see `KeychainService` / `CredentialsCache` fallback).
- **Debug simulation**: `AppSettings.debugSimulate` + `debugSessionPercent`/`debugWeeklyPercent` override the displayed values via `UsageViewModel.effectiveSession`/`effectiveWeekly` without touching real quota or the network fetch — always read through `effective*`, not `session`/`weekly` directly, when rendering UI.
- **Notification dedup**: threshold alerts and reset alerts are keyed by the period's `resetsAt` (`notifiedSessionPeriod`/`notifiedWeeklyPeriod`), truncated to the minute, so each usage period fires at most one alert regardless of poll frequency.
- **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO`) — required to read another app's Keychain item and `~/.claude/`. This is intentional and blocks App Store distribution; don't re-enable it without understanding that tradeoff.

## Data sources (all read-only against the local machine / Anthropic API)

1. Keychain generic-password service `"Claude Code-credentials"` → OAuth access token (JSON: `claudeAiOauth.accessToken`, `.refreshToken`, `.expiresAt` in epoch ms).
2. `GET https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) → session (5h) and weekly (7d) utilization + reset timestamps. Undocumented endpoint — `UsageResponse` parsing is intentionally defensive about field names/shapes.
3. `~/.claude/projects/**/*.jsonl` → per-line `message.usage` token counts, summed for "today" (`JournalService`).
4. `~/.claude.json` → account email/plan (`AccountService`).
5. `~/.claude/settings.json` → read/write for in-app Claude Code settings toggles (`ClaudeSettingsService`).
6. Local `codex app-server --stdio` → Codex account, plan, usage percentages, window durations, and reset timestamps. Burnrate never reads `~/.codex/auth.json`.
