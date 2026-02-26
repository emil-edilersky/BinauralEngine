import Foundation
import AppKit

/// Which tab is active in the menu bar popover.
enum AppTab: String, CaseIterable, Identifiable {
    case binaural
    case experimental
    case energizer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .binaural:     return "Binaural"
        case .experimental: return "Experimental"
        case .energizer:    return "Energizer"
        }
    }
}

/// Experimental tone modes beyond classic binaural beats.
enum ExperimentalMode: String, CaseIterable, Identifiable {
    case isochronal
    case pinkNoise
    case brownNoise
    case crystalBowl
    case heartCoherence
    case adhdPower
    case brainMassage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .isochronal:      return "Isochronal"
        case .pinkNoise:       return "Pink Noise"
        case .brownNoise:      return "Brown Noise"
        case .crystalBowl:     return "Crystal Bowl"
        case .heartCoherence:  return "Heart Coherence"
        case .adhdPower:       return "ADHD Power"
        case .brainMassage:        return "Brain Massage"
        }
    }

    /// SF Symbol name for the mode icon
    var iconName: String {
        switch self {
        case .isochronal:      return "metronome"
        case .pinkNoise:       return "cloud.fill"
        case .brownNoise:      return "wind"
        case .crystalBowl:     return "bell.fill"
        case .heartCoherence:  return "heart.fill"
        case .adhdPower:       return "bolt.fill"
        case .brainMassage:        return "brain"
        }
    }

    var description: String {
        switch self {
        case .isochronal:      return "Pulsed tone at chosen Hz"
        case .pinkNoise:       return "Equal energy per octave"
        case .brownNoise:      return "Deep low-frequency rumble"
        case .crystalBowl:     return "Multi-bowl 432 Hz sound bath"
        case .heartCoherence:  return "0.1 Hz breathing-guide pulse"
        case .adhdPower:       return "Deep drone with slow swells"
        case .brainMassage:        return "Hemi-sync theta brain massage"
        }
    }

    /// Brief explanation of what this mode does and how it works.
    var aboutDescription: String {
        switch self {
        case .isochronal:
            return "A pulsing tone you can hear directly — no headphones needed. Choose a speed to match the brainwave state you want."
        case .pinkNoise:
            return "Balanced, natural-sounding noise that masks distractions. Like steady rain — great for focus or falling asleep."
        case .brownNoise:
            return "Deep, rumbly noise that feels warm and enveloping. Blocks out the world so you can think or rest."
        case .crystalBowl:
            return "Layered singing bowls gently swelling and drifting across the stereo field. A sound bath you can carry in your menu bar."
        case .heartCoherence:
            return "A tone that slowly swells and fades. Breathe with it — in as it rises, out as it falls — to calm your nervous system."
        case .adhdPower:
            return "A deep, immersive drone with ultra-slow swells and wide stereo separation. Designed to hold restless attention steady."
        case .brainMassage:
            return "Hemi-sync technique: multiple binaural beat layers at theta and alpha frequencies interact to create a pulsing sensation that moves through your mind. Headphones required."
        }
    }

    /// Artwork gradient colors for Now Playing (dim neon, unique per mode)
    var artworkColors: (start: NSColor, end: NSColor) {
        switch self {
        case .isochronal: return (
            NSColor(red: 0.18, green: 0.08, blue: 0.06, alpha: 1.0),
            NSColor(red: 0.30, green: 0.14, blue: 0.08, alpha: 1.0)
        ) // warm red
        case .pinkNoise: return (
            NSColor(red: 0.16, green: 0.06, blue: 0.14, alpha: 1.0),
            NSColor(red: 0.26, green: 0.10, blue: 0.22, alpha: 1.0)
        ) // pink
        case .brownNoise: return (
            NSColor(red: 0.12, green: 0.08, blue: 0.04, alpha: 1.0),
            NSColor(red: 0.20, green: 0.14, blue: 0.06, alpha: 1.0)
        ) // brown
        case .crystalBowl: return (
            NSColor(red: 0.06, green: 0.14, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.10, green: 0.22, blue: 0.28, alpha: 1.0)
        ) // crystal teal
        case .heartCoherence: return (
            NSColor(red: 0.18, green: 0.04, blue: 0.08, alpha: 1.0),
            NSColor(red: 0.28, green: 0.06, blue: 0.12, alpha: 1.0)
        ) // deep rose
        case .adhdPower: return (
            NSColor(red: 0.10, green: 0.06, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.18, green: 0.10, blue: 0.30, alpha: 1.0)
        ) // electric indigo
        case .brainMassage: return (
            NSColor(red: 0.04, green: 0.10, blue: 0.18, alpha: 1.0),
            NSColor(red: 0.08, green: 0.18, blue: 0.30, alpha: 1.0)
        ) // deep electric blue
        }
    }
}

