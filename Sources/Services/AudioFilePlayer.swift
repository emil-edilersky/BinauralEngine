import AVFoundation
import Foundation
/// Plays mp3 audio files from the app bundle for Energizer sessions.
///
/// AVAudioEngine with fade in/out, device change handling, and
/// generation counter for safe teardown.
/// Plays the track once at its original duration (no looping).
@MainActor
final class AudioFilePlayer {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private let fadeDuration: Double = 0.5
    private(set) var isPlaying: Bool = false
    private var isPaused: Bool = false
    private var generation: Int = 0

    private var lastFilename: String?

    /// Duration of the currently loaded file in seconds (set after start).
    private(set) var fileDuration: TimeInterval = 0

    private var configChangeObserver: NSObjectProtocol?

    /// Called when audio route changes cause the session to stop.
    var onInterruption: (() -> Void)?

    // MARK: - Start

    func start(filename: String) {
        generation += 1
        stop()

        guard let fileURL = Self.bundleURL(for: filename) else {
            print("AudioFilePlayer: could not find \(filename).mp3 in bundle")
            return
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            print("AudioFilePlayer: failed to open \(filename).mp3: \(error)")
            return
        }

        let format = audioFile.processingFormat
        fileDuration = Double(audioFile.length) / format.sampleRate

        let engine = AVAudioEngine()
        engine.isAutoShutdownEnabled = true
        let player = AVAudioPlayerNode()
        let mainMixer = engine.mainMixerNode

        engine.attach(player)
        engine.connect(player, to: mainMixer, format: format)

        // Start quiet, fade in
        mainMixer.outputVolume = 0.0

        do {
            try engine.start()
        } catch {
            print("AudioFilePlayer: engine start failed: \(error)")
            return
        }

        // Schedule file for single playback (no looping)
        player.scheduleFile(audioFile, at: nil)
        player.play()

        // Fade in
        let fadeSteps = 20
        let stepDuration = fadeDuration / Double(fadeSteps)
        for i in 1...fadeSteps {
            let volume = Float(i) / Float(fadeSteps) * 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak engine] in
                engine?.mainMixerNode.outputVolume = volume
            }
        }

        self.audioEngine = engine
        self.playerNode = player
        self.lastFilename = filename
        self.isPlaying = true

        // When audio route changes (headphones disconnect, etc.) and the
        // engine stops running, stop the session instead of fighting for the device.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying, !(self.audioEngine?.isRunning ?? false) else { return }
                self.forceStop()
                self.onInterruption?()
            }
        }
    }

    // MARK: - Lifecycle

    func stop(completion: (() -> Void)? = nil) {
        guard isPlaying, let engine = audioEngine else {
            completion?()
            return
        }

        // Fade out via mixer volume
        let fadeSteps = 20
        let stepDuration = fadeDuration / Double(fadeSteps)
        let currentVolume = engine.mainMixerNode.outputVolume

        for i in 1...fadeSteps {
            let volume = currentVolume * (1.0 - Float(i) / Float(fadeSteps))
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak engine] in
                engine?.mainMixerNode.outputVolume = volume
            }
        }

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
    /// Resume rebuilds from cached filename.
    func pause() {
        generation += 1
        tearDownEngine()
        isPaused = true
    }

    func resume() {
        isPaused = false
        if audioEngine == nil, let filename = lastFilename {
            // Engine was torn down during pause (device change) — rebuild
            start(filename: filename)
        } else {
            try? audioEngine?.start()
            playerNode?.play()
        }
    }

    func forceStop() {
        generation += 1
        tearDownEngine()
    }

    // MARK: - Teardown

    private func tearDownEngine() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        playerNode?.stop()
        if let engine = audioEngine {
            engine.stop()
            if let node = playerNode, engine.attachedNodes.contains(node) {
                engine.detach(node)
            }
        }
        audioEngine = nil
        playerNode = nil
        isPlaying = false
        isPaused = false
    }

    // MARK: - Bundle Lookup

    /// Finds the mp3 file in the SPM resource bundle.
    static func bundleURL(for filename: String) -> URL? {
        // SPM copies Resources/ into BinauralEngine_BinauralEngine.bundle
        if let bundleURL = Bundle.main.url(forResource: "BinauralEngine_BinauralEngine", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL) {
            if let url = resourceBundle.url(forResource: filename, withExtension: "mp3", subdirectory: "Resources/Energizers") {
                return url
            }
            if let url = resourceBundle.url(forResource: filename, withExtension: "mp3", subdirectory: "Energizers") {
                return url
            }
        }
        return Bundle.main.url(forResource: filename, withExtension: "mp3", subdirectory: "Energizers")
    }

    deinit {
        // Nothing to deallocate — no raw pointers
    }
}
