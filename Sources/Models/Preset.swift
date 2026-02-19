import Foundation
import AppKit

/// A binaural beats preset targeting a specific brainwave state.
///
/// Each preset defines a beat frequency (the difference between left and right ears)
/// and a carrier frequency (the base tone). The brain perceives a phantom "beat"
/// at the difference frequency, which may entrain brainwaves to that rhythm.
enum Preset: String, CaseIterable, Identifiable {
    case focus
    case energize
    case flow
    case calm
    case dream
    case sleep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .focus:    return "Focus"
        case .energize: return "Energize"
        case .flow:     return "Flow"
        case .calm:  return "Calm"
        case .dream: return "Dream"
        case .sleep: return "Sleep"
        }
    }

    /// SF Symbol name for the preset icon
    var iconName: String {
        switch self {
        case .focus:    return "brain.head.profile"
        case .energize: return "sun.max.fill"
        case .flow:     return "figure.mind.and.body"
        case .calm:  return "leaf"
        case .dream: return "moon.stars"
        case .sleep: return "moon.zzz"
        }
    }

    /// Artwork gradient colors (dim neon, unique per preset)
    var artworkColors: (start: NSColor, end: NSColor) {
        switch self {
        case .focus: return (
            NSColor(red: 0.06, green: 0.08, blue: 0.20, alpha: 1.0),
            NSColor(red: 0.10, green: 0.14, blue: 0.35, alpha: 1.0)
        ) // deep blue
        case .energize: return (
            NSColor(red: 0.20, green: 0.12, blue: 0.04, alpha: 1.0),
            NSColor(red: 0.32, green: 0.18, blue: 0.06, alpha: 1.0)
        ) // warm amber
        case .flow: return (
            NSColor(red: 0.05, green: 0.12, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.08, green: 0.20, blue: 0.28, alpha: 1.0)
        ) // teal
        case .calm: return (
            NSColor(red: 0.05, green: 0.14, blue: 0.10, alpha: 1.0),
            NSColor(red: 0.08, green: 0.22, blue: 0.16, alpha: 1.0)
        ) // forest green
        case .dream: return (
            NSColor(red: 0.10, green: 0.06, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.18, green: 0.10, blue: 0.30, alpha: 1.0)
        ) // purple
        case .sleep: return (
            NSColor(red: 0.08, green: 0.06, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.12, green: 0.08, blue: 0.25, alpha: 1.0)
        ) // deep indigo
        }
    }

    /// The binaural beat frequency in Hz (difference between L and R)
    var beatFrequency: Double {
        switch self {
        case .focus:    return 40.0  // Gamma
        case .energize: return 20.0  // High beta
        case .flow:     return 14.0  // Low beta
        case .calm:  return 10.0  // Alpha
        case .dream: return 6.0   // Theta
        case .sleep: return 2.0   // Delta
        }
    }

    /// Brainwave band label
    var bandLabel: String {
        switch self {
        case .focus:    return "gamma"
        case .energize: return "high beta"
        case .flow:     return "beta"
        case .calm:  return "alpha"
        case .dream: return "theta"
        case .sleep: return "delta"
        }
    }

    /// Short description of the frequency
    var frequencyLabel: String {
        let hz = beatFrequency == floor(beatFrequency)
            ? String(format: "%.0f", beatFrequency)
            : String(format: "%.1f", beatFrequency)
        return "\(hz) Hz \(bandLabel)"
    }

    /// Carrier frequency for the left ear (Hz).
    /// 200 Hz chosen based on the Oster Curve — optimal for perceiving
    /// theta/alpha binaural beats, and within effective range for all bands.
    var carrierFrequency: Double { 200.0 }

    /// Left ear frequency
    var leftFrequency: Double { carrierFrequency }

    /// Right ear frequency (carrier + beat = binaural difference)
    var rightFrequency: Double { carrierFrequency + beatFrequency }

    /// Short description for the user
    var description: String {
        switch self {
        case .focus:    return "Deep concentration"
        case .energize: return "Alertness & energy"
        case .flow:     return "Active thinking"
        case .calm:  return "Relaxed alertness"
        case .dream: return "Creativity & meditation"
        case .sleep: return "Deep sleep"
        }
    }

    /// Brief explanation of what this preset does and how it works.
    var aboutDescription: String {
        switch self {
        case .focus:
            return "Designed to sharpen concentration and help you stay locked in. Use with headphones for the full effect."
        case .energize:
            return "Promotes alertness and mental energy. Great for mornings or when you need a pick-me-up without caffeine."
        case .flow:
            return "Helps you settle into a state of relaxed productivity. Ideal for creative work, writing, or studying."
        case .calm:
            return "Guides your mind into a relaxed-but-aware state. Good for winding down or light meditation."
        case .dream:
            return "Encourages deep meditation and creative thinking. Let your mind wander freely."
        case .sleep:
            return "Helps ease you into deep, restful sleep. Set a duration and drift off."
        }
    }
}

/// Available session durations
enum SessionDuration: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case oneHour = 60
    case eightHours = 480

    var id: Int { rawValue }

    var displayLabel: String {
        switch self {
        case .fifteen:   return "15m"
        case .thirty:    return "30m"
        case .fortyFive: return "45m"
        case .oneHour:   return "1h"
        case .eightHours: return "8h"
        }
    }

    var totalSeconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}