/// Available isochronal beat frequencies with brainwave band labels.
enum IsochronalFrequency: Double, CaseIterable, Identifiable {
    case theta = 4.0
    case lowAlpha = 6.0
    case alpha = 10.0
    case beta = 14.0
    case gamma = 40.0

    var id: Double { rawValue }

    var displayLabel: String {
        "\(Int(rawValue))"
    }

    var bandLabel: String {
        switch self {
        case .theta:    return "theta"
        case .lowAlpha: return "theta/alpha"
        case .alpha:    return "alpha"
        case .beta:     return "beta"
        case .gamma:    return "gamma"
        }
    }
}

/// ADHD Power speed variations.
///
/// Standard uses the original modulation rates from the spectral analysis.
/// Slow scales all modulation rates by 0.833× (20% slower) for a calmer version.
enum ADHDPowerVariation: String, CaseIterable, Identifiable {
    case standard
    case slow
    case still

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Steady Pace"
        case .slow:     return "Slow"
        case .still:    return "Still"
        }
    }

    var iconName: String {
        switch self {
        case .standard: return "bolt.fill"
        case .slow:     return "tortoise.fill"
        case .still:    return "moon.fill"
        }
    }

    /// Multiplier applied to all modulation periods (>1 = slower).
    var periodScale: Double {
        switch self {
        case .standard: return 1.0
        case .slow:     return 1.2   // 20% slower
        case .still:    return 1.56  // 30% slower than slow (1.2 × 1.3)
        }
    }
}

