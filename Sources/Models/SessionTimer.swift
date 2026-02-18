import Foundation
import Combine

/// Countdown timer for binaural beat sessions.
///
/// Publishes remaining time so the UI can display it. Fires a completion
/// callback when the session ends.
@MainActor
final class SessionTimer: ObservableObject {
    @Published var remainingSeconds: TimeInterval = 0
    @Published var isRunning: Bool = false

    var onComplete: (() -> Void)?

    private var timer: Timer?
    private var endDate: Date?

    /// Total duration of the current session
    private(set) var totalDuration: TimeInterval = 0

    /// Start a countdown for the given duration in seconds.
    func start(duration: TimeInterval) {
        stop()
        totalDuration = duration
        remainingSeconds = duration
        endDate = Date().addingTimeInterval(duration)
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Pause the countdown (preserves remaining time).
    func pause() {
        timer?.invalidate()
        timer = nil
        // Snapshot remaining time so we can resume from it
        if let end = endDate {
            remainingSeconds = max(0, end.timeIntervalSinceNow)
        }
        endDate = nil
        isRunning = false
    }

    /// Resume a paused countdown.
    func resume() {
        guard !isRunning, remainingSeconds > 0 else { return }
        endDate = Date().addingTimeInterval(remainingSeconds)
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Stop and reset the timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = 0
        isRunning = false
        totalDuration = 0
    }

    private func tick() {
        guard let end = endDate else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            remainingSeconds = 0
            stop()
            onComplete?()
        } else {
            remainingSeconds = remaining
        }
    }

    /// Formatted string for display (e.g., "24:35" or "1:24:35")
    var formattedRemaining: String {
        let total = Int(remainingSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Elapsed fraction (0.0 to 1.0) for progress display
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (remainingSeconds / totalDuration)
    }
}
