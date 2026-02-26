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
            tabSwitcher
            Divider()
            // Both tabs always rendered (ZStack) to prevent popover resize/dismiss.
            // Only the active tab is visible and interactive.
            ZStack {
                VStack(spacing: 0) {
                    presetsSection
                    Divider()
                    controlsSection
                    Divider()
                    carrierDisclosure
                }
                .opacity(appState.activeTab == .binaural ? 1 : 0)
                .allowsHitTesting(appState.activeTab == .binaural)

                VStack(spacing: 0) {
                    experimentalSection
                    Divider()
                    controlsSection
                    Divider()
                    modeSettingsSection
                }
                .opacity(appState.activeTab == .experimental ? 1 : 0)
                .allowsHitTesting(appState.activeTab == .experimental)

                VStack(spacing: 0) {
                    energizerSection
                    Spacer(minLength: 0)
                }
                .opacity(appState.activeTab == .energizer ? 1 : 0)
                .allowsHitTesting(appState.activeTab == .energizer)
            }
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
                Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.togglePlayPause()
                    }

                // Stop
                Image(systemName: "stop.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.stopSession()
                    }
            }
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Text(tab.displayName)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(appState.activeTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        VStack(spacing: 0) {
                            Spacer()
                            if appState.activeTab == tab {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(height: 2)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.activeTab = tab
                    }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Experimental Modes

    private var experimentalSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ExperimentalMode.allCases) { mode in
                experimentalModeRow(mode)
            }
        }
        .padding(.vertical, 6)
    }

    private func experimentalModeRow(_ mode: ExperimentalMode) -> some View {
        // Only highlight as active when experimental is actually playing (or idle)
        let isActive = mode == appState.selectedExperimentalMode
            && (appState.playingTab == nil || appState.playingTab == .experimental)

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .blue : .secondary)
                .font(.body)

            Image(systemName: mode.iconName)
                .frame(width: 18)
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(mode.displayName)
                .font(.body)

            Spacer()

            Text(mode.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.08) : Color.clear)
        .onTapGesture {
            appState.selectedExperimentalMode = mode
        }
    }

    // MARK: - Mode Settings (always present — prevents popover resize/dismiss)

    /// All mode settings rendered in a ZStack so the section never changes height.
    /// Only the active mode's content is visible and interactive.
    private var modeSettingsSection: some View {
        ZStack {
            // Isochronal frequency chips
            HStack(spacing: 4) {
                ForEach(IsochronalFrequency.allCases) { freq in
                    isochronalChip(freq)
                }
            }
            .opacity(appState.selectedExperimentalMode == .isochronal ? 1 : 0)
            .allowsHitTesting(appState.selectedExperimentalMode == .isochronal)

            // Crystal bowl pattern chips
            HStack(spacing: 4) {
                ForEach(CrystalBowlPattern.allCases) { pattern in
                    bowlPatternChip(pattern)
                }
            }
            .opacity(appState.selectedExperimentalMode == .crystalBowl ? 1 : 0)
            .allowsHitTesting(appState.selectedExperimentalMode == .crystalBowl)

            // ADHD variation chips
            HStack(spacing: 4) {
                ForEach(ADHDPowerVariation.allCases) { variation in
                    adhdVariationChip(variation)
                }
            }
            .opacity(appState.selectedExperimentalMode == .adhdPower ? 1 : 0)
            .allowsHitTesting(appState.selectedExperimentalMode == .adhdPower)

            // Description placeholder for modes without sub-settings
            Text(appState.selectedExperimentalMode.description)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .opacity(
                    [.pinkNoise, .brownNoise, .heartCoherence, .brainMassage]
                        .contains(appState.selectedExperimentalMode) ? 1 : 0
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func isochronalChip(_ freq: IsochronalFrequency) -> some View {
        let isSelected = appState.isochronalFrequency == freq.rawValue

        return VStack(spacing: 2) {
            Text(freq.displayLabel)
                .font(.system(.caption, design: .rounded, weight: .semibold))
            Text(freq.bandLabel)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 0.9 : 0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.blue.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.isochronalFrequency = freq.rawValue
        }
    }

    private func bowlPatternChip(_ pattern: CrystalBowlPattern) -> some View {
        let isSelected = appState.crystalBowlPattern == pattern

        return VStack(spacing: 2) {
            Image(systemName: pattern.iconName)
                .font(.system(size: 10))
            Text(pattern.displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.blue.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.crystalBowlPattern = pattern
        }
    }

    private func adhdVariationChip(_ variation: ADHDPowerVariation) -> some View {
        let isSelected = appState.adhdPowerVariation == variation

        return VStack(spacing: 2) {
            Image(systemName: variation.iconName)
                .font(.system(size: 10))
            Text(variation.displayName)
                .font(.system(size: 8, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.blue.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.adhdPowerVariation = variation
        }
    }

    // MARK: - Energizer

    private var energizerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(EnergizerPattern.allCases) { pattern in
                energizerPatternRow(pattern)
            }
        }
        .padding(.vertical, 6)
    }

    private func energizerPatternRow(_ pattern: EnergizerPattern) -> some View {
        let isActive = pattern == appState.selectedEnergizerPattern

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .blue : .secondary)
                .font(.body)

            Image(systemName: pattern.iconName)
                .frame(width: 18)
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(pattern.displayName)
                .font(.body)

            Spacer()

            Text(pattern.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.08) : Color.clear)
        .onTapGesture {
            if appState.selectedEnergizerPattern == pattern {
                appState.selectedEnergizerPattern = nil
            } else {
                appState.selectedEnergizerPattern = pattern
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
        // Only highlight as active when binaural is actually playing (or idle)
        let isActive = preset == appState.selectedPreset
            && (appState.playingTab == nil || appState.playingTab == .binaural)

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .blue : .secondary)
                .font(.body)

            Image(systemName: preset.iconName)
                .frame(width: 18)
                .foregroundStyle(isActive ? .primary : .secondary)

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
        .background(isActive ? Color.blue.opacity(0.08) : Color.clear)
        .onTapGesture {
            appState.selectedPreset = preset
        }
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
            .contentShape(Rectangle())
            .onTapGesture {
                appState.startSession(duration: duration)
            }
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
                showCarrierTuning.toggle()
            }

            if showCarrierTuning {
                VStack(spacing: 4) {
                    Slider(
                        value: $appState.carrierFrequency,
                        in: 20...500,
                        step: 10
                    )
                    .controlSize(.small)

                    HStack {
                        Text("20")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Reset")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                            .onTapGesture {
                                appState.carrierFrequency = 100
                            }
                        Spacer()
                        Text("500")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Dynamic: current preset/mode description
            VStack(alignment: .leading, spacing: 2) {
                Text(currentModeName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(currentModeAbout)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Static: generic app about
            VStack(alignment: .leading, spacing: 4) {
                Text("Pure tone generator for brainwave entrainment. No music, no ads. Use headphones for binaural modes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\u{00A9} 2025 BinauralEngine. Open source. (\(BuildVersion.commitHash))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Text("Hide")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.7))
                    .onTapGesture {
                        showAbout = false
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var currentModeName: String {
        switch appState.activeTab {
        case .binaural:     return appState.selectedPreset.displayName
        case .experimental: return appState.selectedExperimentalMode.displayName
        case .energizer:    return appState.selectedEnergizerPattern?.displayName ?? "Energizer"
        }
    }

    private var currentModeAbout: String {
        switch appState.activeTab {
        case .binaural:     return appState.selectedPreset.aboutDescription
        case .experimental: return appState.selectedExperimentalMode.aboutDescription
        case .energizer:    return appState.selectedEnergizerPattern?.aboutDescription ?? "Short, intense drum-based sessions. Select a pattern to start."
        }
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
                Text("About")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                    .onTapGesture {
                        showAbout = true
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
