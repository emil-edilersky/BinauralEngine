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

    // MARK: - Experimental Tab State

    @Published var activeTab: AppTab = .binaural
    @Published var selectedExperimentalMode: ExperimentalMode = .isochronal
    @Published var isochronalFrequency: Double = 10.0 // Default alpha
    @Published var crystalBowlPattern: CrystalBowlPattern = .relax
    @Published var adhdPowerVariation: ADHDPowerVariation = .standard

    /// Which tab started the current session (nil when idle).
    /// Used for pause/resume routing and UI highlighting — independent of which tab is *visible*.
    @Published private(set) var playingTab: AppTab?

    // MARK: - Services

    let sessionTimer = SessionTimer()
    private let toneGenerator = ToneGenerator()
    private let experimentalGenerator = ExperimentalToneGenerator()
    private let nowPlayingService = NowPlayingService()

    private var timerCancellable: AnyCancellable?
    private var carrierCancellable: AnyCancellable?
    private var presetCancellable: AnyCancellable?
    private var timerForwardCancellable: AnyCancellable?
    private var isoFreqCancellable: AnyCancellable?
    private var experimentalModeCancellable: AnyCancellable?
    private var bowlPatternCancellable: AnyCancellable?
    private var adhdVariationCancellable: AnyCancellable?

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

        // When preset changes: if binaural playing, live-switch; otherwise start fresh
        presetCancellable = $selectedPreset
            .dropFirst() // skip initial value
            .sink { [weak self] newPreset in
                guard let self else { return }
                if self.hasActiveSession && self.playingTab == .binaural {
                    // Live-switch frequencies on the running binaural generator
                    let carrier = self.carrierFrequency
                    self.toneGenerator.updateFrequencies(
                        left: carrier,
                        right: carrier + newPreset.beatFrequency
                    )
                    self.updateNowPlayingInfo()
                } else {
                    // Idle or experimental playing — start binaural session
                    self.startSession(duration: .thirty)
                }
            }

        // Live-update isochronal beat frequency when picker changes
        isoFreqCancellable = $isochronalFrequency
            .sink { [weak self] newFreq in
                guard let self,
                      self.hasActiveSession,
                      self.activeTab == .experimental,
                      self.selectedExperimentalMode == .isochronal else { return }
                self.experimentalGenerator.updateIsochronalFrequency(newFreq)
            }

        // When experimental mode changes: if playing, restart; if idle, auto-start
        experimentalModeCancellable = $selectedExperimentalMode
            .dropFirst()
            .sink { [weak self] newMode in
                guard let self, self.activeTab == .experimental else { return }
                if self.hasActiveSession {
                    self.startExperimentalSession(duration: nil, mode: newMode)
                } else {
                    self.startSession(duration: .thirty)
                }
            }

        // When crystal bowl pattern changes while playing crystal bowl, restart with new pattern
        bowlPatternCancellable = $crystalBowlPattern
            .dropFirst()
            .sink { [weak self] newPattern in
                guard let self,
                      self.hasActiveSession,
                      self.activeTab == .experimental,
                      self.selectedExperimentalMode == .crystalBowl else { return }
                self.startExperimentalSession(duration: nil, mode: .crystalBowl, bowlPattern: newPattern)
            }

        // When ADHD variation changes while playing ADHD Power, restart with new variation
        adhdVariationCancellable = $adhdPowerVariation
            .dropFirst()
            .sink { [weak self] newVariation in
                guard let self,
                      self.hasActiveSession,
                      self.activeTab == .experimental,
                      self.selectedExperimentalMode == .adhdPower else { return }
                self.startExperimentalSession(duration: nil, mode: .adhdPower, adhdVariation: newVariation)
            }
    }

    // MARK: - Session Control

    /// Start a session with the selected preset/mode and given duration.
    /// If already playing, stops first then starts fresh.
    func startSession(duration: SessionDuration) {
        // Stop any existing session
        if isPlaying || isPaused {
            toneGenerator.forceStop()
            experimentalGenerator.forceStop()
            sessionTimer.stop()
        }

        playingTab = activeTab

        if activeTab == .binaural {
            toneGenerator.start(
                leftFrequency: leftFrequency,
                rightFrequency: rightFrequency
            )
        } else {
            experimentalGenerator.start(mode: selectedExperimentalMode, bowlPattern: crystalBowlPattern, adhdVariation: adhdPowerVariation)
        }

        sessionTimer.start(duration: duration.totalSeconds)

        isPlaying = true
        isPaused = false

        updateNowPlayingInfo()
    }

    /// Start an experimental session, optionally reusing the current timer.
    /// Used when switching experimental modes mid-session.
    /// Optional overrides for bowlPattern/adhdVariation are needed because
    /// Combine's @Published emits on willSet (before the property updates),
    /// so reading self.crystalBowlPattern inside a $crystalBowlPattern sink
    /// would return the OLD value.
    func startExperimentalSession(
        duration: SessionDuration?,
        mode: ExperimentalMode,
        bowlPattern: CrystalBowlPattern? = nil,
        adhdVariation: ADHDPowerVariation? = nil
    ) {
        let remainingTime = sessionTimer.remainingSeconds

        toneGenerator.forceStop()
        experimentalGenerator.forceStop()
        sessionTimer.stop()

        playingTab = .experimental

        experimentalGenerator.start(
            mode: mode,
            bowlPattern: bowlPattern ?? crystalBowlPattern,
            adhdVariation: adhdVariation ?? adhdPowerVariation
        )

        if let duration {
            sessionTimer.start(duration: duration.totalSeconds)
        } else if remainingTime > 0 {
            sessionTimer.start(duration: remainingTime)
        } else {
            sessionTimer.start(duration: SessionDuration.thirty.totalSeconds)
        }

        isPlaying = true
        isPaused = false

        updateNowPlayingInfo()
    }

    /// Toggle between playing and paused states.
    /// Routes to the correct generator based on which tab started the session,
    /// not which tab is currently visible.
    func togglePlayPause() {
        guard isPlaying || isPaused else { return }

        if isPaused {
            // Resume
            if playingTab == .binaural {
                toneGenerator.resume()
            } else {
                experimentalGenerator.resume()
            }
            sessionTimer.resume()
            isPaused = false
            isPlaying = true
        } else {
            // Pause
            if playingTab == .binaural {
                toneGenerator.pause()
            } else {
                experimentalGenerator.pause()
            }
            sessionTimer.pause()
            isPaused = true
            isPlaying = false
        }

        updateNowPlayingInfo()
    }

    /// Stop the current session entirely.
    func stopSession() {
        toneGenerator.stop()
        experimentalGenerator.stop()
        sessionTimer.stop()
        isPlaying = false
        isPaused = false
        playingTab = nil
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

        let name: String
        let icon: String
        let colors: (start: NSColor, end: NSColor)
        let label: String

        if playingTab == .binaural {
            name = selectedPreset.displayName
            icon = selectedPreset.iconName
            colors = selectedPreset.artworkColors
            label = "\(selectedPreset.frequencyLabel) @ \(Int(carrierFrequency)) Hz carrier"
        } else {
            let mode = selectedExperimentalMode
            name = mode.displayName
            icon = mode.iconName
            colors = mode.artworkColors
            if mode == .isochronal {
                label = "\(Int(isochronalFrequency)) Hz isochronal"
            } else if mode == .crystalBowl {
                label = "432 Hz \(crystalBowlPattern.displayName) bowl pattern"
            } else if mode == .adhdPower {
                label = "\(adhdPowerVariation.displayName) ADHD Power"
            } else {
                label = mode.description
            }
        }

        nowPlayingService.updateNowPlaying(
            presetName: name,
            presetIcon: icon,
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
        experimentalGenerator.forceStop()
        sessionTimer.stop()
        nowPlayingService.tearDown()
        timerCancellable?.cancel()
        carrierCancellable?.cancel()
        presetCancellable?.cancel()
        timerForwardCancellable?.cancel()
        isoFreqCancellable?.cancel()
        experimentalModeCancellable?.cancel()
        bowlPatternCancellable?.cancel()
        adhdVariationCancellable?.cancel()
    }
}
