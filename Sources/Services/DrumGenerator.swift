import AVFoundation
import Foundation

/// Generates synthesized drum patterns for Energizer sessions.
///
/// Mirrors ExperimentalToneGenerator architecture: AVAudioEngine + AVAudioSourceNode
/// render callback with UnsafeMutablePointer for lock-free audio thread communication.
/// All drum voices (kick, snare, hi-hat) are synthesized in the callback — no samples.
@MainActor
final class DrumGenerator {
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    private let fadeDuration: Double = 0.5
    private(set) var isPlaying: Bool = false
    private var generation: Int = 0

    private var configChangeObserver: NSObjectProtocol?
    private var lastPattern: EnergizerPattern?

    private var _targetGainPtr: UnsafeMutablePointer<Float>?

    // MARK: - Start

    func start(pattern: EnergizerPattern) {
        generation += 1
        stop()

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        let targetGainPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        targetGainPtr.pointee = 1.0

        let gainSmoothing: Float = Float(1.0 / (fadeDuration * sampleRate))

        let renderBlock = Self.drumRenderBlock(
            sampleRate: sampleRate,
            pattern: pattern,
            targetGainPtr: targetGainPtr,
            gainSmoothing: gainSmoothing
        )

        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        let node = AVAudioSourceNode(format: stereoFormat, renderBlock: renderBlock)

        engine.attach(node)
        engine.connect(node, to: mainMixer, format: stereoFormat)
        mainMixer.outputVolume = 0.8

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            self.isPlaying = true
            self.lastPattern = pattern
            self._targetGainPtr = targetGainPtr

            configChangeObserver.map { NotificationCenter.default.removeObserver($0) }
            configChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDeviceChange()
                }
            }
        } catch {
            print("DrumGenerator: Failed to start audio engine: \(error)")
            targetGainPtr.deallocate()
        }
    }

    // MARK: - Lifecycle

    func stop(completion: (() -> Void)? = nil) {
        guard isPlaying, audioEngine != nil else {
            completion?()
            return
        }

        _targetGainPtr?.pointee = 0.0

        let expectedGeneration = generation
        let fadeMs = Int(fadeDuration * 1000) + 100
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(fadeMs)) { [weak self] in
            guard let self, self.generation == expectedGeneration else {
                completion?()
                return
            }
            self.tearDownEngine()
            completion?()
        }
    }

    func pause() {
        audioEngine?.pause()
    }

    func resume() {
        try? audioEngine?.start()
    }

    func forceStop() {
        generation += 1
        _targetGainPtr?.pointee = 0.0
        tearDownEngine()
    }

    // MARK: - Device Change

    private func handleDeviceChange() {
        guard isPlaying || (_targetGainPtr != nil), let pattern = lastPattern else { return }
        forceStop()
        start(pattern: pattern)
    }

    // MARK: - Teardown

    private func tearDownEngine() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let engine = audioEngine {
            engine.stop()
            if let node = sourceNode, engine.attachedNodes.contains(node) {
                engine.detach(node)
            }
        }
        audioEngine = nil
        sourceNode = nil
        isPlaying = false

        _targetGainPtr?.deallocate()
        _targetGainPtr = nil
    }

    deinit {
        _targetGainPtr?.deallocate()
    }

    // MARK: - DSP Primitives

    /// Exponential decay envelope.
    private struct ExpEnv {
        var value: Float = 0.0
        var decay: Float = 0.999

        mutating func trigger(level: Float = 1.0) {
            value = level
        }

        mutating func process() -> Float {
            let out = value
            value *= decay
            return out
        }
    }

    /// Thread-safe linear congruential generator for noise.
    private struct LCGNoise {
        var state: UInt32

        init(seed: UInt32 = 12345) {
            state = seed
        }

        mutating func next() -> Float {
            state = state &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: state)) / Float(Int32.max)
        }
    }

    /// One-pole filter (LP or HP).
    private struct OnePole {
        var y1: Float = 0.0
        var a: Float = 0.5

        static func lowpass(cutoff: Double, sampleRate: Double) -> OnePole {
            let omega = 2.0 * Double.pi * cutoff / sampleRate
            return OnePole(y1: 0, a: Float(omega / (1.0 + omega)))
        }

        static func highpass(cutoff: Double, sampleRate: Double) -> OnePole {
            let omega = 2.0 * Double.pi * cutoff / sampleRate
            return OnePole(y1: 0, a: Float(1.0 / (1.0 + omega)))
        }

        mutating func processLP(_ x: Float) -> Float {
            y1 += a * (x - y1)
            return y1
        }

        mutating func processHP(_ x: Float) -> Float {
            let lp = processLP(x)
            return x - lp
        }
    }

    /// Biquad bandpass filter with unity peak gain at center frequency.
    private struct BiquadBPF {
        var b0: Float, b1: Float, b2: Float
        var a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        /// Standard BPF scaled so peak gain at center ≈ Q (resonant boost).
        static func bandpass(freq: Double, q: Double, sampleRate: Double) -> BiquadBPF {
            let omega = 2.0 * Double.pi * freq / sampleRate
            let sinW = sin(omega)
            let alpha = sinW / (2.0 * q)
            let a0 = 1.0 + alpha
            // Scale by Q so narrow bands still pass useful signal
            let scale = q * 0.5
            return BiquadBPF(
                b0: Float(alpha / a0 * scale),
                b1: 0,
                b2: Float(-alpha / a0 * scale),
                a1: Float(-2.0 * cos(omega) / a0),
                a2: Float((1.0 - alpha) / a0)
            )
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }

        mutating func reset() {
            x1 = 0; x2 = 0; y1 = 0; y2 = 0
        }
    }

    // MARK: - Voice Structs

    /// Shared helper for decay coefficient computation.
    private nonisolated static func decayCoeff(ms: Double, sampleRate: Double) -> Float {
        Float(exp(-1.0 / (ms * 0.001 * sampleRate)))
    }

    /// Kick: sine with pitch envelope (160→50 Hz glide), punchy 80ms decay.
    private struct KickVoice {
        var active: Bool = false
        var phase: Double = 0.0
        var ampEnv: ExpEnv = ExpEnv()
        var pitchEnv: ExpEnv = ExpEnv()
        var velocity: Float = 0.0

        mutating func trigger(velocity: Float, sampleRate: Double) {
            active = true
            phase = 0.0
            self.velocity = velocity
            // Short 80ms decay = punchy kick that clears before next beat
            ampEnv = ExpEnv(value: velocity, decay: decayCoeff(ms: 80, sampleRate: sampleRate))
            // Fast 20ms pitch glide: 160→50 Hz
            pitchEnv = ExpEnv(value: 1.0, decay: decayCoeff(ms: 20, sampleRate: sampleRate))
        }

        mutating func render(sampleRate: Double) -> Float {
            guard active else { return 0 }
            let pitchMix = pitchEnv.process()
            let freq = 50.0 + 110.0 * Double(pitchMix) // 160→50 Hz
            let sample = Float(sin(2.0 * .pi * phase)) * ampEnv.process()
            phase += freq / sampleRate
            if phase >= 1.0 { phase -= 1.0 }
            if ampEnv.value < 0.005 { active = false }
            return sample
        }
    }

    /// Snare: noise burst + 2 wide bandpass resonators + HP snap. 60ms decay.
    private struct SnareVoice {
        var active: Bool = false
        var noiseEnv: ExpEnv = ExpEnv()
        var toneEnv: ExpEnv = ExpEnv()
        var bodyBPF: BiquadBPF
        var crackBPF: BiquadBPF
        var hpf: OnePole
        var noise: LCGNoise
        var velocity: Float = 0.0

        init(sampleRate: Double, seed: UInt32) {
            // Lower Q for wider, louder bands
            bodyBPF = BiquadBPF.bandpass(freq: 250, q: 1.5, sampleRate: sampleRate)
            crackBPF = BiquadBPF.bandpass(freq: 1200, q: 2.0, sampleRate: sampleRate)
            hpf = OnePole.highpass(cutoff: 150, sampleRate: sampleRate)
            noise = LCGNoise(seed: seed)
        }

        mutating func trigger(velocity: Float, sampleRate: Double) {
            active = true
            self.velocity = velocity
            noiseEnv = ExpEnv(value: velocity, decay: decayCoeff(ms: 60, sampleRate: sampleRate))
            toneEnv = ExpEnv(value: velocity, decay: decayCoeff(ms: 35, sampleRate: sampleRate))
            // Reset filters for clean transient
            bodyBPF.reset()
            crackBPF.reset()
        }

        mutating func render() -> Float {
            guard active else { return 0 }
            let n = noise.next()
            let noiseAmp = noiseEnv.process()
            let toneAmp = toneEnv.process()

            let body = bodyBPF.process(n) * toneAmp * 3.0
            let crack = crackBPF.process(n) * toneAmp * 2.0
            let snap = hpf.processHP(n * noiseAmp) * 0.6

            let out = body + crack + snap
            if noiseAmp < 0.005 && toneAmp < 0.005 { active = false }
            return out
        }
    }

    /// Hi-hat: noise + 3 metallic resonators, HP filtered. Closed 30ms / open 120ms.
    private struct HatVoice {
        var active: Bool = false
        var ampEnv: ExpEnv = ExpEnv()
        var resonators: [BiquadBPF]
        var hpf: OnePole
        var noise: LCGNoise
        var velocity: Float = 0.0

        // Fewer resonators at lower Q for louder, broader metallic tone
        static let metallicFreqs: [Double] = [6200, 8500, 11000]

        init(sampleRate: Double, seed: UInt32) {
            resonators = Self.metallicFreqs.map { BiquadBPF.bandpass(freq: $0, q: 3.0, sampleRate: sampleRate) }
            hpf = OnePole.highpass(cutoff: 3000, sampleRate: sampleRate)
            noise = LCGNoise(seed: seed)
        }

        mutating func trigger(velocity: Float, isOpen: Bool, sampleRate: Double) {
            active = true
            self.velocity = velocity
            let ms: Double = isOpen ? 120 : 30
            ampEnv = ExpEnv(value: velocity, decay: decayCoeff(ms: ms, sampleRate: sampleRate))
            // Reset resonators for clean attack
            for i in 0..<resonators.count { resonators[i].reset() }
        }

        mutating func render() -> Float {
            guard active else { return 0 }
            let n = noise.next()
            let env = ampEnv.process()

            var sum: Float = 0
            for i in 0..<resonators.count {
                sum += resonators[i].process(n)
            }
            // HPF keeps it bright, no additional attenuation
            let filtered = hpf.processHP(sum)
            let out = filtered * env

            if env < 0.005 { active = false }
            return out
        }
    }

    /// Crash cymbal: noise + wide metallic resonators, long ~500ms decay.
    private struct CrashVoice {
        var active: Bool = false
        var ampEnv: ExpEnv = ExpEnv()
        var resonators: [BiquadBPF]
        var hpf: OnePole
        var noise: LCGNoise
        var velocity: Float = 0.0

        static let metallicFreqs: [Double] = [3000, 4800, 6500, 9000]

        init(sampleRate: Double, seed: UInt32) {
            resonators = Self.metallicFreqs.map { BiquadBPF.bandpass(freq: $0, q: 2.0, sampleRate: sampleRate) }
            hpf = OnePole.highpass(cutoff: 2000, sampleRate: sampleRate)
            noise = LCGNoise(seed: seed)
        }

        mutating func trigger(velocity: Float, sampleRate: Double) {
            active = true
            self.velocity = velocity
            ampEnv = ExpEnv(value: velocity, decay: decayCoeff(ms: 500, sampleRate: sampleRate))
            for i in 0..<resonators.count { resonators[i].reset() }
        }

        mutating func render() -> Float {
            guard active else { return 0 }
            let n = noise.next()
            let env = ampEnv.process()

            var sum: Float = 0
            for i in 0..<resonators.count {
                sum += resonators[i].process(n)
            }
            let filtered = hpf.processHP(sum + n * 0.15)
            let out = filtered * env

            if env < 0.003 { active = false }
            return out
        }
    }

    // MARK: - Render Block

    private static func drumRenderBlock(
        sampleRate: Double,
        pattern: EnergizerPattern,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {

        let triggers = pattern.triggers()
        let bpm = pattern.bpm
        let loopBeats = pattern.loopBeats

        let secondsPerBeat = 60.0 / bpm
        let loopLengthSamples = UInt64(loopBeats * secondsPerBeat * sampleRate)

        struct TriggerInfo {
            let sampleOffset: UInt64
            let channel: DrumChannel
            let instrument: DrumInstrument
            let velocity: Float
            let isOpen: Bool
        }

        let triggerInfos: [TriggerInfo] = triggers.map { t in
            let offset = UInt64(t.beat * secondsPerBeat * sampleRate)
            return TriggerInfo(
                sampleOffset: offset,
                channel: t.channel,
                instrument: t.instrument,
                velocity: Float(t.velocity),
                isOpen: t.isOpen
            )
        }.sorted { $0.sampleOffset < $1.sampleOffset }

        // Smaller voice pools — short decays mean voices free up fast
        let kickCount = 2
        let snareCount = 3
        let hatCount = 4
        let crashCount = 2
        var kicks = [KickVoice](repeating: KickVoice(), count: kickCount)
        var snares = (0..<snareCount).map { i in SnareVoice(sampleRate: sampleRate, seed: UInt32(100 + i * 37)) }
        var hats = (0..<hatCount).map { i in HatVoice(sampleRate: sampleRate, seed: UInt32(200 + i * 53)) }
        var crashes = (0..<crashCount).map { i in CrashVoice(sampleRate: sampleRate, seed: UInt32(300 + i * 61)) }

        var currentSample: UInt64 = 0
        var currentGain: Float = 0.0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftBuf = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuf = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            let target = targetGainPtr.pointee

            for frame in 0..<Int(frameCount) {
                if currentGain < target {
                    currentGain = min(currentGain + gainSmoothing, target)
                } else if currentGain > target {
                    currentGain = max(currentGain - gainSmoothing, target)
                }

                let posInLoop = currentSample % loopLengthSamples

                // Fire triggers at their sample offsets
                for info in triggerInfos {
                    if info.sampleOffset == posInLoop {
                        switch info.instrument {
                        case .kick:
                            var idx = 0
                            for k in 0..<kickCount {
                                if !kicks[k].active { idx = k; break }
                                idx = k
                            }
                            kicks[idx].trigger(velocity: info.velocity, sampleRate: sampleRate)

                        case .snare:
                            var idx = 0
                            for s in 0..<snareCount {
                                if !snares[s].active { idx = s; break }
                                idx = s
                            }
                            snares[idx].trigger(velocity: info.velocity, sampleRate: sampleRate)

                        case .hat:
                            var idx = 0
                            for h in 0..<hatCount {
                                if !hats[h].active { idx = h; break }
                                idx = h
                            }
                            hats[idx].trigger(velocity: info.velocity, isOpen: info.isOpen, sampleRate: sampleRate)

                        case .crash:
                            var idx = 0
                            for c in 0..<crashCount {
                                if !crashes[c].active { idx = c; break }
                                idx = c
                            }
                            crashes[idx].trigger(velocity: info.velocity, sampleRate: sampleRate)
                        }
                    }
                }

                // Render all active voices into stereo mix
                var sumL: Float = 0
                var sumR: Float = 0

                // Kick: center, moderate level
                for k in 0..<kickCount {
                    let sample = kicks[k].render(sampleRate: sampleRate)
                    sumL += sample * 0.7
                    sumR += sample * 0.7
                }

                // Snare: slight left bias
                for s in 0..<snareCount {
                    let sample = snares[s].render()
                    sumL += sample * 0.65
                    sumR += sample * 0.35
                }

                // Hat: alternating L/R
                for h in 0..<hatCount {
                    let sample = hats[h].render()
                    if h % 2 == 0 {
                        sumL += sample * 0.6
                        sumR += sample * 0.3
                    } else {
                        sumL += sample * 0.3
                        sumR += sample * 0.6
                    }
                }

                // Crash: wide stereo
                for c in 0..<crashCount {
                    let sample = crashes[c].render()
                    sumL += sample * 0.3
                    sumR += sample * 0.7
                }

                // Soft-clip + master gain
                let outL = tanhf(sumL) * currentGain * 0.65
                let outR = tanhf(sumR) * currentGain * 0.65

                leftBuf[frame] = outL
                rightBuf[frame] = outR

                currentSample += 1
            }

            return noErr
        }
    }
}
