# Thomodoro — Pomodoro Timer for macOS

Thomodoro is a macOS menu bar Pomodoro timer built for writers, students, and anyone who wants structure in their work or study sessions.

## Origin

My sister tried every Pomodoro app she could find — BeFocused Pro, group sprint sessions on YouTube, dedicated timer apps. None of them solved two specific problems she had: there was no way to ease into a session with a warmup period before the work timer started, and managing music separately meant losing the audio cue that told her whether she was in work or break mode.

I built Thomodoro to solve both. The warmup phase gives her time to settle before the clock starts counting down. The music integration plays different playlists for work and break phases automatically, so the music itself becomes the signal.

## Features

- **Warmup phase** — optional preparation period before the work session begins, implemented as an initial FSM state that bypasses the session counter
- **Spotify and Apple Music integration** — automatically switches playlists between work and break phases
- **Menu bar native** — lives in the menu bar, out of the way until you need it
- **Project tracking** — log work sessions against projects and track progress through milestones (10h, 30h, 50h, 100h, 500h, 1000h, 2000h)
- **Statistics** — view session history and time logged per project
- **macOS notifications** — notified when a phase completes even when the popover is closed

## Architecture

Thomodoro is a macOS-only app. After prototyping both iOS and macOS versions, the menu bar layout better suited the use case — it stays accessible without requiring a window to be managed, and hides cleanly when not needed.

### Separation of Concerns

The codebase is organised around single-responsibility classes:

**`TimerEngine`** owns all timer logic — the countdown, phase sequencing, and session tracking. It has no knowledge of the UI, music, or notifications. Changes to timer behaviour are isolated to one file and feed cleanly into `TimerViewModel`.

**`TimerViewModel`** coordinates between the engine, music, and notifications. It owns the `@Published` state that the views observe, and exposes a simple interface to the UI — `toggleTimer()`, `skipToNext()`, `reset()`. All business logic is delegated to `TimerEngine` and `MusicCoordinator`.

**`MusicCoordinator`** routes playback commands to whichever music service is active. It calls `play()`, `pause()`, and `playPlaylist()` through the `MusicPlayerService` protocol without knowing whether it's talking to Spotify or Apple Music.

**`StatisticsManager`** and **`ProjectManager`** are independent of the timer. They handle persistence and can be reasoned about in isolation.

### Finite State Machine

Phase sequencing is modelled as a finite state machine. The four states — `warmup`, `work`, `shortBreak`, `longBreak` — are defined as an enum, and valid transitions are defined explicitly on the state itself:
```swift
func next(sessionsCompleted: Int, sessionsUntilLong: Int) -> TimerPhase
```

This guarantees invalid transitions are impossible by construction. The session counter extends the basic FSM to handle periodic long breaks — a pattern that maps to a Moore machine in automata theory, where output depends only on the current state. The zero case (`sessionsUntilLong == 0`) is explicitly guarded to prevent division by zero, which tests verify.

### Protocol-Oriented Music Integration

Both `SpotifyManager` and `AppleMusicManager` conform to `MusicPlayerService`:
```swift
protocol MusicPlayerService {
    var isPlaying: Bool { get }
    var currentArtworkURL: URL? { get }
    func play()
    func pause()
    func playPlaylist(id: String) async
}
```

For an app with two music services this protocol isn't strictly necessary — the coordinator could reference both managers directly. It's included to demonstrate the Dependency Inversion Principle: `MusicCoordinator` depends on the abstraction, not the concrete implementations. Adding a third service would require conforming a new manager to the protocol with no changes to the coordinator.

### Spotify Authentication — OAuth 2.0 PKCE

Spotify integration uses the OAuth 2.0 PKCE (Proof Key for Code Exchange) flow, implemented from scratch without a third-party library:

1. A cryptographically random code verifier is generated using `SecRandomCopyBytes`
2. A SHA-256 code challenge is derived from the verifier using CryptoKit
3. A random state parameter is generated to prevent CSRF attacks
4. The user authenticates in their browser and Spotify redirects back with an authorisation code
5. The code is exchanged for an access token, verified against the original state parameter
6. Tokens are refreshed automatically when they expire within 5 minutes

This means the app never handles the user's Spotify password and access tokens are short-lived. The implementation validates the state parameter on every redirect to prevent man-in-the-middle attacks.

Playback state — current track, artwork, and play/pause status — is kept in sync by polling the Spotify API every 3 seconds using a `Timer` on the main run loop, with results dispatched back to the main actor for UI updates.

### Persistence

Session and project data is persisted using UserDefaults with iCloud Key-Value sync. SwiftData and Core Data were evaluated but the data model is a flat structure — projects with associated sessions — that doesn't require an object graph database. Core Data would add managed object contexts, migration handling, and relationship graph traversal for no practical benefit at this data scale. The right persistence layer is the simplest one that meets the requirements.

### Design Patterns

The app uses several patterns that interact to form a clean architecture. MVVM separates views from business logic — views observe `TimerViewModel` and call methods on it, with no logic of their own. The FSM sits inside `TimerEngine` and drives phase transitions, with `TimerViewModel` reacting to phase completion callbacks to trigger music changes and notifications. The `MusicPlayerService` protocol applies dependency inversion so `MusicCoordinator` can route to either service without branching on type. Shared managers — `StatisticsManager`, `ProjectManager`, `NotificationManager` — use the singleton pattern since they manage global state that multiple parts of the app need to read and write. Combine's `objectWillChange` propagates timer state changes from `TimerEngine` through `TimerViewModel` to the UI.

## Technical Stack

- Swift, SwiftUI, Combine
- MusicKit (Apple Music integration)
- Spotify Web API with OAuth 2.0 PKCE flow
- CryptoKit for PKCE code challenge generation
- UserNotifications for phase completion alerts
- iCloud Key-Value storage for cross-device sync

## Project Structure
```
Thomodoro/
├── App/              # Entry point and app state
├── Timer/            # TimerEngine, TimerViewModel, TimerState, TimerPhase
├── Music/            # MusicCoordinator, MusicPlayerService, SpotifyManager, AppleMusicManager
├── Projects/         # Project model and ProjectManager
├── Statistics/       # StatisticsManager
├── Notifications/    # NotificationManager
├── Views/            # SwiftUI views
└── Support/          # Colors, menu bar, notification names
```

## Configuration

### Spotify
Set your credentials in `SpotifyConfig.swift`:
```swift
static let clientID = "your_client_id"
static let redirectURI = "thomodoro://spotify-callback"
```

Spotify's developer policy limits beta testing to 20 users. For broader distribution, submit your app for Spotify Extended Quota Mode review.

## Development

Built with Xcode. Requires macOS 14+.

Spotify integration requires a Spotify Premium account and a registered Spotify Developer application. Apple Music integration requires an Apple Music subscription.

## Privacy

Thomodoro does not collect or transmit any user data. All storage is local to the device or synced privately via iCloud Key-Value Store. No analytics, no tracking.
