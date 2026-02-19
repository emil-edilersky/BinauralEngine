import Foundation
import AppKit

/// Stereo channel for drum placement.
enum DrumChannel {
    case left, right, center
}

/// Instrument type for drum triggers.
enum DrumInstrument {
    case kick, snare, hat
}

/// A single drum hit within a loop.
struct DrumTrigger {
    /// Position within loop (0-based, in quarter notes).
    let beat: Double
    /// Stereo channel placement.
    let channel: DrumChannel
    /// Which drum voice to fire.
    let instrument: DrumInstrument
    /// Hit intensity 0–1.
    let velocity: Double
    /// For hat: open (longer decay) vs closed (short).
    let isOpen: Bool

    init(beat: Double, channel: DrumChannel, instrument: DrumInstrument, velocity: Double, isOpen: Bool = false) {
        self.beat = beat
        self.channel = channel
        self.instrument = instrument
        self.velocity = velocity
        self.isOpen = isOpen
    }
}

/// Energizer drum patterns — short, intense 5-minute sessions.
enum EnergizerPattern: String, CaseIterable, Identifiable {
    case eternalReturnal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eternalReturnal: return "Eternal Returnal"
        }
    }

    var iconName: String {
        switch self {
        case .eternalReturnal: return "arrow.trianglehead.2.counterclockwise"
        }
    }

    var description: String {
        switch self {
        case .eternalReturnal: return "Driving four-on-the-floor groove"
        }
    }

    var aboutDescription: String {
        switch self {
        case .eternalReturnal:
            return "A relentless 130 BPM electronic groove with synthesized kick, snare, and hi-hat. Four-on-the-floor energy to power through a quick break. Always runs for exactly 5 minutes."
        }
    }

    /// Artwork gradient colors for Now Playing.
    var artworkColors: (start: NSColor, end: NSColor) {
        switch self {
        case .eternalReturnal: return (
            NSColor(red: 0.14, green: 0.04, blue: 0.04, alpha: 1.0),
            NSColor(red: 0.28, green: 0.08, blue: 0.06, alpha: 1.0)
        ) // dark crimson
        }
    }

    var bpm: Double {
        switch self {
        case .eternalReturnal: return 130.0
        }
    }

    var beatsPerBar: Int {
        switch self {
        case .eternalReturnal: return 4
        }
    }

    var loopBars: Int {
        switch self {
        case .eternalReturnal: return 4
        }
    }

    /// Total loop length in quarter notes.
    var loopBeats: Int { beatsPerBar * loopBars }

    /// The full drum pattern as an array of triggers.
    func triggers() -> [DrumTrigger] {
        switch self {
        case .eternalReturnal: return Self.eternalReturnalTriggers()
        }
    }

    // MARK: - Eternal Returnal Pattern (4 bars of 4/4 at 130 BPM)

    private static func eternalReturnalTriggers() -> [DrumTrigger] {
        var t: [DrumTrigger] = []

        // Kick: every quarter note (four-on-the-floor), center
        for bar in 0..<4 {
            for beat in 0..<4 {
                let pos = Double(bar * 4 + beat)
                let vel = (beat == 0) ? 0.95 : 0.85
                t.append(DrumTrigger(beat: pos, channel: .center, instrument: .kick, velocity: vel))
            }
        }

        // Snare: beats 1 and 3 of each bar (backbeat), slight left bias
        for bar in 0..<4 {
            t.append(DrumTrigger(beat: Double(bar * 4 + 1), channel: .left, instrument: .snare, velocity: 0.80))
            t.append(DrumTrigger(beat: Double(bar * 4 + 3), channel: .left, instrument: .snare, velocity: 0.78))
        }

        // Closed hat: every 8th note, alternating L/R
        for bar in 0..<4 {
            for eighth in 0..<8 {
                let pos = Double(bar * 4) + Double(eighth) * 0.5
                let chan: DrumChannel = (eighth % 2 == 0) ? .left : .right
                let vel = (eighth % 2 == 0) ? 0.40 : 0.35
                t.append(DrumTrigger(beat: pos, channel: chan, instrument: .hat, velocity: vel))
            }
        }

        // Open hat: beat 3.5 in bars 2 and 4 for lift
        t.append(DrumTrigger(beat: 7.5, channel: .right, instrument: .hat, velocity: 0.50, isOpen: true))
        t.append(DrumTrigger(beat: 15.5, channel: .right, instrument: .hat, velocity: 0.50, isOpen: true))

        // Ghost snare: beat 2.75 in bar 4 for fill
        t.append(DrumTrigger(beat: 14.75, channel: .right, instrument: .snare, velocity: 0.35))

        return t
    }
}
