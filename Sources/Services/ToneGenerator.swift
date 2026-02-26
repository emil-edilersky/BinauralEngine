import AVFoundation
import Foundation

/// Generates stereo binaural beat tones using AVAudioEngine.
///
/// Produces two pure sine waves — one per ear — at slightly different frequencies.
/// The brain perceives a "beat" at the frequency difference. Uses AVAudioSourceNode
/// with a render callback for real-time, mathematically precise tone generation.
@MainActor
final class ToneGenerator {
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    /// Current phase accumulators for smooth, click-free audio
    private var leftPhase: Double = 0.0
    private var rightPhase: Double = 0.0

    /// Target frequencies (thread-safe access via atomic-like pattern)
    private var _leftFrequency: Double = 0.0
    private var _rightFrequency: Double = 0.0

    /// Volume envelope for fade in/out (0.0 to 1.0)
    private var _targetGain: Float = 0.0
    private var _currentGain: Float = 0.0

    /// Fade duration in seconds
    private let fadeDuration: Double = 1.0

    private(set) var isPlaying: Bool = false
    private var isPaused: Bool = false

    /// Generation counter to invalidate stale stop() closures
    private var generation: Int = 0

    /// Observer for audio device changes
    private var configChangeObserver: NSObjectProtocol?

    /// Last known frequencies for restart after device change
    private var lastLeftFreq: Double = 0
    private var lastRightFreq: Double = 0

    /// Start generating binaural tones at the given frequencies.
    ///
    /// - Parameters:
    ///   - leftFreq: Frequency for the left ear (carrier)
    ///   - rightFreq: Frequency for the right ear (carrier + beat)
    func start(leftFrequency leftFreq: Double, rightFrequency rightFreq: Double) {
        generation += 1  // Invalidate any pending stop() closures
        stop()

        _leftFrequency = leftFreq
        _rightFrequency = rightFreq
        _targetGain = 1.0
        _currentGain = 0.0
        leftPhase = 0.0
        rightPhase = 0.0

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate

        // Capture mutable state for the render callback.
        // These are captured by reference — the callback reads them each render cycle.
        var leftPhase = 0.0
        var rightPhase = 0.0
        var currentGain: Float = 0.0

        // Per-sample gain increment for ~1 second fade
        let gainSmoothing: Float = Float(1.0 / (fadeDuration * sampleRate))

        // We need thread-safe access to these values from the audio thread.
        // Using a simple approach: capture self weakly and read the ivars.
        // The audio render callback runs on a real-time thread, so we avoid
        // locks and just read the Double/Float values (atomic on arm64/x86_64).
        let leftFreqPtr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        let rightFreqPtr = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        let targetGainPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)

        leftFreqPtr.pointee = leftFreq
        rightFreqPtr.pointee = rightFreq
        targetGainPtr.pointee = 1.0

