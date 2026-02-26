import Foundation
import AppKit

/// Energizer audio tracks — mp3 files played at their original duration.
enum EnergizerPattern: String, CaseIterable, Identifiable {
    case timeToJazz
    case gardenRoots
    case eternalReturnal
    case saryKhalil
    case qalabalik

    var id: String { rawValue }

    /// Bundle filename (without extension) for mp3 lookup.
    var mp3Filename: String {
        switch self {
        case .timeToJazz:      return "time-to-jazz"
        case .gardenRoots:     return "garden-roots"
        case .eternalReturnal: return "eternal-returnal"
        case .saryKhalil:      return "sary-khalil"
        case .qalabalik:       return "qalabalik"
        }
    }

    var displayName: String {
        switch self {
        case .timeToJazz:      return "Time to Jazz"
        case .gardenRoots:     return "Garden Roots"
        case .eternalReturnal: return "Eternal Returnal"
        case .saryKhalil:      return "Sary Khalil"
        case .qalabalik:       return "Qalabalik"
        }
    }

    var iconName: String {
        switch self {
        case .timeToJazz:      return "music.note"
        case .gardenRoots:     return "leaf.fill"
        case .eternalReturnal: return "waveform.path"
        case .saryKhalil:      return "sparkles"
        case .qalabalik:       return "flame.fill"
        }
    }

    var description: String {
        switch self {
        case .timeToJazz:      return "Jazz energy boost"
        case .gardenRoots:     return "Organic groove"
        case .eternalReturnal: return "Hypnotic loop"
        case .saryKhalil:      return "Eastern rhythms"
        case .qalabalik:       return "Chaotic energy"
        }
    }

    var aboutDescription: String {
        switch self {
        case .timeToJazz:
            return "High-energy jazz fusion clip — improvisational fire to get you moving."
        case .gardenRoots:
            return "Organic, earthy grooves rooted in world music traditions."
        case .eternalReturnal:
            return "A hypnotic audio loop that builds and cycles, pulling you into deep focus."
        case .saryKhalil:
            return "Eastern-influenced rhythmic patterns with intricate percussion layers."
        case .qalabalik:
            return "Raw, chaotic energy — controlled musical mayhem."
        }
    }

    /// Artwork gradient colors for Now Playing.
    var artworkColors: (start: NSColor, end: NSColor) {
        switch self {
        case .timeToJazz: return (
            NSColor(red: 0.08, green: 0.06, blue: 0.16, alpha: 1.0),
            NSColor(red: 0.16, green: 0.12, blue: 0.30, alpha: 1.0)
        ) // midnight blue
        case .gardenRoots: return (
            NSColor(red: 0.04, green: 0.12, blue: 0.06, alpha: 1.0),
            NSColor(red: 0.08, green: 0.22, blue: 0.10, alpha: 1.0)
        ) // forest green
        case .eternalReturnal: return (
            NSColor(red: 0.12, green: 0.04, blue: 0.10, alpha: 1.0),
            NSColor(red: 0.24, green: 0.08, blue: 0.20, alpha: 1.0)
        ) // deep purple
        case .saryKhalil: return (
            NSColor(red: 0.14, green: 0.10, blue: 0.04, alpha: 1.0),
            NSColor(red: 0.26, green: 0.18, blue: 0.06, alpha: 1.0)
        ) // warm amber
        case .qalabalik: return (
            NSColor(red: 0.16, green: 0.04, blue: 0.02, alpha: 1.0),
            NSColor(red: 0.32, green: 0.06, blue: 0.04, alpha: 1.0)
        ) // fiery red
        }
    }
}
