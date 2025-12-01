//
//  AutoEditSettingsStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct AutoEditSettingsStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    @State private var targetLength: TargetLength = .standard
    @State private var pace: Pace = .normal
    @State private var style: AutoEditStyle?
    @State private var removeNoise: Bool = true
    @State private var smoothLoudness: Bool = true
    @State private var overallVolume: Double = 0.0
    @State private var colorLook: ColorLookPreset = .neutral
    @State private var qualityThreshold: Float = 0.5
    
    // Effects & Transitions
    @State private var selectedTransitions: Set<TransitionType> = [.crossfade]
    @State private var transitionDuration: Double = 0.25
    @State private var enableFadeToBlack: Bool = true
    @State private var fadeToBlackDuration: Double = 2.0
    @State private var selectedEffects: Set<VideoEffect> = []
    
    private var currentSettings: AutoEditSettings {
        AutoEditSettings(
            targetLengthSeconds: targetLengthSeconds,
            pace: pace,
            style: style ?? defaultStyle,
            removeNoise: removeNoise,
            normalizeLoudness: smoothLoudness,
            baseColorLook: colorLook,
            qualityThreshold: qualityThreshold,
            transitionTypes: Array(selectedTransitions),
            transitionDuration: transitionDuration,
            enableFadeToBlack: enableFadeToBlack,
            fadeToBlackDuration: fadeToBlackDuration,
            effects: Array(selectedEffects)
        )
    }
    
    private var defaultStyle: AutoEditStyle {
        AutoEditStyle.defaultStyle(for: projectViewModel.type)
    }
    
    private var targetLengthSeconds: Double? {
        switch targetLength {
        case .short: return 60.0
        case .standard: return 180.0
        case .extended: return 600.0
        case .full: return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // App Logo in top-left
            HStack {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .compositingGroup()
                    .padding(.leading, 20)
                    .padding(.top, 12)
                
                Spacer()
            }
            
            // Step indicator
            GlobalStepIndicator(currentStep: .autoEdit)
            
            Divider()
                .background(AutoEditTheme.hairlineDivider)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set your auto-edit preferences")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(AutoEditTheme.primaryText)
                        
                        Text("Auto Slate will use these settings to build your first draft.")
                            .font(.system(size: 14))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 40)
                    
                    // Quality Preview Button (if clips exist)
                    if !projectViewModel.clips.isEmpty {
                        qualityPreviewButton
                            .padding(.horizontal, 40)
                            .padding(.bottom, 10)
                    }
                    
                    // Settings sections
                    VStack(alignment: .leading, spacing: 20) {
                        // Target Length
                        targetLengthSection
                        
                        // Pace
                        paceSection
                        
                        // Style
                        styleSection
                        
                        // Audio Cleanup
                        audioCleanupSection
                        
                        // Quality Threshold
                        qualityThresholdSection
                        
                        // Color Look
                        colorLookSection
                        
                        // Effects & Transitions
                        effectsTransitionsSection
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .background(AutoEditTheme.bg)
            
            Divider()
                .background(AutoEditTheme.hairlineDivider)
            
            // Navigation
            HStack {
                Button("Back") {
                    appViewModel.previousStep()
                }
                .buttonStyle(BackButtonStyle())
                .disabled(projectViewModel.isAutoEditing)
                
                Spacer()
                
                HStack(spacing: 12) {
                    if projectViewModel.isAutoEditing {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.tealCircular)
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                Text(projectViewModel.autoEditStatus)
                                    .font(.system(size: 12))
                                    .foregroundColor(AutoEditTheme.secondaryText)
                            }
                            
                            // Time estimate - shown below the spinning wheel
                            if let timeEstimate = projectViewModel.autoEditTimeEstimate {
                                Text(timeEstimate)
                                    .font(.system(size: 10))
                                    .foregroundColor(AutoEditTheme.secondaryText.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    if let error = projectViewModel.autoEditError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(.trailing, 8)
                    }
                    
                    Button("Run Auto Edit") {
                        runAutoEdit()
                    }
                    .buttonStyle(RunAutoEditButtonStyle(isDisabled: projectViewModel.isAutoEditing || projectViewModel.clips.isEmpty))
                    .disabled(projectViewModel.isAutoEditing || projectViewModel.clips.isEmpty)
                }
            }
            .padding(30)
            .background(AutoEditTheme.panel)
            }
            .background(AutoEditTheme.bg)
            .onAppear {
                if style == nil {
                    style = defaultStyle
                }
                // Initialize quality threshold from current settings
                qualityThreshold = projectViewModel.autoEditSettings.qualityThreshold
            }
        }
    
    private var targetLengthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Target length")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            HStack(spacing: 12) {
                ForEach(TargetLength.allCases, id: \.self) { length in
                    Button(action: { targetLength = length }) {
                        Text(length.label)
                            .font(.system(size: 14, weight: targetLength == length ? .medium : .regular))
                            .foregroundColor(targetLength == length ? .white : AutoEditTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if targetLength == length {
                                        AutoEditTheme.teal
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(
                                        targetLength == length ? Color.clear : AutoEditTheme.teal.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(999)
                            .shadow(color: targetLength == length ? AutoEditTheme.teal.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Pace")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar - ORANGE
            Rectangle()
                .fill(AutoEditTheme.orange)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            HStack(spacing: 12) {
                ForEach(Pace.allCases, id: \.self) { paceOption in
                    Button(action: { pace = paceOption }) {
                        Text(paceOption.rawValue.capitalized)
                            .font(.system(size: 14, weight: pace == paceOption ? .medium : .regular))
                            .foregroundColor(pace == paceOption ? .white : AutoEditTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if pace == paceOption {
                                        AutoEditTheme.orange
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(
                                        pace == paceOption ? Color.clear : AutoEditTheme.orange.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(999)
                            .shadow(color: pace == paceOption ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Style")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar - using orange to match Pace
            Rectangle()
                .fill(AutoEditTheme.orange)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            HStack(spacing: 12) {
                ForEach(styleOptions, id: \.self) { styleOption in
                    Button(action: { style = styleOption }) {
                        Text(styleOption.displayLabel)
                            .font(.system(size: 14, weight: (style ?? defaultStyle) == styleOption ? .medium : .regular))
                            .foregroundColor((style ?? defaultStyle) == styleOption ? .white : AutoEditTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if (style ?? defaultStyle) == styleOption {
                                        AutoEditTheme.orange
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(
                                        (style ?? defaultStyle) == styleOption ? Color.clear : AutoEditTheme.orange.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(999)
                            .shadow(color: (style ?? defaultStyle) == styleOption ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var audioCleanupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Audio cleanup")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            Toggle("Remove background noise", isOn: $removeNoise)
                .toggleStyle(TealToggleStyle())
                .foregroundColor(AutoEditTheme.primaryText)
            
            Toggle("Smooth out loudness", isOn: $smoothLoudness)
                .toggleStyle(TealToggleStyle())
                .foregroundColor(AutoEditTheme.primaryText)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Overall volume")
                    .autoEditHint()
                
                HStack {
                    Slider(value: $overallVolume, in: -12.0...12.0)
                        .tint(AutoEditTheme.orange)
                    Text(String(format: "%.1f dB", overallVolume))
                        .font(.system(size: 12))
                        .foregroundColor(AutoEditTheme.secondaryText)
                        .frame(width: 60)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var qualityThresholdSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Shot Quality Filter")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Minimum quality threshold")
                        .autoEditHint()
                    Spacer()
                    Text(String(format: "%.1f", qualityThreshold))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AutoEditTheme.primaryText)
                        .frame(width: 50)
                }
                
                Text("Clips below this threshold will be filtered out during auto-edit.")
                    .font(.system(size: 11))
                    .foregroundColor(AutoEditTheme.secondaryText)
                    .padding(.bottom, 4)
                
                HStack {
                    Text("Low")
                        .font(.system(size: 11))
                        .foregroundColor(AutoEditTheme.secondaryText)
                    
                    Slider(value: $qualityThreshold, in: 0.0...1.0)
                        .tint(AutoEditTheme.teal)
                    
                    Text("High")
                        .font(.system(size: 11))
                        .foregroundColor(AutoEditTheme.secondaryText)
                }
                
                // Quality indicator
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Poor")
                            .font(.system(size: 10))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 8, height: 8)
                        Text("Medium")
                            .font(.system(size: 10))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("High")
                            .font(.system(size: 10))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var colorLookSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Color look")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Orange accent bar
            Rectangle()
                .fill(AutoEditTheme.orange)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            Text("Choose a base look for your grade.")
                .font(.system(size: 11))
                .foregroundColor(AutoEditTheme.secondaryText)
                .padding(.bottom, 8)
            
            // Swatch buttons in horizontal layout
            HStack(spacing: 16) {
                ForEach(ColorLookPreset.allCases, id: \.self) { look in
                    ColorLookSwatch(
                        preset: look,
                        isSelected: colorLook == look
                    )
                    .onTapGesture {
                        colorLook = look
                    }
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var effectsTransitionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Effects & Transitions")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Teal accent bar
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            // Transition Types (Multiple Selection)
            VStack(alignment: .leading, spacing: 12) {
                Text("Transition Types")
                    .autoEditLabel()
                
                Text("Select one or more transition styles to use between clips")
                    .font(.system(size: 11))
                    .foregroundColor(AutoEditTheme.secondaryText)
                    .padding(.bottom, 4)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(TransitionType.allCases.filter { $0 != .none }, id: \.self) { transType in
                        OptionChip(
                            label: transType.displayLabel,
                            isSelected: selectedTransitions.contains(transType),
                            isSecondaryAccent: false
                        )
                        .onTapGesture {
                            if selectedTransitions.contains(transType) {
                                selectedTransitions.remove(transType)
                            } else {
                                selectedTransitions.insert(transType)
                            }
                        }
                    }
                }
            }
            
            // Transition Duration
            if !selectedTransitions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transition Duration")
                            .autoEditLabel()
                        Spacer()
                        Text(String(format: "%.2fs", transitionDuration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AutoEditTheme.primaryText)
                            .frame(width: 50)
                    }
                    
                    Slider(value: $transitionDuration, in: 0.1...1.0)
                        .tint(AutoEditTheme.teal)
                    
                    HStack {
                        Text("Fast")
                            .font(.system(size: 11))
                            .foregroundColor(AutoEditTheme.secondaryText)
                        Spacer()
                        Text("Slow")
                            .font(.system(size: 11))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                }
            }
            
            Divider()
                .background(AutoEditTheme.border)
            
            // Fade to Black
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enableFadeToBlack) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fade to Black")
                            .autoEditLabel()
                        Text("Fade video to black at the end (matches music fade-out)")
                            .font(.system(size: 11))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                }
                .toggleStyle(TealToggleStyle())
                
                if enableFadeToBlack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fade Duration")
                                .autoEditLabel()
                            Spacer()
                            Text(String(format: "%.1fs", fadeToBlackDuration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AutoEditTheme.primaryText)
                                .frame(width: 50)
                        }
                        
                        Slider(value: $fadeToBlackDuration, in: 0.5...3.0)
                            .tint(AutoEditTheme.teal)
                        
                        HStack {
                            Text("Quick")
                                .font(.system(size: 11))
                                .foregroundColor(AutoEditTheme.secondaryText)
                            Spacer()
                            Text("Slow")
                                .font(.system(size: 11))
                                .foregroundColor(AutoEditTheme.secondaryText)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
            
            Divider()
                .background(AutoEditTheme.border)
            
            // Video Effects
            VStack(alignment: .leading, spacing: 12) {
                Text("Video Effects")
                    .autoEditLabel()
                Text("Add dynamic effects to make your video more engaging")
                    .font(.system(size: 11))
                    .foregroundColor(AutoEditTheme.secondaryText)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(VideoEffect.allCases.filter { $0 != .none }, id: \.self) { effect in
                        OptionChip(
                            label: effect.displayLabel,
                            isSelected: selectedEffects.contains(effect),
                            isSecondaryAccent: false
                        )
                        .onTapGesture {
                            if selectedEffects.contains(effect) {
                                selectedEffects.remove(effect)
                            } else {
                                selectedEffects.insert(effect)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var styleOptions: [AutoEditStyle] {
        AutoEditStyle.styles(for: projectViewModel.type)
    }
    
    private var qualityPreviewButton: some View {
        Button(action: {
            Task {
                await projectViewModel.analyzeQualityForClips()
            }
        }) {
            HStack {
                if projectViewModel.isAnalyzingQuality {
                    ProgressView()
                        .progressViewStyle(.tealCircular)
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                    Text("Analyzing quality... (\(projectViewModel.qualityAnalysisProgress.current)/\(projectViewModel.qualityAnalysisProgress.total))")
                        .font(.system(size: 14))
                        .foregroundColor(AutoEditTheme.primaryText)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                    Text("Preview Quality Scores")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AutoEditTheme.primaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AutoEditTheme.teal.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AutoEditTheme.teal, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(projectViewModel.isAnalyzingQuality)
    }
    
    private func runAutoEdit() {
        // Update project with auto edit settings
        var updatedProject = projectViewModel.project
        updatedProject.autoEditSettings = currentSettings
        projectViewModel.project = updatedProject
        
        // Update audio settings
        var audioSettings = projectViewModel.audioSettings
        audioSettings.enableNoiseReduction = removeNoise
        audioSettings.enableCompression = smoothLoudness
        audioSettings.masterGainDB = overallVolume
        projectViewModel.updateAudioSettings(audioSettings)
        
        // Update color settings based on preset with proper distinct looks
        var colorSettings = projectViewModel.colorSettings
        switch colorLook {
        case .neutral:
            // Neutral: No color grading, natural look
            colorSettings = ColorSettings(
                exposure: 0.0,
                contrast: 1.0,
                saturation: 1.0,
                colorHue: 0.0,
                colorSaturation: 0.0
            )
        case .clean:
            // Clean: Slightly brightened, enhanced contrast, crisp look
            colorSettings = ColorSettings(
                exposure: 0.15,
                contrast: 1.15,
                saturation: 1.05,
                colorHue: 0.0,
                colorSaturation: 0.0
            )
        case .filmic:
            // Filmic: Slightly desaturated, reduced contrast, warm cinematic tone
            colorSettings = ColorSettings(
                exposure: -0.1,
                contrast: 0.85,
                saturation: 0.9,
                colorHue: 15.0,  // Slight warm shift (orange/yellow)
                colorSaturation: 0.25
            )
        case .punchy:
            // Punchy: Enhanced contrast, boosted saturation, vibrant colors
            colorSettings = ColorSettings(
                exposure: 0.1,
                contrast: 1.25,
                saturation: 1.35,
                colorHue: 0.0,
                colorSaturation: 0.0
            )
        }
        projectViewModel.colorSettings = colorSettings
        
        // Update auto edit settings
        projectViewModel.autoEditSettings = currentSettings
        
        // Run auto edit
        projectViewModel.runAutoEdit()
        
        // Wait for completion and move to review
        Task {
            // Wait a bit for auto edit to start
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Poll until auto edit is complete
            while projectViewModel.isAutoEditing {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            await MainActor.run {
                // Check for errors
                if let error = projectViewModel.autoEditError {
                    // Show error - don't advance
                    print("Auto edit error: \(error)")
                } else {
                    // Success - move to Edit step (review/edit screen)
                    // This is the first forward step after auto-edit completes
                    appViewModel.goToStep(.edit)
                }
            }
        }
    }
}

enum TargetLength: CaseIterable {
    case short
    case standard
    case extended
    case full
    
    var label: String {
        switch self {
        case .short: return "Short (0-1 min)"
        case .standard: return "Standard (1-3 min)"
        case .extended: return "Extended (3-10 min)"
        case .full: return "Full (use all content)"
        }
    }
}

// MARK: - Custom Button Styles

struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundColor(AutoEditTheme.secondaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? AutoEditTheme.panel.opacity(0.5) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AutoEditTheme.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct RunAutoEditButtonStyle: ButtonStyle {
    let isDisabled: Bool
    
    // Orange color matching the app's orange accent
    private let orangeColor = AutoEditTheme.orange // #FFB347 - matches app orange
    private let orangeColorDisabled = AutoEditTheme.orange.opacity(0.5) // Dimmed orange when disabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minWidth: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDisabled ? orangeColorDisabled : orangeColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        configuration.isPressed && !isDisabled ? Color.white.opacity(0.3) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isDisabled ? .clear : orangeColor.opacity(0.4),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct TealToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(configuration.isOn ? AutoEditTheme.teal : AutoEditTheme.panel)
                    .frame(width: 50, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AutoEditTheme.border, lineWidth: 1)
                    )
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

