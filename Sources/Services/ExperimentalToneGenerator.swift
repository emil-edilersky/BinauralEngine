import AVFoundation
import Foundation

/// Generates experimental tones (isochronal, noise, crystal bowl, heart coherence).
///
/// Mirrors ToneGenerator architecture: AVAudioEngine + AVAudioSourceNode render callback
/// with UnsafeMutablePointer for lock-free audio thread communication.
@MainActor
final class ExperimentalToneGenerator {
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    /// Volume envelope for fade in/out (0.0 to 1.0)
    private let fadeDuration: Double = 1.0

    private(set) var isPlaying: Bool = false
    private var isPaused: Bool = false

    /// Generation counter to invalidate stale stop() closures
    private var generation: Int = 0

    /// Observer for audio device changes
    private var configChangeObserver: NSObjectProtocol?

    /// Last mode/pattern/variation for restart after device change
    private var lastMode: ExperimentalMode?
    private var lastBowlPattern: CrystalBowlPattern?
    private var lastADHDVariation: ADHDPowerVariation?

    /// Pointers for communicating with the audio render thread
    private var _targetGainPtr: UnsafeMutablePointer<Float>?
    private var _isoFreqPtr: UnsafeMutablePointer<Double>?

    // MARK: - Start

    /// Start generating the given experimental tone.
    func start(mode: ExperimentalMode, bowlPattern: CrystalBowlPattern = .relax, adhdVariation: ADHDPowerVariation = .standard) {
        generation += 1
        stop()

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        let targetGainPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        targetGainPtr.pointee = 1.0

        let isoFreqPtr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        isoFreqPtr.pointee = _isoFreqPtr?.pointee ?? 10.0

        let gainSmoothing: Float = Float(1.0 / (fadeDuration * sampleRate))

        // Pick the right render block based on mode
        let renderBlock: AVAudioSourceNodeRenderBlock

        switch mode {
        case .isochronal:
            renderBlock = Self.isochronalBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                isoFreqPtr: isoFreqPtr,
                gainSmoothing: gainSmoothing
            )
        case .pinkNoise:
            renderBlock = Self.pinkNoiseBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing
            )
        case .brownNoise:
            renderBlock = Self.brownNoiseBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing
            )
        case .crystalBowl:
            renderBlock = Self.crystalBowlBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing,
                modes: bowlPattern.modes,
                clusterLFOs: bowlPattern.clusterLFOs
            )
        case .heartCoherence:
            renderBlock = Self.heartCoherenceBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing
            )
        case .adhdPower:
            renderBlock = Self.adhdPowerBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing,
                periodScale: adhdVariation.periodScale
            )
        case .brainMassage:
            renderBlock = Self.brainMassageBlock(
                sampleRate: sampleRate,
                targetGainPtr: targetGainPtr,
                gainSmoothing: gainSmoothing
            )
        }

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
            self.lastMode = mode
            self.lastBowlPattern = bowlPattern
            self.lastADHDVariation = adhdVariation
            self._targetGainPtr = targetGainPtr
            self._isoFreqPtr = isoFreqPtr

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
            print("ExperimentalToneGenerator: Failed to start audio engine: \(error)")
            targetGainPtr.deallocate()
            isoFreqPtr.deallocate()
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

    /// Pause audio — fully tears down engine to release the audio device.
    /// Resume rebuilds from cached mode/pattern.
    func pause() {
        generation += 1
        tearDownEngine()
        isPaused = true
    }

    func resume() {
        isPaused = false
        if audioEngine == nil, let mode = lastMode {
            // Engine was torn down during pause (device change) — rebuild
            start(mode: mode, bowlPattern: lastBowlPattern ?? .relax, adhdVariation: lastADHDVariation ?? .standard)
        } else {
            try? audioEngine?.start()
        }
    }

    func forceStop() {
        generation += 1
        _targetGainPtr?.pointee = 0.0
        tearDownEngine()
    }

    /// Update isochronal beat frequency live.
    func updateIsochronalFrequency(_ freq: Double) {
        _isoFreqPtr?.pointee = freq
    }

    // MARK: - Device Change

    /// Only fires while playing — paused state has no engine/observer.
    private func handleDeviceChange() {
        guard isPlaying || (_targetGainPtr != nil), let mode = lastMode else { return }
        let pattern = lastBowlPattern ?? .relax
        let variation = lastADHDVariation ?? .standard
        forceStop()
        start(mode: mode, bowlPattern: pattern, adhdVariation: variation)
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
        isPaused = false

        _targetGainPtr?.deallocate()
        _isoFreqPtr?.deallocate()
        _targetGainPtr = nil
        _isoFreqPtr = nil
    }

    deinit {
        _targetGainPtr?.deallocate()
        _isoFreqPtr?.deallocate()
    }

    // MARK: - Render Blocks

    /// Helper: write the same sample to both stereo channels.
    private static func writeStereo(
        _ ablPointer: UnsafeMutableAudioBufferListPointer,
        frame: Int,
        sample: Float
    ) {
        if ablPointer.count >= 2 {
            let leftPtr = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
            let rightPtr = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)
            leftPtr[frame] = sample
            rightPtr[frame] = sample
        } else if ablPointer.count == 1 {
            let ptr = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
            ptr[frame * 2] = sample
            ptr[frame * 2 + 1] = sample
        }
    }

    /// Isochronal: Sine wave gated by a square-wave envelope at the beat frequency.
    private static func isochronalBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        isoFreqPtr: UnsafeMutablePointer<Double>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {
        var carrierPhase: Double = 0.0
        var envelopePhase: Double = 0.0
        var currentGain: Float = 0.0
        let carrierFreq: Double = 100.0 // Warm carrier tone

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee
            let isoFreq = isoFreqPtr.pointee

            let carrierIncrement = carrierFreq / sampleRate
            let envelopeIncrement = isoFreq / sampleRate

            for frame in 0..<Int(frameCount) {
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                // Square-wave gate: on when first half of cycle, off when second half
                let gate: Float = envelopePhase < 0.5 ? 1.0 : 0.0
                let sample = Float(sin(2.0 * .pi * carrierPhase)) * gate * currentGain * 0.5

                writeStereo(ablPointer, frame: frame, sample: sample)

                carrierPhase += carrierIncrement
                if carrierPhase >= 1.0 { carrierPhase -= 1.0 }
                envelopePhase += envelopeIncrement
                if envelopePhase >= 1.0 { envelopePhase -= 1.0 }
            }

            return noErr
        }
    }

    /// Pink noise: Voss-McCartney algorithm — 16 random generators at halving update rates.
    private static func pinkNoiseBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {
        let numGenerators = 16
        var generators = [Float](repeating: 0.0, count: numGenerators)
        var counter: UInt32 = 0
        var runningSum: Float = 0.0
        var currentGain: Float = 0.0
        let normalization: Float = 1.0 / Float(numGenerators)

        // Initialize generators
        for i in 0..<numGenerators {
            let val = Float.random(in: -1.0...1.0)
            generators[i] = val
            runningSum += val
        }

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee

            for frame in 0..<Int(frameCount) {
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                counter &+= 1

                // Update generators based on trailing zeros of counter
                // Generator k updates every 2^k samples
                var changed = counter
                var idx = 0
                while changed & 1 == 0 && idx < numGenerators {
                    changed >>= 1
                    let oldVal = generators[idx]
                    let newVal = Float.random(in: -1.0...1.0)
                    runningSum += (newVal - oldVal)
                    generators[idx] = newVal
                    idx += 1
                }

                let sample = runningSum * normalization * currentGain * 0.4

                writeStereo(ablPointer, frame: frame, sample: sample)
            }

            return noErr
        }
    }

    /// Brown noise: White noise through a leaky integrator.
    private static func brownNoiseBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {
        var lastOutput: Float = 0.0
        var currentGain: Float = 0.0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee

            for frame in 0..<Int(frameCount) {
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                let white = Float.random(in: -1.0...1.0)
                lastOutput = 0.99 * lastOutput + white * 0.02
                // Clamp to prevent rare drift
                lastOutput = max(-1.0, min(1.0, lastOutput))

                let sample = lastOutput * currentGain * 6.4 // Scale up (leaky integrator output is small)

                writeStereo(ablPointer, frame: frame, sample: sample)
            }

            return noErr
        }
    }

    /// Helper: write separate left/right samples to stereo buffer.
    private static func writeStereoSeparate(
        _ ablPointer: UnsafeMutableAudioBufferListPointer,
        frame: Int,
        left: Float,
        right: Float
    ) {
        if ablPointer.count >= 2 {
            let leftPtr = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
            let rightPtr = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)
            leftPtr[frame] = left
            rightPtr[frame] = right
        } else if ablPointer.count == 1 {
            let ptr = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
            ptr[frame * 2] = left
            ptr[frame * 2 + 1] = right
        }
    }

    /// Crystal bowl: Modal cluster synthesis from spectral analysis of real bowls.
    ///
    /// Each pattern provides groups of closely-spaced oscillator frequencies (modal clusters)
    /// that produce natural beating/shimmer. Per-cluster amplitude LFOs create swells.
    /// Stereo is achieved via different L/R initial phases + tiny per-channel frequency offsets.
    /// Subtle micro-FM drift keeps the sound alive. One-pole HPF at 40 Hz removes rumble.
    private static func crystalBowlBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float,
        modes: [(freq: Double, amp: Double, cluster: Int)],
        clusterLFOs: [(rate: Double, depth: Double)]
    ) -> AVAudioSourceNodeRenderBlock {
        let numModes = modes.count
        let numClusters = clusterLFOs.count

        // Per-oscillator state
        var phasesL = [Double](repeating: 0, count: numModes)
        var phasesR = [Double](repeating: 0, count: numModes)
        var amps = [Float](repeating: 0, count: numModes)
        var freqsL = [Double](repeating: 0, count: numModes)
        var freqsR = [Double](repeating: 0, count: numModes)
        var clusterIdx = [Int](repeating: 0, count: numModes)

        // Micro-FM state per oscillator
        var fmPhasesL = [Double](repeating: 0, count: numModes)
        var fmPhasesR = [Double](repeating: 0, count: numModes)
        var fmRates = [Double](repeating: 0, count: numModes)
        var fmDepths = [Double](repeating: 0, count: numModes)

        for i in 0..<numModes {
            let mode = modes[i]
            amps[i] = Float(mode.amp)
            clusterIdx[i] = mode.cluster

            // L/R: same base frequency, different initial phases + tiny R detune
            freqsL[i] = mode.freq
            freqsR[i] = mode.freq + Double.random(in: -0.04...0.04)
            phasesL[i] = Double.random(in: 0..<1.0)
            phasesR[i] = Double.random(in: 0..<1.0)

            // Micro-FM drift: ±0.05–0.25 Hz at 0.05–0.25 Hz
            fmRates[i] = Double.random(in: 0.05...0.25)
            fmDepths[i] = Double.random(in: 0.05...0.20)
            fmPhasesL[i] = Double.random(in: 0..<1.0)
            fmPhasesR[i] = Double.random(in: 0..<1.0)
        }

        // Per-cluster LFO state
        var clusterLFOPhases = [Double](repeating: 0, count: numClusters)
        var clusterLFORates = [Double](repeating: 0, count: numClusters)
        var clusterLFODepths = [Float](repeating: 0, count: numClusters)

        // Per-oscillator slow variation (so modes within a cluster don't pulse identically)
        var perOscLFOPhases = [Double](repeating: 0, count: numModes)
        var perOscLFORates = [Double](repeating: 0, count: numModes)

        for c in 0..<numClusters {
            clusterLFOPhases[c] = Double.random(in: 0..<1.0)
            clusterLFORates[c] = clusterLFOs[c].rate
            clusterLFODepths[c] = Float(clusterLFOs[c].depth)
        }

        for i in 0..<numModes {
            perOscLFOPhases[i] = Double.random(in: 0..<1.0)
            perOscLFORates[i] = Double.random(in: 0.03...0.15)
        }

        // HPF state (one-pole at ~40 Hz)
        let hpfAlpha: Float = {
            let omega = 2.0 * Double.pi * 40.0 / sampleRate
            return Float(1.0 / (1.0 + omega))
        }()
        var hpfPrevInL: Float = 0
        var hpfPrevInR: Float = 0
        var hpfOutL: Float = 0
        var hpfOutR: Float = 0

        var currentGain: Float = 0.0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee
            let dt = 1.0 / sampleRate

            for frame in 0..<Int(frameCount) {
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                var sumL: Float = 0
                var sumR: Float = 0

                for i in 0..<numModes {
                    let c = clusterIdx[i]

                    // Cluster amplitude LFO
                    let depth = clusterLFODepths[c]
                    let clusterEnv = (1.0 - depth) + depth * Float(0.5 + 0.5 * sin(2.0 * .pi * clusterLFOPhases[c]))

                    // Per-oscillator slow variation
                    let perOscVar = Float(0.92 + 0.08 * sin(2.0 * .pi * perOscLFOPhases[i]))

                    let ampEnv = clusterEnv * perOscVar

                    // Micro-FM for L/R
                    let fmL = Float(fmDepths[i] * sin(2.0 * .pi * fmPhasesL[i]))
                    let fmR = Float(fmDepths[i] * sin(2.0 * .pi * fmPhasesR[i]))

                    // Oscillator output
                    let oscL = Float(sin(2.0 * .pi * phasesL[i]))
                    let oscR = Float(sin(2.0 * .pi * phasesR[i]))

                    sumL += oscL * amps[i] * ampEnv
                    sumR += oscR * amps[i] * ampEnv

                    // Advance oscillator phases (base freq + micro-FM)
                    phasesL[i] += (freqsL[i] + Double(fmL)) * dt
                    if phasesL[i] >= 1.0 { phasesL[i] -= 1.0 }
                    phasesR[i] += (freqsR[i] + Double(fmR)) * dt
                    if phasesR[i] >= 1.0 { phasesR[i] -= 1.0 }

                    // Advance micro-FM phases
                    fmPhasesL[i] += fmRates[i] * dt
                    if fmPhasesL[i] >= 1.0 { fmPhasesL[i] -= 1.0 }
                    fmPhasesR[i] += fmRates[i] * dt
                    if fmPhasesR[i] >= 1.0 { fmPhasesR[i] -= 1.0 }

                    // Advance per-oscillator variation
                    perOscLFOPhases[i] += perOscLFORates[i] * dt
                    if perOscLFOPhases[i] >= 1.0 { perOscLFOPhases[i] -= 1.0 }
                }

                // Advance cluster LFOs (once per frame, not per oscillator)
                for c in 0..<numClusters {
                    clusterLFOPhases[c] += clusterLFORates[c] * dt
                    if clusterLFOPhases[c] >= 1.0 { clusterLFOPhases[c] -= 1.0 }
                }

                // One-pole HPF
                let newHpfL = hpfAlpha * (hpfOutL + sumL - hpfPrevInL)
                let newHpfR = hpfAlpha * (hpfOutR + sumR - hpfPrevInR)
                hpfPrevInL = sumL
                hpfPrevInR = sumR
                hpfOutL = newHpfL
                hpfOutR = newHpfR

                // Output with gain — scale to reasonable level
                let outL = hpfOutL * currentGain * 0.35
                let outR = hpfOutR * currentGain * 0.35

                writeStereoSeparate(ablPointer, frame: frame, left: outL, right: outR)
            }

            return noErr
        }
    }

    /// Heart coherence: 100 Hz carrier amplitude-modulated by a 0.1 Hz sine (6 breaths/min).
    private static func heartCoherenceBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {
        var carrierPhase: Double = 0.0
        var modPhase: Double = 0.0
        var currentGain: Float = 0.0
        let carrierFreq: Double = 100.0
        let modFreq: Double = 0.1 // 6 breaths per minute

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee

            let carrierIncrement = carrierFreq / sampleRate
            let modIncrement = modFreq / sampleRate

            for frame in 0..<Int(frameCount) {
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                // AM: carrier × (0.5 + 0.5 * modulator) to keep output 0..1 range
                let modulator = Float(0.5 + 0.5 * sin(2.0 * .pi * modPhase))
                let carrier = Float(sin(2.0 * .pi * carrierPhase))
                let sample = carrier * modulator * currentGain * 0.5

                writeStereo(ablPointer, frame: frame, sample: sample)

                carrierPhase += carrierIncrement
                if carrierPhase >= 1.0 { carrierPhase -= 1.0 }
                modPhase += modIncrement
                if modPhase >= 1.0 { modPhase -= 1.0 }
            }

            return noErr
        }
    }

    /// ADHD Power: Low harmonic drone with asymmetric swell envelope and fast mid-band pulsing.
    ///
    /// Based on detailed spectral analysis of effective ADHD focus music:
    /// - 6 oscillators: 55.26, 108.84, 164.02, 217.94, 330.99, 391.89 Hz
    /// - Two groups: Low (55, 109) and Mid (164, 218, 331, 392)
    /// - Slow asymmetric swell at 0.6166 Hz (1.62s): slow rise + sharp snap-back
    /// - Fast sinusoidal pulse at 4.925 Hz applied to mid group only
    /// - Macro wobble at ~0.15 Hz
    /// - Gentle one-pole LPF at ~750 Hz
    /// - Same frequencies L/R with different initial phases + slight panning
    private static func adhdPowerBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float,
        periodScale: Double = 1.0
    ) -> AVAudioSourceNodeRenderBlock {
        // --- Oscillator setup ---
        // 6 partials: freq, relative amplitude, pan (0=center, <0=left, >0=right)
        let partials: [(freq: Double, amp: Float, pan: Float)] = [
            (55.26,  0.66, 0.0),     // Low group — centered
            (108.84, 1.00, 0.0),     // Low group — centered
            (164.02, 0.16, -0.15),   // Mid group — slightly left
            (217.94, 0.18, -0.15),   // Mid group — slightly left
            (330.99, 0.11, 0.15),    // Mid group — slightly right
            (391.89, 0.16, 0.15),    // Mid group — slightly right
        ]
        let numPartials = partials.count
        let lowGroupCount = 2  // first 2 are low group

        // Per-oscillator state: L/R phases (different initial phases for stereo)
        var phasesL = [Double](repeating: 0, count: numPartials)
        var phasesR = [Double](repeating: 0, count: numPartials)
        for i in 0..<numPartials {
            phasesL[i] = 0.0
            phasesR[i] = Double.random(in: 0..<1.0)  // Random R phase offset
        }

        // Pre-compute per-channel gains from pan
        var gainL = [Float](repeating: 0, count: numPartials)
        var gainR = [Float](repeating: 0, count: numPartials)
        for i in 0..<numPartials {
            let p = partials[i].pan
            // Equal-power pan: center=0 gives 0.707/0.707, full L/R gives 1.0/0.0
            let angle = Double((p + 1.0) * 0.5) * .pi / 2.0
            gainL[i] = Float(cos(angle)) * partials[i].amp
            gainR[i] = Float(sin(angle)) * partials[i].amp
        }

        // --- Envelope state (scaled by periodScale for variations) ---
        let slowPeriod: Double = 1.62 * periodScale     // 0.6166 Hz standard
        let fastFreq: Double = 4.925 / periodScale      // scaled inversely
        let macroFreq: Double = 0.15 / periodScale

        var slowTime: Double = Double.random(in: 0..<slowPeriod)
        var fastPhase: Double = Double.random(in: 0..<1.0)
        var macroPhase: Double = Double.random(in: 0..<1.0)

        // --- One-pole LPF state (per channel) ---
        // fc ~750 Hz, gentle rolloff
        let lpfAlpha: Float = {
            let omega = 2.0 * Double.pi * 750.0 / sampleRate
            return Float(omega / (1.0 + omega))
        }()
        var lpfL: Float = 0.0
        var lpfR: Float = 0.0

        var currentGain: Float = 0.0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetGain = targetGainPtr.pointee

            let dt = 1.0 / sampleRate

            for frame in 0..<Int(frameCount) {
                // Master gain smoothing
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                // --- Slow envelope: narrow pulse with sharp attack + snap-back ---
                // Narrow pulse shape produces rich harmonics (the "thump" / drum beat).
                // Only ~35% of cycle is active; rest is near-silent.
                let p = slowTime / slowPeriod
                let shape: Float
                if p <= 0.30 {
                    // Fast exponential rise (steeper than smoothstep → richer harmonics)
                    let t_norm = p / 0.30
                    let t2 = t_norm * t_norm
                    shape = Float(t2 * t2)  // t^4 — sharper rise
                } else if p <= 0.36 {
                    // Brief peak plateau
                    shape = 1.0
                } else if p <= 0.40 {
                    // Very fast exponential snap-back
                    let t_norm = (p - 0.36) / 0.04
                    shape = Float(exp(-18.0 * Double(t_norm)))
                } else {
                    // Rest at near-silence (60% of cycle)
                    shape = 0.0
                }
                // Moderate floor — drone stays present, transient is felt not chopped
                let envSlow = 0.25 + 0.75 * shape

                // --- Fast pulse (4.925 Hz, sharply shaped = "metronome click") ---
                // Power of 3.0 creates narrow spiky peaks, deep modulation
                let envFastRaw = Float(0.5 * (1.0 + sin(2.0 * .pi * fastPhase)))
                let envFast = powf(envFastRaw, 3.0)

                // --- Macro wobble ---
                let envMacro = Float(0.85 + 0.15 * sin(2.0 * .pi * macroPhase))

                // --- Modulation chains ---
                let aLow = envSlow * envMacro
                // Mid: direct fast pulse multiplication (full depth, no floor blend)
                let aMid = envSlow * envFast * envMacro

                // --- Sum oscillators ---
                var sumL: Float = 0
                var sumR: Float = 0

                for i in 0..<numPartials {
                    let sinL = Float(sin(2.0 * .pi * phasesL[i]))
                    let sinR = Float(sin(2.0 * .pi * phasesR[i]))

                    let env = (i < lowGroupCount) ? aLow : aMid

                    sumL += sinL * gainL[i] * env
                    sumR += sinR * gainR[i] * env

                    // Advance phases
                    let inc = partials[i].freq * dt
                    phasesL[i] += inc
                    if phasesL[i] >= 1.0 { phasesL[i] -= 1.0 }
                    phasesR[i] += inc
                    if phasesR[i] >= 1.0 { phasesR[i] -= 1.0 }
                }

                // --- One-pole LPF ---
                lpfL += lpfAlpha * (sumL - lpfL)
                lpfR += lpfAlpha * (sumR - lpfR)

                // Scale and apply master gain
                let outL = lpfL * currentGain * 0.60
                let outR = lpfR * currentGain * 0.60

                writeStereoSeparate(ablPointer, frame: frame, left: outL, right: outR)

                // Advance envelope clocks
                slowTime += dt
                if slowTime >= slowPeriod { slowTime -= slowPeriod }
                fastPhase += fastFreq * dt
                if fastPhase >= 1.0 { fastPhase -= 1.0 }
                macroPhase += macroFreq * dt
                if macroPhase >= 1.0 { macroPhase -= 1.0 }
            }

            return noErr
        }
    }

    // MARK: - Brain Massage (Hemi-Sync)

    /// Multi-layer binaural + isochronic brain hemisphere synchronization.
    ///
    /// Based on spectral analysis of "Hemi Sync Extended" by Frequency Tuning.
    /// Three binaural layers at different carrier frequencies create overlapping
    /// beat patterns that produce a "moving" sensation across the stereo field.
    ///
    /// Layer 1 (sub):      L=69.3 Hz,  R=74.8 Hz  → 5.5 Hz theta beat
    /// Layer 2 (low-mid):  L=158.0 Hz, R=165.0 Hz → 7.0 Hz theta-alpha beat
    /// Layer 3 (mid):      271.7 / 277.2 / 282.7 Hz shared → 5.5 & 11 Hz monaural beating
    /// Isochronic:         5.5 Hz amplitude modulation (depth 0.30)
    /// Macro swell:        0.167 Hz (~6s breathing cycle)
    private static func brainMassageBlock(
        sampleRate: Double,
        targetGainPtr: UnsafeMutablePointer<Float>,
        gainSmoothing: Float
    ) -> AVAudioSourceNodeRenderBlock {

        let dt = 1.0 / sampleRate

        // Layer 1: Primary binaural pair (sub bass, ~72 Hz center)
        let l1FreqL = 69.3      // Left ear
        let l1FreqR = 74.8      // Right ear — 5.5 Hz beat
        let l1Amp: Float = 1.0

        // Layer 2: Secondary binaural pair (low-mid, ~161 Hz center)
        let l2FreqL = 158.0
        let l2FreqR = 165.0     // 7.0 Hz beat
        let l2Amp: Float = 0.25

        // Layer 3: Shared mid cluster (monaural beating)
        let l3Freq1 = 271.7     // creates 5.5 Hz beat with l3Freq2
        let l3Freq2 = 277.2     // center tone
        let l3Freq3 = 282.7     // creates 5.5 Hz beat with l3Freq2, 11 Hz with l3Freq1
        let l3Amp1: Float = 0.22
        let l3Amp2: Float = 0.40
        let l3Amp3: Float = 0.20

        // Isochronic amplitude modulation
        let isoFreq = 5.5       // Hz — matches primary binaural beat
        let isoDepth: Float = 0.30

        // Slow macro swell
        let macroFreq = 0.167   // ~6s period
        let macroDepth: Float = 0.15

        // Phase accumulators (Double precision for frequency accuracy)
        var phaseL1L = 0.0
        var phaseL1R = 0.0
        var phaseL2L = 0.0
        var phaseL2R = 0.0
        var phaseL3a = 0.0
        var phaseL3b = 0.0
        var phaseL3c = 0.0
        var isoPhase = 0.0
        var macroPhase = 0.0

        var currentGain: Float = 0.0

        return { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftBuf = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuf = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            let target = targetGainPtr.pointee

            for i in 0..<Int(frameCount) {
                currentGain += (target - currentGain) * gainSmoothing

                // Isochronic envelope: smooth sinusoidal modulation
                let isoEnv = 1.0 - isoDepth + isoDepth * Float(0.5 + 0.5 * sin(2.0 * .pi * isoPhase))

                // Macro swell envelope
                let macroEnv = 1.0 - macroDepth + macroDepth * Float(0.5 + 0.5 * sin(2.0 * .pi * macroPhase))

                let envelope = currentGain * isoEnv * macroEnv

                // Layer 1: binaural sub — separate L/R
                let l1L = l1Amp * Float(sin(2.0 * .pi * phaseL1L))
                let l1R = l1Amp * Float(sin(2.0 * .pi * phaseL1R))

                // Layer 2: binaural low-mid — separate L/R
                let l2L = l2Amp * Float(sin(2.0 * .pi * phaseL2L))
                let l2R = l2Amp * Float(sin(2.0 * .pi * phaseL2R))

                // Layer 3: shared mid cluster — same in both channels
                let l3 = l3Amp1 * Float(sin(2.0 * .pi * phaseL3a))
                     + l3Amp2 * Float(sin(2.0 * .pi * phaseL3b))
                     + l3Amp3 * Float(sin(2.0 * .pi * phaseL3c))

                // Mix: layers 1+2 are stereo-split, layer 3 is mono
                leftBuf[i]  = (l1L + l2L + l3) * envelope
                rightBuf[i] = (l1R + l2R + l3) * envelope

                // Advance all phase accumulators
                phaseL1L += l1FreqL * dt
                if phaseL1L >= 1.0 { phaseL1L -= 1.0 }
                phaseL1R += l1FreqR * dt
                if phaseL1R >= 1.0 { phaseL1R -= 1.0 }

                phaseL2L += l2FreqL * dt
                if phaseL2L >= 1.0 { phaseL2L -= 1.0 }
                phaseL2R += l2FreqR * dt
                if phaseL2R >= 1.0 { phaseL2R -= 1.0 }

                phaseL3a += l3Freq1 * dt
                if phaseL3a >= 1.0 { phaseL3a -= 1.0 }
                phaseL3b += l3Freq2 * dt
                if phaseL3b >= 1.0 { phaseL3b -= 1.0 }
                phaseL3c += l3Freq3 * dt
                if phaseL3c >= 1.0 { phaseL3c -= 1.0 }

                isoPhase += isoFreq * dt
                if isoPhase >= 1.0 { isoPhase -= 1.0 }
                macroPhase += macroFreq * dt
                if macroPhase >= 1.0 { macroPhase -= 1.0 }
            }

            return noErr
        }
    }
}
