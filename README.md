# Notch Island

A NotchNook-style Dynamic Island for the MacBook notch, written in SwiftUI + AppKit.

Hover over the notch and it springs open. While something is "live" (music playing, a timer
running, a charger plugged in, a meeting about to start) the notch widens slightly to show it.

## Features

| Area | What it does |
|---|---|
| **Now playing** | Track, artist, album art, live progress bar, play/pause/skip for **Apple Music**, **Spotify** and **YouTube / YouTube Music** in Safari, Chrome, Arc, Brave or Edge. Equalizer bars + art in the notch while playing. |
| **File shelf** | Drag any file onto the notch to park it. Drag it back out anywhere, double-click to open, right-click for Show in Finder / AirDrop / Remove. "AirDrop All" button. Shelf survives relaunch. |
| **Calendar** | Week strip + the selected day's events from every calendar in macOS Calendar (iCloud, Google, Exchange…). |
| **Live activities** | Countdown timer (1/5/15/25 min) with ring, chime when done. Battery level, charging / unplugged toasts, low-battery (20 %) alert, "meeting in N min" alert 10 min before events. |
| **Extras** | Haptic tap on open, menu-bar item (Open Island, Launch at Login, Quit), works on external displays as a floating pill. |

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (or the Command Line Tools with Swift 5.9+)

## Build & run

```bash
cd notch-island
chmod +x build.sh
./build.sh release --run
```

This produces `build/NotchIsland.app`. Drag it into `/Applications` if you want to use
**Launch at Login**.

> Use `build.sh` rather than `swift run` / running from Xcode directly: Calendar access needs the
> `Info.plist` usage strings, which only exist inside the `.app` bundle. Running the bare binary
> will crash the moment you tap **Allow Calendar Access**.

To work on it in Xcode: `open Package.swift`, edit there, then run `./build.sh debug --run`.

## Permissions (asked the first time)

- **Automation → Music / Spotify** – to read the current track and control playback.
- **Calendars** – tap *Allow Calendar Access* in the Calendar tab.
- **YouTube** – the first time, macOS asks to let Notch Island control your browser. Then turn on
  *Allow JavaScript from Apple Events* once in each browser you use:
  - **Chrome / Brave / Edge / Arc:** View → Developer → Allow JavaScript from Apple Events
  - **Safari:** Settings → Advanced → tick *Show features for web developers*, then
    Develop menu → Allow JavaScript from Apple Events

  This only lets apps you've approved under Automation run scripts in the browser. Firefox isn't
  supported because it has no way for other apps to read its tabs.

Because the app is ad-hoc signed, macOS may forget these after a rebuild. If something stops
working, reset with `tccutil reset AppleEvents com.example.NotchIsland` and
`tccutil reset Calendar com.example.NotchIsland`, then relaunch.

## How it works

```
Sources/NotchIsland
├── App.swift                      entry point, menu-bar item, launch at login
├── NotchWindowController.swift    transparent panel over the notch, hover/drag tracking
├── NotchViewModel.swift           closed / peek / open state, sizes, live-activity alerts
├── Features/
│   ├── MediaController.swift      AppleScript polling of Music & Spotify
│   ├── ShelfStore.swift           parked files (paths in UserDefaults), AirDrop
│   ├── CalendarStore.swift        EventKit
│   ├── BatteryMonitor.swift       IOKit power-source notifications
│   └── TimerActivity.swift        countdown
└── Views/
    ├── NotchShape.swift           animatable notch outline (flared top, rounded bottom)
    ├── NotchRootView.swift        morphing island + file drop target
    ├── PeekView.swift             the "ears" either side of the camera
    ├── ExpandedView.swift         header with tabs, battery, settings
    ├── HomeTab.swift              now playing + timer + power cards
    ├── ShelfTab.swift
    └── CalendarTab.swift
```

- **Notch size** comes from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`, so it matches every notched MacBook exactly.
- **Click-through:** the panel is larger than the island, so it sets `ignoresMouseEvents`
  to `true` everywhere except while the cursor is over the island. Global mouse monitors decide
  when to open (0.12 s hover) and close (0.25 s after leaving). Mouse-move monitoring does
  **not** need Accessibility permission.
- **File drags** are detected by watching the drag pasteboard's `changeCount`, so dragging a file
  toward the notch opens the shelf instantly, while dragging a window past it does nothing.
- **Media:** Apple's private MediaRemote framework is restricted on recent macOS, so this uses
  AppleScript, which is supported and stable. It only talks to players that are already
  running, so it never launches Music on its own.

## Ideas to extend

- Volume / brightness HUD replacement (needs a CGEvent tap + Accessibility permission)
- Clipboard history tab
- Webcam mirror (AVCaptureSession in a small preview)
- Per-app accent colour from album art (average the artwork colours)
