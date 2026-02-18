import SwiftUI
import AppKit

/// Main menu bar popover view.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCarrierTuning = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            presetsSection
            Divider()
            controlsSection
            Divider()
            carrierDisclosure
            if showAbout {
                Divider()
                aboutSection
            }
            Divider()
            footerSection
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header (with playback controls)

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("BinauralEngine")
                    .font(.headline)
                Text("Pure binaural beats")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Playback controls — always visible
            playbackControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            if appState.hasActiveSession {
                // Countdown with timer icon
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(appState.sessionTimer.formattedRemaining)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }

                // Play/Pause
                Button {
                    appState.togglePlayPause()
                } label: {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                // Stop
                Button {
                    appState.stopSession()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Preset.allCases) { preset in
                presetRow(preset)
            }
        }
        .padding(.vertical, 6)
    }

    private func presetRow(_ preset: Preset) -> some View {
        Button {
            appState.selectedPreset = preset
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset == appState.selectedPreset ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(preset == appState.selectedPreset ? .blue : .secondary)
                    .font(.body)

                Image(systemName: preset.iconName)
                    .frame(width: 18)
                    .foregroundStyle(preset == appState.selectedPreset ? .primary : .secondary)

                Text(preset.displayName)
                    .font(.body)

                Spacer()

                Text(preset.frequencyLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            preset == appState.selectedPreset
                ? Color.blue.opacity(0.08)
                : Color.clear
        )
    }

    // MARK: - Duration buttons

    private var controlsSection: some View {
        HStack(spacing: 6) {
            ForEach(SessionDuration.allCases) { duration in
                durationButton(duration)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func durationButton(_ duration: SessionDuration) -> some View {
        Button {
            appState.startSession(duration: duration)
        } label: {
            Text(duration.displayLabel)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Carrier Tuning (foldable)

    private var carrierDisclosure: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: showCarrierTuning ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text("Carrier Tuning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(appState.carrierFrequency)) Hz")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCarrierTuning.toggle()
                }
            }

            if showCarrierTuning {
                VStack(spacing: 4) {
                    Slider(
                        value: $appState.carrierFrequency,
                        in: 40...500,
                        step: 10
                    )
                    .controlSize(.small)

                    HStack {
                        Text("40")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Reset") {
                            appState.carrierFrequency = 100
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue.opacity(0.7))
                        Spacer()
                        Text("500")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generates pure binaural beat tones to help guide your brain into focus, relaxation, or sleep states.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Based on brainwave entrainment research. Use with headphones for the binaural effect.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\u{00A9} 2025 BinauralEngine. Open source.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Hide") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAbout = false
                    }
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.blue.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Quit") {
                appState.cleanup()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Spacer()

            if !showAbout {
                Button("About") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAbout = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .font(.caption2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
