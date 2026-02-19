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
            // Convert to float in -1..1
            return Float(Int32(bitPattern: state)) / Float(Int32.max)
        }
    }

    /// One-pole filter (LP or HP).
    private struct OnePole {
        var y1: Float = 0.0
        var a: Float = 0.5

        /// Create a lowpass with cutoff in Hz.
        static func lowpass(cutoff: Double, sampleRate: Double) -> OnePole {
            let omega = 2.0 * Double.pi * cutoff / sampleRate
            return OnePole(y1: 0, a: Float(omega / (1.0 + omega)))
        }

        /// Create a highpass with cutoff in Hz.
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

    /// Biquad bandpass filter.
    private struct BiquadBPF {
        var b0: Float, b1: Float, b2: Float
        var a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0
        var y1: Float = 0, y2: Float = 0

        static func bandpass(freq: Double, q: Double, sampleRate: Double) -> BiquadBPF {
            let omega = 2.0 * Double.pi * freq / sampleRate
            let sinW = sin(omega)
            let alpha = sinW / (2.0 * q)
            let a0 = 1.0 + alpha
            return BiquadBPF(
                b0: Float(alpha / a0),
                b1: 0,
                b2: Float(-alpha / a0),
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
    }

    // MARK: - Voice Structs

    /// Kick: sine with pitch envelope (200→55 Hz glide), amp decay ~220ms.
    private struct KickVoice {
        var active: Bool = false
        var phase: Double = 0.0
        var ampEnv: ExpEnv = ExpEnv()
        var pitchEnv: ExpEnv = ExpEnv()
        var velocity: Float = 0.0
        let startFreq: Double = 200.0
        let endFreq: Double = 55.0

        static func decayCoeff(ms: Double, sampleRate: Double) -> Float {
            Float(exp(-1.0 / (ms * 0.001 * sampleRate)))
        }

        mutating func trigger(velocity: Float, sampleRate: Double) {
            active = true
            phase = 0.0
            self.velocity = velocity
            ampEnv = ExpEnv(value: velocity, decay: Self.decayCoeff(ms: 220, sampleRate: sampleRate))
            pitchEnv = ExpEnv(value: 1.0, decay: Self.decayCoeff(ms: 40, sampleRate: sampleRate))
        }

        mutating func render(sampleRate: Double) -> Float {
            guard active else { return 0 }
            let pitchMix = pitchEnv.process()
            let freq = endFreq + (startFreq - endFreq) * Double(pitchMix)
            let sample = Float(sin(2.0 * .pi * phase)) * ampEnv.process()
            phase += freq / sampleRate
            if phase >= 1.0 { phase -= 1.0 }
            if ampEnv.value < 0.001 { active = false }
            return sample
        }
    }

    /// Snare: noise burst + 2 bandpass resonators (body 350 Hz, crack 900 Hz) + HP snap.
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
            bodyBPF = BiquadBPF.bandpass(freq: 350, q: 3.0, sampleRate: sampleRate)
            crackBPF = BiquadBPF.bandpass(freq: 900, q: 2.5, sampleRate: sampleRate)
            hpf = OnePole.highpass(cutoff: 200, sampleRate: sampleRate)
            noise = LCGNoise(seed: seed)
        }

        mutating func trigger(velocity: Float, sampleRate: Double) {
            active = true
            self.velocity = velocity
            let nDecay = KickVoice.decayCoeff(ms: 120, sampleRate: sampleRate)
            let tDecay = KickVoice.decayCoeff(ms: 80, sampleRate: sampleRate)
            noiseEnv = ExpEnv(value: velocity, decay: nDecay)
            toneEnv = ExpEnv(value: velocity * 0.7, decay: tDecay)
        }

        mutating func render() -> Float {
            guard active else { return 0 }
            let n = noise.next()
            let noiseAmp = noiseEnv.process()
            let toneAmp = toneEnv.process()

            let body = bodyBPF.process(n) * toneAmp
            let crack = crackBPF.process(n) * toneAmp * 0.6
            let snap = hpf.processHP(n * noiseAmp) * 0.4

            let out = body + crack + snap
            if noiseAmp < 0.001 && toneAmp < 0.001 { active = false }
            return out
        }
    }

    /// Hi-hat: noise + 5 metallic resonators (5.4–11.2 kHz), closed ~60ms / open ~180ms.
    private struct HatVoice {
        var active: Bool = false
        var ampEnv: ExpEnv = ExpEnv()
        var resonators: [BiquadBPF]
        var hpf: OnePole
        var noise: LCGNoise
        var velocity: Float = 0.0

        static let metallicFreqs: [Double] = [5400, 6800, 8200, 9600, 11200]

        init(sampleRate: Double, seed: UInt32) {
            resonators = Self.metallicFreqs.map { BiquadBPF.bandpass(freq: $0, q: 8.0, sampleRate: sampleRate) }
            hpf = OnePole.highpass(cutoff: 4000, sampleRate: sampleRate)
            noise = LCGNoise(seed: seed)
        }

        mutating func trigger(velocity: Float, isOpen: Bool, sampleRate: Double) {
            active = true
            self.velocity = velocity
            let ms: Double = isOpen ? 180 : 60
            ampEnv = ExpEnv(value: velocity, decay: KickVoice.decayCoeff(ms: ms, sampleRate: sampleRate))
        }

        mutating func render() -> Float {
            guard active else { return 0 }
            let n = noise.next()
            let env = ampEnv.process()

            var sum: Float = 0
            for i in 0..<resonators.count {
                sum += resonators[i].process(n)
            }
            let filtered = hpf.processHP(sum * 0.2)
            let out = filtered * env

            if env < 0.001 { active = false }
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

        // Convert trigger beats to sample offsets within the loop
        let secondsPerBeat = 60.0 / bpm
        let loopLengthSamples = UInt64(Double(loopBeats) * secondsPerBeat * sampleRate)

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

        // Voice pools
        let kickCount = 4
        let snareCount = 6
        let hatCount = 8
        var kicks = [KickVoice](repeating: KickVoice(), count: kickCount)
        var snares = (0..<snareCount).map { i in SnareVoice(sampleRate: sampleRate, seed: UInt32(100 + i * 37)) }
        var hats = (0..<hatCount).map { i in HatVoice(sampleRate: sampleRate, seed: UInt32(200 + i * 53)) }

        var currentSample: UInt64 = 0
        var currentGain: Float = 0.0

        // Track which triggers fired this loop iteration to handle wrap-around
        var lastLoopStart: UInt64 = 0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftBuf = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuf = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            let target = targetGainPtr.pointee

            for frame in 0..<Int(frameCount) {
                // Gain smoothing
                if currentGain < target {
                    currentGain = min(currentGain + gainSmoothing, target)
                } else if currentGain > target {
                    currentGain = max(currentGain - gainSmoothing, target)
                }

                let posInLoop = currentSample % loopLengthSamples
                let loopStart = currentSample - posInLoop

                // Detect loop restart
                if loopStart != lastLoopStart {
                    lastLoopStart = loopStart
                }

                // Check triggers — fire voices at their sample offsets
                for info in triggerInfos {
                    if info.sampleOffset == posInLoop {
                        switch info.instrument {
                        case .kick:
                            // Find inactive kick voice (or steal oldest)
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
                        }
                    }
                }

                // Render all active voices
                var sumL: Float = 0
                var sumR: Float = 0

                for k in 0..<kickCount {
                    let sample = kicks[k].render(sampleRate: sampleRate)
                    if sample != 0 {
                        // Center: equal L/R
                        sumL += sample
                        sumR += sample
                    }
                }

                for s in 0..<snareCount {
                    let sample = snares[s].render()
                    if sample != 0 {
                        // Snare triggers carry their own channel, but rendered voices
                        // don't track channel — use slight left bias for snare overall
                        sumL += sample * 0.8
                        sumR += sample * 0.4
                    }
                }

                for h in 0..<hatCount {
                    let sample = hats[h].render()
                    if sample != 0 {
                        // Hats alternate L/R — since voices don't track channel,
                        // spread evenly with slight alternation
                        let spread: Float = (h % 2 == 0) ? 0.7 : 0.4
                        sumL += sample * spread
                        sumR += sample * (1.0 - spread + 0.1)
                    }
                }

                // Soft-clip via tanh + gain
                let outL = tanhf(sumL * 0.7) * currentGain * 0.75
                let outR = tanhf(sumR * 0.7) * currentGain * 0.75

                leftBuf[frame] = outL
                rightBuf[frame] = outR

                currentSample += 1
            }

            return noErr
        }
    }
}