        // Create a stereo format for our source node
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        let node = AVAudioSourceNode(format: stereoFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            let leftFreq = leftFreqPtr.pointee
            let rightFreq = rightFreqPtr.pointee
            let targetGain = targetGainPtr.pointee

            // Phase increments per sample
            let leftIncrement = leftFreq / sampleRate
            let rightIncrement = rightFreq / sampleRate

            for frame in 0..<Int(frameCount) {
                // Smooth gain envelope
                if currentGain < targetGain {
                    currentGain = min(currentGain + gainSmoothing, targetGain)
                } else if currentGain > targetGain {
                    currentGain = max(currentGain - gainSmoothing, targetGain)
                }

                // Generate sine waves
                let leftSample = Float(sin(2.0 * .pi * leftPhase)) * currentGain * 0.5
                let rightSample = Float(sin(2.0 * .pi * rightPhase)) * currentGain * 0.5

                // Write to stereo buffer: channel 0 = left, channel 1 = right
                if ablPointer.count >= 2 {
                    // Non-interleaved stereo
                    let leftBuf = ablPointer[0]
                    let rightBuf = ablPointer[1]
                    let leftPtr = leftBuf.mData!.assumingMemoryBound(to: Float.self)
                    let rightPtr = rightBuf.mData!.assumingMemoryBound(to: Float.self)
                    leftPtr[frame] = leftSample
                    rightPtr[frame] = rightSample
                } else if ablPointer.count == 1 {
                    // Interleaved stereo
                    let buf = ablPointer[0]
                    let ptr = buf.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame * 2] = leftSample
                    ptr[frame * 2 + 1] = rightSample
                }

                // Advance phase (wrap to avoid floating point accumulation errors)
                leftPhase += leftIncrement
                if leftPhase >= 1.0 { leftPhase -= 1.0 }
                rightPhase += rightIncrement
                if rightPhase >= 1.0 { rightPhase -= 1.0 }
            }

            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: mainMixer, format: stereoFormat)

        // Set a reasonable volume on the mixer
        mainMixer.outputVolume = 0.8

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            self.isPlaying = true
            self.lastLeftFreq = leftFreq
            self.lastRightFreq = rightFreq

            // Store pointers for later manipulation
            self._leftFreqPtr = leftFreqPtr
            self._rightFreqPtr = rightFreqPtr
            self._targetGainPtr = targetGainPtr

            // Observe audio device changes (e.g. switching headphones/speakers)
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
            print("ToneGenerator: Failed to start audio engine: \(error)")
            leftFreqPtr.deallocate()
            rightFreqPtr.deallocate()
            targetGainPtr.deallocate()
        }
    }

    /// Restart the engine when the audio output device changes.
    private func handleDeviceChange() {
        guard isPlaying || isPaused || (_targetGainPtr != nil) else { return }
        let wasPaused = isPaused
        let leftFreq = _leftFreqPtr?.pointee ?? lastLeftFreq
        let rightFreq = _rightFreqPtr?.pointee ?? lastRightFreq
        // Tear down old engine and rebuild with new device's sample rate
        forceStop()
        start(leftFrequency: leftFreq, rightFrequency: rightFreq)
        if wasPaused { pause() }
    }

    /// Pointers for communicating with the audio render thread
    private var _leftFreqPtr: UnsafeMutablePointer<Double>?
    private var _rightFreqPtr: UnsafeMutablePointer<Double>?
    private var _targetGainPtr: UnsafeMutablePointer<Float>?

    /// Stop tone generation with a fade-out.
    /// Completion is called after the fade finishes.
    func stop(completion: (() -> Void)? = nil) {
        guard isPlaying, audioEngine != nil else {
            completion?()
            return
        }

        // Trigger fade-out
        _targetGainPtr?.pointee = 0.0

        // Capture current generation — if it changes before the closure fires,
        // another start() or forceStop() already took over teardown.
        let expectedGeneration = generation

        // Wait for fade to complete, then tear down
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

    /// Pause audio output (keeps engine alive for quick resume)
    func pause() {
        isPaused = true
        audioEngine?.pause()
    }

    /// Resume audio output after pause
    func resume() {
        isPaused = false
        try? audioEngine?.start()
    }

    /// Update frequencies live while playing (glitch-free via pointer writes).
    /// The audio thread picks up new values on the next render cycle.
    func updateFrequencies(left: Double, right: Double) {
        _leftFreqPtr?.pointee = left
        _rightFreqPtr?.pointee = right
    }

    /// Immediately stop without fade (for app termination or quick restart)
    func forceStop() {
        generation += 1  // Invalidate any pending stop() closures
        _targetGainPtr?.pointee = 0.0
        tearDownEngine()
    }

    /// Shared teardown — stops engine, detaches node, deallocates pointers.
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

        _leftFreqPtr?.deallocate()
        _rightFreqPtr?.deallocate()
        _targetGainPtr?.deallocate()
        _leftFreqPtr = nil
        _rightFreqPtr = nil
        _targetGainPtr = nil
    }

    deinit {
        _leftFreqPtr?.deallocate()
        _rightFreqPtr?.deallocate()
        _targetGainPtr?.deallocate()
    }
}
