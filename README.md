<p align="center">
  <img src="docs/images/app-icon.png" width="128" height="128" alt="BinauralEngine icon">
</p>

# BinauralEngine

A native macOS menu bar app that generates pure binaural beats and experimental tones for focus, relaxation, creativity, and sleep. No music, no samples — just real-time synthesized audio backed by brainwave entrainment research.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

<p align="center">
  <img src="docs/images/screenshot-v2.png" width="320" alt="BinauralEngine screenshot — Binaural tab">
</p>

## What It Does

BinauralEngine sits in your menu bar and produces stereo binaural beats — a slightly different frequency in each ear that your brain perceives as a rhythmic pulse. Different pulse frequencies target different mental states.

### Binaural Tab

Classic binaural beats with adjustable carrier frequency:

| Preset | Beat Frequency | Brainwave Band | State |
|--------|---------------|----------------|-------|
| Focus | 40 Hz | Gamma | Deep concentration |
| Energize | 20 Hz | High Beta | Alertness & energy |
| Flow | 14 Hz | Beta | Active thinking |
| Calm | 10 Hz | Alpha | Relaxed alertness |
| Dream | 6 Hz | Theta | Creativity & meditation |
| Sleep | 2 Hz | Delta | Deep sleep |

### Experimental Tab

Seven additional tone modes beyond classic binaural beats, each synthesized in real time:

| Mode | Technique | What It Does |
|------|-----------|--------------|
| Isochronal | Pulsed tone | Rhythmic on/off gating at selectable Hz (4/6/10/14/40) — no headphones needed |
| Pink Noise | Voss-McCartney | Equal energy per octave — masks distractions like steady rain |
| Brown Noise | Leaky integrator | Deep low-frequency rumble — warm and enveloping |
| Crystal Bowl | Modal cluster synthesis | Multi-bowl 432 Hz sound bath from spectral analysis of real singing bowls |
| Heart Coherence | AM carrier | 0.1 Hz breathing-guide pulse — breathe with the swell |
| ADHD Power | Multi-partial drone | Deep drone with sharp transient swells and fast pulse — holds restless attention |
| Brain Massage | Multi-layer hemi-sync | Three binaural beat layers (theta + alpha) with isochronic modulation — creates a moving sensation through the mind |

**Crystal Bowl** offers three patterns (Relax, Heal, Meditate), each derived from spectral analysis of real crystal singing bowl recordings. **ADHD Power** has two speed variations (Steady Pace and Slow). **Brain Massage** requires headphones for the full hemi-sync effect.

## Features

- **Pure tones only** — mathematically generated sine waves and noise, no samples or music
- **Two-tab interface** — classic binaural beats and experimental tone modes
- **Menu bar native** — no dock icon, lives in your status bar
- **System integration** — works with macOS Now Playing, media keys, and AirPods controls
- **Session timers** — 15m, 30m, 45m, 1h, or 8h sessions
- **Carrier tuning** — adjustable carrier frequency (20–500 Hz) to find your sweet spot
- **Cross-tab playback** — audio continues when switching between tabs
- **Preset switching** — next/prev track controls cycle through presets
- **Now Playing artwork** — per-mode colored thumbnails in Control Center

## Requirements

- macOS 13 (Ventura) or later
- Headphones recommended (required for binaural beats and Brain Massage)

## Build & Run

```bash
git clone https://github.com/emil-edilersky/BinauralEngine.git
cd BinauralEngine
./run.sh
```

`run.sh` builds via Swift Package Manager and wraps the binary in a `.app` bundle (required for MenuBarExtra). The app appears in your menu bar — click the waveform icon to open.

To build manually:

```bash
swift build
```

> **Note:** Running the bare binary (`swift run` or `.build/.../BinauralEngine`) won't work because SwiftUI's `MenuBarExtra` requires a proper `.app` bundle to register with the window server.

## How It Works

Two sine waves at slightly different frequencies are played — one in each ear. Your auditory brainstem creates an interference pattern perceived as a pulsing "beat" at the difference frequency. This may entrain brainwaves toward that frequency (the **frequency following response**).

The carrier frequency (default 100 Hz) determines the base tone you hear. The beat frequency is the difference between left and right channels. Research suggests carriers in the 100–500 Hz range work best for perceiving binaural beats (Oster, 1973; Licklider, 1950).

The experimental modes use different synthesis techniques — isochronal pulsing, noise shaping, additive modal synthesis (crystal bowls), amplitude modulation (heart coherence), multi-partial drones (ADHD Power), and multi-layer binaural beating (Brain Massage).

For a deeper dive, see [docs/why-it-works.md](docs/why-it-works.md).

## Architecture

```
Sources/
├── BinauralEngineApp.swift           # @main, MenuBarExtra, AppDelegate
├── Models/
│   ├── AppState.swift                # Central state coordinator
│   ├── Preset.swift                  # Binaural preset definitions & session durations
│   ├── ExperimentalMode.swift        # Experimental mode enums & crystal bowl data
│   └── SessionTimer.swift            # Countdown timer
├── Services/
│   ├── ToneGenerator.swift           # AVAudioEngine binaural beat generation
│   ├── ExperimentalToneGenerator.swift # AVAudioEngine experimental tone synthesis
│   └── NowPlayingService.swift       # MPNowPlayingInfoCenter integration
├── Views/
│   └── MenuBarView.swift             # SwiftUI popover UI (two-tab layout)
└── Resources/
    └── Info.plist
```

Key technical choices:
- **AVAudioSourceNode** render callback for sample-accurate sine wave generation
- **UnsafeMutablePointer** for lock-free communication with the real-time audio thread
- **Per-sample gain smoothing** for click-free fade in/out
- **Combine pipelines** for reactive carrier/preset/mode switching
- **Modal cluster synthesis** for crystal bowls — frequencies from spectral analysis of real recordings
- **ZStack-based tab layout** to prevent MenuBarExtra popover dismissal on content changes

## License

MIT License. See [LICENSE](LICENSE).
