# Thomodoro

A Pomodoro timer for iOS and macOS with music integration, Live Activities, and project tracking.

---

## Features

### Timer
- Configurable work sessions, short breaks, and long breaks
- Optional warm-up period before work sessions begin — a preparation phase that lets you ease into focus before the clock starts
- Automatic phase transitions with audio cues
- Slider to manually scrub through the current phase
- Session checkmarks tracking progress toward the next long break

### Live Activities & Lock Screen
- Lock screen and Dynamic Island timer display on iOS
- Real-time countdown visible without opening the app
- Pause, resume, and skip controls from the lock screen via interactive widgets
- Accurate time restoration when returning from background using SharedState

### Music Integration
- **Spotify** — connect via OAuth PKCE, assign playlists to work and break phases, shuffled playback with random track offset, album artwork display with attribution link
- **Apple Music** — authorize via MusicKit, assign playlists to work and break phases, shuffled playback, artwork display
- Music automatically switches playlist when the timer phase changes
- Playback pauses when the timer is paused and resumes when the timer resumes

### Projects & Statistics
- Create projects with optional emoji labels
- Assign a project to the current session via the project switcher
- Unassigned sessions are tracked as Freestyle
- Milestone progression: 10h, 30h, 50h, 100h, 500h, 1000h, 2000h
- Today and all-time statistics with per-project breakdowns
- iCloud Key-Value sync across devices with automatic migration from UserDefaults

### macOS
- Menu bar app with popover interface
- Auto-opens on launch with retry logic for full-screen space compatibility
- Configurable keep-open behavior for the dropdown
- Notification Center observers for toggle, reset, and skip actions

---

## Requirements

- iOS 17+ / macOS 14+
- Xcode 15+
- Apple Music subscription (for Apple Music integration)
- Spotify Premium (for Spotify integration)
- Spotify developer app registered at developer.spotify.com with redirect URI configured

---

## Configuration

### Spotify
Set your credentials in `SpotifyConfig`:
```swift
static let clientID = "your_client_id"
static let redirectURI = "thomodoro://spotify-callback"
```

Spotify's developer policy limits beta testing to 20 users. For broader distribution, submit your app for Spotify Extended Quota Mode review.

### App Group
The App Group ID is used to share state between the main app and widgets/Live Activities. Update it in `SharedTimerState.swift`:
```swift
static let appGroupID = "group.com.yourteam.thomodoro"
```
Make sure this matches the App Group entitlement in both the main app and widget extension targets.

---

## Architecture

| File | Responsibility |
|------|---------------|
| `TimerViewModel` | Timer logic, phase transitions, music control, Live Activity management, background/foreground restoration |
| `TimerState` | Observable timer state, persistence to UserDefaults, Codable with legacy format migration |
| `SharedTimerState` | App Group shared state for widget and Live Activity synchronization |
| `TimerAttributes` | ActivityKit attributes and content state for Live Activities |
| `SpotifyManager` | Spotify OAuth PKCE flow, playlist fetching, playback control, artwork polling |
| `AppleMusicManager` | MusicKit authorization, playlist fetching, shuffled playback, artwork |
| `NotificationManager` | Local notification scheduling, category/action registration, delegate handling |
| `ProjectManager` | Project CRUD, iCloud KV sync, project selection |
| `StatisticsManager` | Session logging, today/all-time aggregation, project breakdowns |
| `MenuBarManager` | macOS status item, popover lifecycle, full-screen space compatibility |
| `CrashLogger` | Uncaught exception handler, event log, debug report export |

### State Synchronization
When the app backgrounds, the current timer state is written to both `UserDefaults` (via `TimerState`) and the App Group store (via `SharedTimerState`) with a timestamp. On foreground, elapsed time is calculated from the timestamp and subtracted from the stored remaining time. Live Activity visual countdowns are not used for state calculation — `SharedTimerState` is the source of truth.

---

## Privacy

Thomodoro does not collect or transmit any user data. All storage is local to the device or synced privately via iCloud Key-Value Store. No analytics, no tracking.

The privacy policy is hosted at [thomodoroapp.com](https://thomodoroapp.com).
