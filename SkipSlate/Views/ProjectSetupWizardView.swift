//
//  ProjectSetupWizardView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct ProjectSetupWizardView: View {
    @ObservedObject var appViewModel: AppViewModel
    let projectViewModel: ProjectViewModel?
    
    @State private var selectedType: ProjectType?
    @State private var selectedAspectRatio: AspectRatio?
    @State private var selectedResolution: ResolutionPreset?
    @State private var projectName: String = ""
    
    private var currentStepNumber: Int {
        appViewModel.currentStep.rawValue
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
            GlobalStepIndicator(currentStep: appViewModel.currentStep)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 30) {
                    if appViewModel.currentStep == .type {
                        step1View
                    } else if appViewModel.currentStep == .frame {
                        step2View
                    } else if appViewModel.currentStep == .name {
                        step3View
                    }
                }
                .padding(40)
            }
            .scrollIndicators(.hidden)
            .background(AppColors.background)
            
            Divider()
            
            // Navigation
            HStack {
                if currentStepNumber > 1 {
                    Button("Back") {
                        appViewModel.previousStep()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                if appViewModel.currentStep == .name {
                    Button("Create Project") {
                        createProject()
                    }
                    .buttonStyle(BrightProminentButtonStyle(isEnabled: canProceed))
                    .disabled(!canProceed)
                } else {
                    Button("Next") {
                        if canProceed {
                            appViewModel.nextStep()
                        }
                    }
                    .buttonStyle(BrightProminentButtonStyle(isEnabled: canProceed))
                    .disabled(!canProceed)
                }
            }
            .padding(30)
            .background(AppColors.panelBackground)
        }
        .background(AppColors.background)
        .onAppear {
            // Initialize from existing project if available
            if let existing = projectViewModel {
                selectedType = existing.type
                selectedAspectRatio = existing.aspectRatio
                selectedResolution = existing.resolution
                projectName = existing.projectName
            }
        }
    }
    
    private var step1View: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title
            Text("What are you editing?")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppColors.primaryText)
            
            // Subtitle
            Text("Choose a project type so Auto Slate can auto-edit with the right pacing.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .padding(.bottom, 8)
            
            // Grid of project type cards (2 columns, wraps for 5 items)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                ForEach(ProjectType.allCases) { type in
                    ProjectTypeCard(
                        type: type,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var step2View: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Title
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose frame & resolution")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                Text("Select the aspect ratio and resolution for your project.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            // Aspect Ratio Cards
            VStack(alignment: .leading, spacing: 16) {
                Text("Aspect Ratio")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ], spacing: 20) {
                    ForEach(AspectRatio.allCases) { aspectRatio in
                        AspectRatioCard(
                            aspectRatio: aspectRatio,
                            isSelected: selectedAspectRatio == aspectRatio
                        ) {
                            selectedAspectRatio = aspectRatio
                            selectedResolution = nil
                        }
                    }
                }
            }
            
            // Resolution Chips (if aspect ratio selected)
            if let aspectRatio = selectedAspectRatio {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Resolution")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    HStack(spacing: 12) {
                        ForEach(ResolutionPreset.presetsForAspectRatio(aspectRatio)) { preset in
                            ResolutionCard(
                                preset: preset,
                                isSelected: selectedResolution == preset
                            ) {
                                selectedResolution = preset
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var step3View: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Title section with subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("Name your project")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                
                Text("Give your project a memorable name to help you find it later.")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.top, 20)
            
            // Project name input field
            VStack(alignment: .leading, spacing: 12) {
                Text("Project Name")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.primaryText)
                
                TextField("", text: $projectName, prompt: Text("Enter project name").foregroundColor(AppColors.tertiaryText))
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .accentColor(.black) // Cursor color
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppColors.cardBase)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.panelBorder.opacity(0.3), lineWidth: 1)
                    )
                    .onAppear {
                        if projectName.isEmpty {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MMM d, yyyy HH:mm"
                            projectName = "Untitled Project \(formatter.string(from: Date()))"
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var canProceed: Bool {
        switch appViewModel.currentStep {
        case .type:
            return selectedType != nil
        case .frame:
            return selectedAspectRatio != nil && selectedResolution != nil
        case .name:
            return !projectName.isEmpty
        default:
            return false
        }
    }
    
    private func createProject() {
        guard let type = selectedType,
              let aspectRatio = selectedAspectRatio,
              let resolution = selectedResolution else {
            return
        }
        
        appViewModel.createProject(
            type: type,
            aspectRatio: aspectRatio,
            resolution: resolution,
            name: projectName.isEmpty ? "Untitled Project" : projectName
        )
    }
}

struct StepIndicator: View {
    let step: Int
    let currentStep: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if currentStep >= step {
                    Circle()
                        .fill(currentStep == step ? AppColors.podcastColor : AppColors.podcastColor.opacity(0.6))
                        .frame(width: 40, height: 40)
                } else {
                    Circle()
                        .stroke(AppColors.secondaryText.opacity(0.3), lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
                
                if currentStep > step {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                } else {
                    Text("\(step)")
                        .foregroundColor(currentStep >= step ? .white : AppColors.secondaryText)
                        .fontWeight(.semibold)
                }
            }
            
            Text(label)
                .font(.caption)
                .fontWeight(currentStep == step ? .semibold : .regular)
                .foregroundColor(currentStep >= step ? AppColors.primaryText : AppColors.secondaryText)
        }
    }
}

