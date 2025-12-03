//
//  AppViewModel.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

enum WizardStep: Int, CaseIterable {
    case type = 1
    case frame = 2
    case name = 3
    case media = 4
    case autoEdit = 5
    case edit = 6      // Edit is now first after auto-edit
    case color = 7
    case audio = 8
    case export = 9
    
    var label: String {
        switch self {
        case .type: return "Type"
        case .frame: return "Frame"
        case .name: return "Name"
        case .media: return "Media"
        case .autoEdit: return "Auto Edit"
        case .color: return "Color"
        case .audio: return "Audio"
        case .edit: return "Edit"
        case .export: return "Export"
        }
    }
    
    // Tab icon name for DaVinci-style interface
    var iconName: String {
        switch self {
        case .type: return "square.grid.2x2"
        case .frame: return "aspectratio"
        case .name: return "text.cursor"
        case .media: return "photo.on.rectangle"
        case .autoEdit: return "wand.and.stars"
        case .color: return "paintpalette"
        case .audio: return "waveform"
        case .edit: return "scissors"
        case .export: return "square.and.arrow.up"
        }
    }
}

class AppViewModel: ObservableObject {
    @Published var currentStep: WizardStep = .type
    @Published var projectViewModel: ProjectViewModel?
    @Published var isInWizard: Bool = false
    
    func startNewProject() {
        isInWizard = true
        currentStep = .type
    }
    
    func createProject(type: ProjectType, aspectRatio: AspectRatio, resolution: ResolutionPreset, name: String) {
        let project = Project(
            name: name,
            type: type,
            aspectRatio: aspectRatio,
            resolution: resolution
        )
        projectViewModel = ProjectViewModel(project: project)
        currentStep = .media
    }
    
    // Navigate to specific editing step (for tab-based navigation)
    func navigateToEditingStep(_ step: WizardStep) {
        guard let projectVM = projectViewModel else { return }
        
        // Validate prerequisites
        switch step {
        case .media:
            currentStep = .media
        case .autoEdit:
            if !projectVM.clips.isEmpty {
                currentStep = .autoEdit
            }
        case .color, .audio, .edit, .export:
            if !projectVM.segments.isEmpty {
                currentStep = step
            }
        default:
            break
        }
    }
    
    func nextStep() {
        if let next = WizardStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }
    
    func previousStep() {
        if let previous = WizardStep(rawValue: currentStep.rawValue - 1) {
            currentStep = previous
        }
    }
    
    func goToStep(_ step: WizardStep) {
        // CRITICAL: Prevent going back to Media or AutoEdit after segments exist
        // This prevents users from accidentally restarting the auto-edit process
        if let projectVM = projectViewModel, !projectVM.segments.isEmpty {
            // After auto-edit: Only allow forward steps
            if step == .media || step == .autoEdit {
                print("SkipSlate: Navigation blocked - cannot go back to \(step.label) after auto-edit completes")
                return
            }
        }
        currentStep = step
    }
}

