import Foundation
import Combine
import AppKit

/// Central app state coordinating tone generation, session timing, and Now Playing.
///
/// This is the single source of truth for the app's state. The UI observes it,
/// and it orchestrates the ToneGenerator, SessionTimer, and NowPlayingService.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var selectedPreset: Preset = .focus
    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false

    /// Carrier frequency (Hz) — adjustable per user preference.
    /// Default is 200 Hz (Oster Curve optimal). Range: 100–500 Hz.
    @Published var carrierFrequency: Double = 100.0

    // MARK: - Services

    let sessionTimer = SessionTimer()
    private let toneGenerator = ToneGenerator()
    private let nowPlayingService = NowPlayingService()

    private var timerCancellable: AnyCancellable?
    private var carrierCancellable: AnyCancellable?
    private var presetCancellable: AnyCancellable?
    private var timerForwardCancellable: AnyCancellable?

    /// Computed left/right frequencies based on carrier + preset beat
    var leftFrequency: Double { carrierFrequency }
    var rightFrequency: Double { carrierFrequency + selectedPreset.beatFrequency }

    // MARK: - Initialization

    func initialize() {
        // Forward SessionTimer changes so SwiftUI redraws when timer ticks
        timerForwardCancellable = sessionTimer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        // Wire up Now Playing play/pause to our toggle
        nowPlayingService.onPlayPause = { [weak self] in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
        }
        nowPlayingService.onNextTrack = { [weak self] in
            Task { @MainActor [weak self] in
                self?.switchPreset(forward: true)
            }
        }
        nowPlayingService.onPreviousTrack = { [weak self] in
            Task { @MainActor [weak self] in
                self?.switchPreset(forward: false)
            }
        }
        nowPlayingService.configure()

        // When session timer completes, stop playback
        sessionTimer.onComplete = { [weak self] in
            self?.stopSession()
        }

        // Observe timer's remaining seconds to update Now Playing
        timerCancellable = sessionTimer.$remainingSeconds
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }

        // Live-update tone frequencies when carrier slider moves
        carrierCancellable = $carrierFrequency
            .sink { [weak self] newCarrier in
                guard let self, self.hasActiveSession else { return }
                let beat = self.selectedPreset.beatFrequency
                self.toneGenerator.updateFrequencies(
                    left: newCarrier,
                    right: newCarrier + beat
                )
            }

        // When preset changes: if playing, live-switch; if idle, auto-start with 30m
        presetCancellable = $selectedPreset
            .dropFirst() // skip initial value
            .sink { [weak self] newPreset in
                guard let self else { return }
                if self.hasActiveSession {
                    // Live-switch frequencies
                    let carrier = self.carrierFrequency
                    self.toneGenerator.updateFrequencies(
                        left: carrier,
                        right: carrier + newPreset.beatFrequency
                    )
                    self.updateNowPlayingInfo()
                } else {
                    // Auto-start with 30m
                    self.startSession(duration: .thirty)
                }
            }
    }

    // MARK: - Session Control

    /// Start a session with the selected preset and given duration.
    /// If already playing, stops first then starts fresh.
    func startSession(duration: SessionDuration) {
        // Stop any existing session
        if isPlaying || isPaused {
            toneGenerator.forceStop()
            sessionTimer.stop()
        }

        // Start tone generation using current carrier
        toneGenerator.start(
            leftFrequency: leftFrequency,
            rightFrequency: rightFrequency
        )

        // Start timer
        sessionTimer.start(duration: duration.totalSeconds)

        isPlaying = true
        isPaused = false

        updateNowPlayingInfo()
    }

    /// Toggle between playing and paused states.
    func togglePlayPause() {
        guard isPlaying || isPaused else { return }

        if isPaused {
            // Resume
            toneGenerator.resume()
            sessionTimer.resume()
            isPaused = false
            isPlaying = true
        } else {
            // Pause
            toneGenerator.pause()
            sessionTimer.pause()
            isPaused = true
            isPlaying = false
        }

        updateNowPlayingInfo()
    }

    /// Stop the current session entirely.
    func stopSession() {
        toneGenerator.stop()
        sessionTimer.stop()
        isPlaying = false
        isPaused = false
        nowPlayingService.clearNowPlaying()
    }

    /// Cycle to the next or previous preset. Wraps around.
    func switchPreset(forward: Bool) {
        let all = Preset.allCases
        guard let idx = all.firstIndex(of: selectedPreset) else { return }
        if forward {
            selectedPreset = all[(all.index(after: idx) == all.endIndex) ? all.startIndex : all.index(after: idx)]
        } else {
            selectedPreset = all[idx == all.startIndex ? all.index(before: all.endIndex) : all.index(before: idx)]
        }
    }

    /// Whether any session is active (playing or paused)
    var hasActiveSession: Bool {
        isPlaying || isPaused
    }

    // MARK: - Now Playing Updates

    private func updateNowPlayingInfo() {
        guard hasActiveSession else {
            nowPlayingService.clearNowPlaying()
            return
        }

        let elapsed = sessionTimer.totalDuration - sessionTimer.remainingSeconds
        let label = "\(selectedPreset.frequencyLabel) @ \(Int(carrierFrequency)) Hz carrier"
        let colors = selectedPreset.artworkColors
        nowPlayingService.updateNowPlaying(
            presetName: selectedPreset.displayName,
            presetIcon: selectedPreset.iconName,
            gradientStart: colors.start,
            gradientEnd: colors.end,
            frequencyLabel: label,
            remainingFormatted: sessionTimer.formattedRemaining,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: sessionTimer.totalDuration
        )
    }

    // MARK: - Cleanup

    func cleanup() {
        toneGenerator.forceStop()
        sessionTimer.stop()
        nowPlayingService.tearDown()
        timerCancellable?.cancel()
        carrierCancellable?.cancel()
        presetCancellable?.cancel()
        timerForwardCancellable?.cancel()
    }
}
