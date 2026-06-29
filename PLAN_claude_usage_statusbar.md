# Claude Usage — macOS Status Bar App
## Project Planner

---

## Overview

แอป macOS Status Bar ที่แสดง Claude Code usage แบบ real-time โดยดึงข้อมูลจาก Anthropic OAuth API และ local JSONL logs

**Stack:** SwiftUI + AppKit (NSStatusItem)  
**Target:** macOS 13 Ventura ขึ้นไป  
**Auth:** Keychain (`Claude Code-credentials`)

---

## Data Sources

| ข้อมูล | แหล่ง | วิธีดึง |
|---|---|---|
| Session % (5h) | Anthropic API | `GET /api/oauth/usage` |
| Weekly % (7d) | Anthropic API | `GET /api/oauth/usage` |
| Reset time | Anthropic API | `resets_at` field |
| Token breakdown | Local JSONL | `~/.claude/projects/**/*.jsonl` |
| OAuth Token | macOS Keychain | `security find-generic-password` |

---

## Features

### MVP (Phase 1)
- [ ] แสดง session % และ weekly % บน menu bar icon
- [ ] Click เปิด popover แสดงรายละเอียด
  - Session: 37% — resets in 2h30m
  - Weekly: 12% — resets Jul 3
- [ ] Poll ทุก 5 นาที
- [ ] Color indicator: 🟢 <50% / 🟡 50–80% / 🔴 >80%
- [ ] Launch at login

### Phase 2
- [ ] Token breakdown จาก JSONL (input / output / cache)
- [ ] แยกต่อ project
- [ ] Daily/weekly usage chart (SwiftUI Charts)
- [ ] Notification เมื่อเกิน 80%

### Phase 3
- [ ] Token refresh อัตโนมัติเมื่อ accessToken หมดอายุ (ใช้ refreshToken)
- [ ] Support หลาย account

---

## Project Structure

```
ClaudeUsage/
├── ClaudeUsageApp.swift          # @main, NSApplicationDelegate
├── AppDelegate.swift             # NSStatusItem setup
├── Views/
│   ├── StatusBarIcon.swift       # icon + label บน menu bar
│   └── UsagePopover.swift        # popover เมื่อ click
├── Models/
│   ├── UsageResponse.swift       # Codable struct จาก API
│   └── TokenUsage.swift          # struct จาก JSONL
├── Services/
│   ├── KeychainService.swift     # อ่าน OAuth token
│   ├── UsageAPIService.swift     # call /api/oauth/usage
│   └── JournalService.swift      # parse JSONL logs
└── Utilities/
    └── TimeFormatter.swift       # format reset countdown
```

---

## API Contract

### Keychain
```swift
// Service: "Claude Code-credentials"
// Returns JSON:
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "sk-ant-ort01-...",
    "expiresAt": 1782756662774
  }
}
```

### OAuth Usage Endpoint
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
```

```swift
// Response fields ที่ใช้:
struct UsageResponse: Codable {
    let fiveHour: UsagePeriod     // session
    let sevenDay: UsagePeriod     // weekly
}

struct UsagePeriod: Codable {
    let utilization: Double       // 0–100
    let resetsAt: String          // ISO 8601
}
```

---

## Polling Strategy

```
Poll interval: 5 นาที (ระวัง 429)
On 429: backoff 10 นาที
On token expired (401): refresh token แล้ว retry
Cache: in-memory เท่านั้น
```

---

## UI Design

### Menu Bar Icon
```
[████░░░░] 37%
```
หรือแบบย่อ: `⚡37% · 📅12%`

### Popover (click)
```
┌─────────────────────────┐
│  Claude Usage           │
├─────────────────────────┤
│  Session (5h)           │
│  ████████░░░░  37%      │
│  Resets in 2h 30m       │
│                         │
│  Weekly (7d)            │
│  ███░░░░░░░░░  12%      │
│  Resets Jul 3, 5am      │
├─────────────────────────┤
│  Last updated: 10:42 AM │
└─────────────────────────┘
```

---

## Implementation Steps

### Step 1 — Setup Project
1. สร้าง Xcode project → macOS App → SwiftUI
2. ปิด main window (Info.plist: `Application is agent = YES`)
3. เพิ่ม `NSStatusItem` ใน AppDelegate

### Step 2 — Keychain Service
1. อ่าน `Claude Code-credentials` จาก Keychain
2. Parse JSON → ได้ `accessToken` + `expiresAt`
3. เช็ค expiry ก่อน call API

### Step 3 — API Service
1. `URLSession` call `/api/oauth/usage`
2. Decode `UsageResponse`
3. Handle 429 → backoff
4. Handle 401 → (Phase 3) refresh token

### Step 4 — Status Bar UI
1. `NSStatusItem` + `NSStatusBarButton`
2. Label แสดง `⚡37%`
3. Color ตาม threshold

### Step 5 — Popover
1. `NSPopover` + SwiftUI `UsagePopover` view
2. Progress bar + countdown timer
3. Toggle เปิด/ปิดเมื่อ click

### Step 6 — Timer & Polling
1. `Timer.scheduledTimer` ทุก 5 นาที
2. `@Published` ใน `UsageViewModel` → UI update อัตโนมัติ

---

## Notes

- endpoint `/api/oauth/usage` เป็น **undocumented** อาจเปลี่ยนได้
- ถ้า 429 บ่อย ให้เพิ่ม interval เป็น 10 นาที
- `expiresAt` เป็น Unix milliseconds
- Token refresh ยังไม่ทำใน MVP — ถ้า expire ให้แจ้ง user login ใหม่ผ่าน Claude Code
