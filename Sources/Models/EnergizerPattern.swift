import Foundation
import AppKit

/// Stereo channel for drum placement.
enum DrumChannel {
    case left, right, center
}

/// Instrument type for drum triggers.
enum DrumInstrument {
    case kick, snare, hat, crash
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
    case thunderstruck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eternalReturnal: return "Eternal Returnal"
        case .thunderstruck:   return "Thunderstruck"
        }
    }

    var iconName: String {
        switch self {
        case .eternalReturnal: return "arrow.trianglehead.2.counterclockwise"
        case .thunderstruck:   return "bolt.horizontal.fill"
        }
    }

    var description: String {
        switch self {
        case .eternalReturnal: return "Driving 7/8 groove"
        case .thunderstruck:   return "Hard rock 4/4 drive"
        }
    }

    var aboutDescription: String {
        switch self {
        case .eternalReturnal:
            return "A relentless 133 BPM groove in 7/8 with synthesized kick, snare, and hi-hat. The asymmetric meter creates a hypnotic, lopsided drive. Always runs for exactly 5 minutes."
        case .thunderstruck:
            return "AC/DC-style 130 BPM hard rock beat. Driving eighth-note hi-hats, kick on 1 and 3, snare backbeat on 2 and 4, with crash accents. Pure energy for 5 minutes."
        }
    }

    /// Artwork gradient colors for Now Playing.
    var artworkColors: (start: NSColor, end: NSColor) {
        switch self {
        case .eternalReturnal: return (
            NSColor(red: 0.14, green: 0.04, blue: 0.04, alpha: 1.0),
            NSColor(red: 0.28, green: 0.08, blue: 0.06, alpha: 1.0)
        ) // dark crimson
        case .thunderstruck: return (
            NSColor(red: 0.16, green: 0.10, blue: 0.02, alpha: 1.0),
            NSColor(red: 0.30, green: 0.20, blue: 0.04, alpha: 1.0)
        ) // electric gold
        }
    }

    /// Quarter-note BPM.
    var bpm: Double {
        switch self {
        case .eternalReturnal: return 133.0
        case .thunderstruck:   return 130.0
        }
    }

    var loopBars: Int {
        switch self {
        case .eternalReturnal: return 4
        case .thunderstruck:   return 4
        }
    }

    /// Total loop length in quarter notes.
    var loopBeats: Double {
        switch self {
        case .eternalReturnal: return 14.0 // 4 bars × 3.5 quarter notes (7/8)
        case .thunderstruck:   return 16.0 // 4 bars × 4 quarter notes (4/4)
        }
    }

    /// Time signature label for display.
    var timeSignature: String {
        switch self {
        case .eternalReturnal: return "7/8"
        case .thunderstruck:   return "4/4"
        }
    }

    /// The full drum pattern as an array of triggers.
    func triggers() -> [DrumTrigger] {
        switch self {
        case .eternalReturnal: return Self.eternalReturnalTriggers()
        case .thunderstruck:   return Self.thunderstruckTriggers()
        }
    }

    // MARK: - Eternal Returnal Pattern (4 bars of 7/8 at 133 BPM)
    //
    // 7/8 grouped as 2+2+3 eighth notes per bar.
    // Each bar = 7 eighths = 3.5 quarter notes.
    // Bar offsets (quarter notes): 0, 3.5, 7.0, 10.5

    private static func eternalReturnalTriggers() -> [DrumTrigger] {
        var t: [DrumTrigger] = []
        let barLen = 3.5 // quarter notes per bar

        for bar in 0..<4 {
            let offset = Double(bar) * barLen

            // Kick: on subgroup downbeats (eighth 0, 2, 4 → quarter 0, 1.0, 2.0)
            t.append(DrumTrigger(beat: offset + 0.0, channel: .center, instrument: .kick, velocity: 0.95))
            t.append(DrumTrigger(beat: offset + 1.0, channel: .center, instrument: .kick, velocity: 0.80))
            t.append(DrumTrigger(beat: offset + 2.0, channel: .center, instrument: .kick, velocity: 0.85))

            // Snare: on the "3" subgroup (eighth 4 = quarter 2.0), slight left
            t.append(DrumTrigger(beat: offset + 2.0, channel: .left, instrument: .snare, velocity: 0.80))

            // Closed hat: every eighth note (0-6), alternating L/R
            for eighth in 0..<7 {
                let pos = offset + Double(eighth) * 0.5
                let chan: DrumChannel = (eighth % 2 == 0) ? .left : .right
                let vel = (eighth % 2 == 0) ? 0.40 : 0.35
                t.append(DrumTrigger(beat: pos, channel: chan, instrument: .hat, velocity: vel))
            }
        }

        // Open hat: last eighth of bars 2 and 4 (eighth 6 = quarter 3.0)
        t.append(DrumTrigger(beat: 3.5 + 3.0, channel: .right, instrument: .hat, velocity: 0.50, isOpen: true))
        t.append(DrumTrigger(beat: 10.5 + 3.0, channel: .right, instrument: .hat, velocity: 0.50, isOpen: true))

        // Ghost snare: second-to-last eighth of bar 4 (eighth 5 = quarter 2.5)
        t.append(DrumTrigger(beat: 10.5 + 2.5, channel: .right, instrument: .snare, velocity: 0.30))

        return t
    }

    // MARK: - Thunderstruck Pattern (4 bars of 4/4 at 130 BPM)
    //
    // Classic hard rock groove: driving eighth-note hats, kick on 1 & 3,
    // snare backbeat on 2 & 4, crash on bar 1, fill in bar 4.
    // Each bar = 4 quarter notes. Bar offsets: 0, 4, 8, 12.

    private static func thunderstruckTriggers() -> [DrumTrigger] {
        var t: [DrumTrigger] = []

        for bar in 0..<4 {
            let offset = Double(bar) * 4.0

            // Kick: beats 1 and 3 (quarters 0, 2)
            t.append(DrumTrigger(beat: offset + 0.0, channel: .center, instrument: .kick, velocity: 0.95))
            t.append(DrumTrigger(beat: offset + 2.0, channel: .center, instrument: .kick, velocity: 0.85))

            // Snare: beats 2 and 4 (quarters 1, 3)
            t.append(DrumTrigger(beat: offset + 1.0, channel: .left, instrument: .snare, velocity: 0.85))
            t.append(DrumTrigger(beat: offset + 3.0, channel: .left, instrument: .snare, velocity: 0.80))

            // Hi-hat: every eighth note, alternating L/R
            for eighth in 0..<8 {
                let pos = offset + Double(eighth) * 0.5
                let chan: DrumChannel = (eighth % 2 == 0) ? .left : .right
                let vel = (eighth % 2 == 0) ? 0.40 : 0.35
                t.append(DrumTrigger(beat: pos, channel: chan, instrument: .hat, velocity: vel))
            }
        }

        // Crash: beat 1 of bar 1 (phrase start)
        t.append(DrumTrigger(beat: 0.0, channel: .right, instrument: .crash, velocity: 0.70))

        // Bar 4 extras: pickup kick on "and of 4" + open hat
        t.append(DrumTrigger(beat: 15.5, channel: .center, instrument: .kick, velocity: 0.75))
        t.append(DrumTrigger(beat: 15.5, channel: .right, instrument: .hat, velocity: 0.45, isOpen: true))

        // Crash at top of repeat (bar 1 beat 1 already has it)

        return t
    }
}