/// Crystal singing bowl patterns based on spectral analysis of real bowl recordings.
///
/// Each pattern uses **modal clusters** — groups of closely-spaced frequencies that
/// produce natural beating/shimmer, exactly as measured from actual crystal bowl audio.
/// Patterns are derived from different source recordings, each with unique character.
enum CrystalBowlPattern: String, CaseIterable, Identifiable {
    case relax
    case heal
    case meditate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relax:    return "Relax"
        case .heal:     return "Heal"
        case .meditate: return "Meditate"
        }
    }

    var iconName: String {
        switch self {
        case .relax:    return "leaf"
        case .heal:     return "cross.circle"
        case .meditate: return "figure.mind.and.body"
        }
    }

    /// All modal oscillators: (frequency Hz, amplitude 0–1 relative, cluster index).
    /// Clusters group oscillators that share an amplitude LFO swell.
    var modes: [(freq: Double, amp: Double, cluster: Int)] {
        switch self {
        case .relax:
            // From 432Hz Calming Crystal Singing Bowls — bright, warm
            // Centroid ~360 Hz. Clusters: ~258, ~344, ~325, ~433 Hz
            return [
                // Cluster 0: ~258 Hz (C4 — dominant)
                (257.925, 1.000, 0),
                (258.125, 0.216, 0),
                (258.325, 0.178, 0),
                (258.588, 0.108, 0),
                // Cluster 1: ~344 Hz (F4 — nearly equal)
                (343.595, 0.977, 1),
                (342.954, 0.468, 1),
                (343.953, 0.350, 1),
                (343.795, 0.251, 1),
                (344.279, 0.200, 1),
                // Cluster 2: ~325 Hz (E4)
                (325.185, 0.741, 2),
                (324.817, 0.575, 2),
                (324.954, 0.479, 2),
                (325.385, 0.251, 2),
                // Cluster 3: ~433 Hz (A4 — quiet)
                (433.124, 0.158, 3),
                (432.830, 0.098, 3),
            ]
        case .heal:
            // From Healing Vibrations bowl recording — deep, resonant
            // Centroid ~200 Hz. Clusters: ~162, ~129, ~289, supporting
            return [
                // Cluster 0: ~162 Hz (dominant)
                (162.670, 1.000, 0),
                (162.430, 0.214, 0),
                (163.074, 0.078, 0),
                // Cluster 1: ~129 Hz
                (129.747, 0.228, 1),
                (129.254, 0.137, 1),
                (128.763, 0.025, 1),
                // Cluster 2: ~289 Hz
                (288.683, 0.226, 2),
                (288.977, 0.086, 2),
                (289.333, 0.042, 2),
                (289.657, 0.018, 2),
                // Cluster 3: supporting modes
                (325.264, 0.022, 3),
                (257.423, 0.011, 3),
                (80.620,  0.016, 3),
            ]
        case .meditate:
            // From Purity Sound Bath — spacious, warm
            // Centroid ~253 Hz. Clusters: ~258, ~172, ~194, ~342, ~486, ~384, ~433
            return [
                // Cluster 0: ~258 Hz (C4 — dominant)
                (258.104, 1.000, 0),
                (257.852, 0.977, 0),
                (258.356, 0.149, 0),
                (257.599, 0.132, 0),
                // Cluster 1: ~172 Hz (F3 — strong)
                (172.076, 0.977, 1),
                // Cluster 2: ~194 Hz (G3 — strong)
                (194.146, 0.862, 2),
                (194.030, 0.098, 2),
                (194.430, 0.044, 2),
                // Cluster 3: ~342 Hz (F4)
                (342.218, 0.056, 3),
                (341.829, 0.029, 3),
                // Cluster 4: ~486 Hz (B4)
                (485.738, 0.028, 4),
                (485.959, 0.019, 4),
                (485.601, 0.016, 4),
                // Cluster 5: ~384 Hz (G4)
                (384.622, 0.021, 5),
                (383.844, 0.012, 5),
                // Cluster 6: ~433 Hz (A4)
                (433.135, 0.020, 6),
                (433.019, 0.014, 6),
            ]
        }
    }

    /// Per-cluster amplitude LFO: (rate Hz, depth 0–1).
    /// Index matches the cluster field in `modes`.
    var clusterLFOs: [(rate: Double, depth: Double)] {
        switch self {
        case .relax:
            // Slow dominant swell at 0.133 Hz (7.5s)
            return [
                (0.133, 0.45),  // ~258 Hz cluster
                (0.18,  0.50),  // ~344 Hz
                (0.10,  0.40),  // ~325 Hz
                (0.08,  0.35),  // ~433 Hz
            ]
        case .heal:
            // Moderate swells
            return [
                (0.08, 0.45),   // ~162 Hz — slowest
                (0.12, 0.50),   // ~129 Hz
                (0.18, 0.55),   // ~289 Hz — fastest
                (0.10, 0.40),   // supporting
            ]
        case .meditate:
            // Dominant single swell at 0.267 Hz (3.75s)
            return [
                (0.267, 0.50),  // ~258 Hz
                (0.20,  0.55),  // ~172 Hz
                (0.30,  0.45),  // ~194 Hz
                (0.15,  0.40),  // ~342 Hz
                (0.22,  0.45),  // ~486 Hz
                (0.18,  0.40),  // ~384 Hz
                (0.12,  0.35),  // ~433 Hz
            ]
        }
    }
}
