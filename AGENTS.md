# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a near-duplicate of this file (for Claude Code) — keep the two in sync when changing guidance.

## What this is

Burnrate is a macOS menu bar app (SwiftUI + AppKit, `NSStatusItem`) that shows Claude Code and Codex usage. Claude data comes from local credentials/logs plus an undocumented Anthropic endpoint; Codex data comes from the local `codex app-server` protocol. No backend; everything runs client-side.

## Build & run

```bash
# Release build (matches what Homebrew ships)
xcodebuild -scheme Burnrate -configuration Release -derivedDataPath build/release build

# Install/replace the running app
cp -R build/release/Build/Products/Release/Burnrate.app /Applications/
open /Applications/Burnrate.app
```

- No test target exists (`xcodebuild -list` shows only the `Burnrate` scheme). Verify changes by building and running the app manually.
- The app the user actually runs is the Release build at `/Applications/Burnrate.app` — after changes meant for real use, rebuild Release and copy it over as above.

## Toolchain quirks (easy to get wrong)

- **Default actor isolation is MainActor** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` in `project.pbxproj`). New types/functions are MainActor unless explicitly marked `nonisolated`. Services called from background contexts (e.g. `LogService.log`) must opt out explicitly — see `LogService` for the pattern.
- Deployment target is macOS 15.7 (README's "macOS 13" is stale); sandbox is intentionally disabled (see below).
- Two SPM dependencies only: Alamofire (`UsageAPIService`, `WebhookService`) and MQTTNIO (`MQTTService`). Do not add network calls through other means.

## Versioning

- `CURRENT_PROJECT_VERSION` (build number, currently 36) — bump on every commit that changes app code. Appears twice in `project.pbxproj` (Debug + Release); keep in sync.
- `MARKETING_VERSION` (currently 1.0.7) — user-controlled; do not bump unless asked.

## Architecture

Single-target app. Data flows one way: `AppDelegate` drives polling → `UsageViewModel` (main `ObservableObject`) fetches via services and republishes `@Published` state → SwiftUI views and the status item read from it. All I/O lives in `Services/`; ViewModels never touch Keychain/network/filesystem directly.

```
Burnrate/
├── BurnrateApp.swift            # @main
├── AppDelegate.swift            # NSStatusItem, NSPopover, polling/timers, wake + display-sleep observers
├── Models/                      # UsageResponse (defensive API parser), CodexUsage, GLMUsage, AccountInfo, TokenUsage, LogEntry
├── Services/
│   ├── KeychainService.swift    # reads "Claude Code-credentials" via /usr/bin/security (see below)
│   ├── CredentialsCache.swift   # last-known-good credentials
│   ├── UsageAPIService.swift    # GET https://api.anthropic.com/api/oauth/usage
│   ├── CodexUsageService.swift  # account/rateLimits/read + account/read over codex app-server stdio
│   ├── CodexUsageCache.swift    # last-known-good Codex snapshot
│   ├── GLMUsageService.swift    # z.ai monitor API (quota/limit + model-usage) using opencode's saved key
│   ├── GLMUsageCache.swift      # last-known-good GLM snapshot
│   ├── AccountService.swift     # parses ~/.claude.json
│   ├── JournalService.swift     # parses ~/.claude/projects/**/*.jsonl for today's tokens
│   ├── ClaudeSettingsService.swift # reads AND writes ~/.claude/settings.json (autoMode config)
│   ├── MQTTService.swift        # persistent MQTTNIO client, auto-reconnect, subscribes to one topic
│   ├── LogService.swift         # in-app activity log → os.Logger + ~/Library/Logs/Burnrate/ daily files
│   ├── NotificationService.swift
│   ├── WebhookService.swift     # POSTs usage JSON after each successful fetch
│   └── UsageCache.swift         # UserDefaults persistence of last successful fetch
├── ViewModels/                  # UsageViewModel (refresh, notifications), AppSettings (UserDefaults-backed singleton)
├── Views/
│   ├── UsagePopover.swift + Popover/   # popover split into +Header/+UsageSection/+Tokens/+Footer extensions
│   └── SettingsView.swift + Settings/  # sidebar window: General, Display, Notifications, Webhook, MQTT, Advanced, Auto Mode, Logs, About
└── Utilities/                   # TimeFormatter, UsageColor, LaunchAtLogin
```

## Key mechanics

- **Keychain reads** (`KeychainService`): shells out to `/usr/bin/security` instead of in-process `SecItemCopyMatching` — Apple's binary is already in the item's ACL, so the user isn't re-prompted. Cache-first: only live-read when no cached credentials exist. Never consume or write back the refresh token — it's single-use and would invalidate the CLI's copy.
- **401 handling**: decided by the live `/usage` response, never by locally computed `expiresAt` — cache-sourced credentials may be stale, so `UsageViewModel.refresh()` retries with a live Keychain read before declaring re-login needed. A token past its own `expiresAt` skips the network call entirely.
- **Polling** (`AppDelegate.poll()`): refreshes enabled providers concurrently, then reschedules — normal interval from settings, or 10-minute backoff on Claude HTTP 429 (honor `Retry-After` when present). Arms a one-shot `resetTimer` for the soonest reset. Polls are skipped while the display is asleep (`CGDisplayIsAsleep`) and run once on wake.
- **Codex app server**: `CodexUsageService` keeps stdin open until both async response IDs arrive — app-server treats EOF as shutdown. Burnrate never reads `~/.codex/auth.json`.
- **MQTT lifecycle** (`MQTTService`): persistent connection with 5s-delay reconnect; MQTTNIO clients own an event loop and must be `shutdown()` even when the broker closes the connection — retain the client until shutdown finishes. Incoming messages currently only get logged. The MQTT password is stored in UserDefaults plaintext by explicit user choice (avoids Keychain prompts with local brokers) — don't "fix" this to Keychain.
- **Debug simulation**: `AppSettings.debugSimulate` overrides displayed values via `UsageViewModel.effectiveSession`/`effectiveWeekly` — always render through `effective*`, never `session`/`weekly`.
- **Menu bar provider**: `AppSettings.menuBarProvider` selects exactly one compact status display (Claude, ChatGPT/Codex, or GLM). Never append multiple providers to the status title.
- **GLM (z.ai)**: `GLMUsageService` borrows the coding-plan API key read-only from `~/.local/share/opencode/auth.json` (provider ids `zai-coding-plan`, `zai`, …; never written back). The monitor API expects the raw key in `Authorization` — no `Bearer` prefix. Limit windows are encoded as `unit` (3 = hours, 6 = months) + `number`; limits are sorted soonest-reset first so `glmLimits.first` is the session window (same convention as Codex). Off by default (`glmEnabled`) since most installs have no opencode z.ai entry.
- **Notification dedup**: threshold/reset alerts are keyed by the period's `resetsAt` truncated to the minute (`notifiedSessionPeriod`/`notifiedWeeklyPeriod`) — one alert per usage period regardless of poll frequency.
- **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO`) — required to read Claude Code's Keychain item and `~/.claude/`. Intentional; blocks App Store distribution. Don't re-enable.

## Data sources

1. Keychain generic-password service `"Claude Code-credentials"` → OAuth access token (JSON: `claudeAiOauth.accessToken`, `.refreshToken`, `.expiresAt` epoch ms).
2. `GET https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) → session (5h) + weekly (7d) utilization. Undocumented endpoint — `UsageResponse` parsing is intentionally defensive about field names/shapes.
3. `~/.claude/projects/**/*.jsonl` → per-line `message.usage` tokens, summed for today (`JournalService`).
4. `~/.claude.json` → account email/plan (`AccountService`).
5. `~/.claude/settings.json` → read **and written** for Claude Code settings toggles incl. `autoMode` (`ClaudeSettingsService`, Auto Mode tab).
6. Local `codex app-server --stdio` → Codex account, plan, usage windows, resets.
7. `~/.local/share/opencode/auth.json` → z.ai GLM Coding Plan key, then `GET https://api.z.ai/api/monitor/usage/quota/limit` (+ `model-usage` for 24h token totals per model) → credit windows (5h + monthly), plan level, resets. Undocumented monitor API.