struct ProjectTypeCard: View {
    let type: ProjectType
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    private var accentColor: Color {
        AppColors.accentColor(for: type)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(isSelected ? accentColor : AppColors.secondaryText)
                
                Text(type.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : AppColors.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(
                ZStack {
                    // Base dark background
                    AppColors.cardBase
                    
                    // Gradient overlay
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(isSelected ? 0.25 : 0.1),
                            accentColor.opacity(isSelected ? 0.05 : 0.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? accentColor : (isHovered ? accentColor.opacity(0.3) : Color.clear),
                        lineWidth: isSelected ? 3 : 2
                    )
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.3) : .clear,
                radius: isSelected ? 8 : 0
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isHovered)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var iconName: String {
        switch type {
        case .podcast:
            return "mic.fill"
        case .documentary:
            return "film"
        case .musicVideo:
            return "music.note"
        case .danceVideo:
            return "figure.dance"
        case .highlightReel:
            return "sparkles"
        case .commercials:
            return "tv.fill"
        }
    }
}

struct AspectRatioCard: View {
    let aspectRatio: AspectRatio
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    private var usageText: String {
        switch aspectRatio {
        case .ar16x9:
            return "YouTube / Desktop"
        case .ar9x16:
            return "Vertical / Reels"
        case .ar1x1:
            return "Instagram / Social"
        case .ar4x5:
            return "Stories / Shorts"
        case .ar235x1:
            return "Cinema / Film"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon showing orientation
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                
                // Main label
                Text(aspectRatio.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : AppColors.primaryText)
                
                // Sub-label
                Text(usageText)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [AppColors.tealAccent, AppColors.tealAccent.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        AppColors.panelBackground
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? AppColors.tealAccent : AppColors.panelBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .cornerRadius(16)
            .shadow(color: isSelected ? AppColors.tealAccent.opacity(0.3) : .clear, radius: 8)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isHovered)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var iconName: String {
        switch aspectRatio {
        case .ar16x9:
            return "rectangle" // Landscape orientation
        case .ar9x16:
            return "rectangle.portrait"
        case .ar1x1:
            return "square"
        case .ar4x5:
            return "rectangle.portrait.fill"
        case .ar235x1:
            return "rectangle.fill" // Wide cinematic aspect ratio
        }
    }
}

struct ResolutionCard: View {
    let preset: ResolutionPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(preset.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : AppColors.primaryText)
                
                Text("\(preset.width)×\(preset.height)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppColors.secondaryText)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(
                isSelected ? AppColors.tealAccent : AppColors.panelBackground
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? AppColors.tealAccent : AppColors.panelBorder,
                        lineWidth: 1
                    )
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// Legacy ResolutionCard - keeping for compatibility but should use ResolutionChip above
struct ResolutionCard_Legacy: View {
    let preset: ResolutionPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.label)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .gray)
                
                Text("\(preset.width)×\(preset.height)")
                    .font(.caption)
                    .foregroundColor(isSelected ? .gray : .gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bright Button Style

struct BrightProminentButtonStyle: ButtonStyle {
    let isEnabled: Bool
    private let tealColor = AppColors.tealAccent
    private let disabledColor = Color.gray.opacity(0.5)
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? tealColor : disabledColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        configuration.isPressed && isEnabled ? Color.white.opacity(0.3) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: isEnabled ? tealColor.opacity(0.5) : .clear,
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 3 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

