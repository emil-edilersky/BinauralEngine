import Foundation
import MediaPlayer
import AppKit

/// Integrates with macOS Now Playing (Control Center, media keys, AirPods).
///
/// Updates MPNowPlayingInfoCenter with the current preset and remaining time,
/// generates dynamic artwork showing the active mode, and registers
/// MPRemoteCommandCenter handlers for play/pause from external controls.
@MainActor
final class NowPlayingService {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    private var commandCenter: MPRemoteCommandCenter {
        MPRemoteCommandCenter.shared()
    }

    /// Cache key for last generated artwork to avoid redundant redraws
    private var lastArtworkKey: String = ""
    private var lastArtwork: MPMediaItemArtwork?

    /// Set up remote command handlers (play, pause, toggle)
    func configure() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        // Next/previous track = switch preset
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextTrack?()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousTrack?()
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    /// Update Now Playing info with current session details.
    func updateNowPlaying(
        presetName: String,
        presetIcon: String,
        gradientStart: NSColor,
        gradientEnd: NSColor,
        frequencyLabel: String,
        remainingFormatted: String,
        isPlaying: Bool,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(presetName) — \(remainingFormatted)",
            MPMediaItemPropertyArtist: "BinauralEngine",
            MPMediaItemPropertyAlbumTitle: frequencyLabel,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration
        ]

        info[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue

        // Regenerate artwork when preset changes (cached per preset)
        let artworkKey = presetName
        if artworkKey != lastArtworkKey {
            lastArtwork = generateArtwork(
                presetName: presetName,
                iconName: presetIcon,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd
            )
            lastArtworkKey = artworkKey
        }
        if let artwork = lastArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    /// Clear Now Playing info when session ends.
    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// Remove command targets on cleanup
    func tearDown() {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        clearNowPlaying()
    }

    // MARK: - Artwork Generation

    /// Renders a 300x300 thumbnail — dim neon background, full-size white circle, large white icon.
    private func generateArtwork(presetName: String, iconName: String, gradientStart: NSColor, gradientEnd: NSColor) -> MPMediaItemArtwork? {
        let size = CGSize(width: 300, height: 300)

        let image = NSImage(size: size, flipped: false) { rect in
            // Dim neon background (per-preset color)
            let gradient = NSGradient(starting: gradientStart, ending: gradientEnd)
            gradient?.draw(in: rect, angle: -45)

            // Full-size circle (edge-to-edge with small margin)
            let margin: CGFloat = 10
            let circleRect = rect.insetBy(dx: margin, dy: margin)
            NSColor(white: 1.0, alpha: 0.12).setFill()
            NSBezierPath(ovalIn: circleRect).fill()
            NSColor.white.setStroke()
            let circlePath = NSBezierPath(ovalIn: circleRect)
            circlePath.lineWidth = 2
            circlePath.stroke()

            // Icon at ~60% of the area
            if let symbolImage = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: presetName
            ) {
                let iconPointSize = rect.width * 0.6 * 0.55
                let config = NSImage.SymbolConfiguration(
                    pointSize: iconPointSize,
                    weight: .thin
                )
                let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage
                let iconSize = configured.size
                let iconRect = CGRect(
                    x: (rect.width - iconSize.width) / 2,
                    y: (rect.height - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                // Tint white by drawing into a context with .sourceIn
                let tintedImage = NSImage(size: iconSize, flipped: false) { tintRect in
                    configured.draw(in: tintRect)
                    NSColor.white.set()
                    tintRect.fill(using: .sourceIn)
                    return true
                }
                tintedImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            return true
        }

        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}
