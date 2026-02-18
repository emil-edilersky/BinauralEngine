import Testing
@testable import BinauralEngine

@Test func presetFrequencies() {
    // Verify all presets have correct binaural relationship:
    // right frequency = left frequency + beat frequency
    for preset in Preset.allCases {
        #expect(preset.rightFrequency == preset.leftFrequency + preset.beatFrequency)
    }
}

@Test func presetCarrierIs200Hz() {
    for preset in Preset.allCases {
        #expect(preset.carrierFrequency == 200.0)
    }
}

@Test func sessionDurations() {
    #expect(SessionDuration.fifteen.totalSeconds == 900)
    #expect(SessionDuration.thirty.totalSeconds == 1800)
    #expect(SessionDuration.fortyFive.totalSeconds == 2700)
    #expect(SessionDuration.oneHour.totalSeconds == 3600)
    #expect(SessionDuration.eightHours.totalSeconds == 28800)
}
