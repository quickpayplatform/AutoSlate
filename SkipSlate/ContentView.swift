//
//  ContentView.swift
//  SkipSlate
//
//  Created by Tee Forest on 11/25/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        Group {
            if appViewModel.isInWizard, let projectViewModel = appViewModel.projectViewModel {
                // Wizard flow
                switch appViewModel.currentStep {
                case .type, .frame, .name:
                    // Setup wizard (keep original design)
                    ProjectSetupWizardView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .media:
                    // Media import (keep original for now, can be wrapped in DaVinci layout later)
                    MediaImportStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .autoEdit:
                    // Auto edit (keep original for now, can be wrapped in DaVinci layout later)
                    AutoEditSettingsStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .color:
                    // Color grading - DaVinci-style layout
                    ColorGradingStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .audio:
                    // Audio editing - DaVinci-style layout
                    AudioEditingStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .edit:
                    // Edit/Timeline - DaVinci-style layout (renamed from Review)
                    EditStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
                case .export:
                    // Export (keep original for now, can be wrapped in DaVinci layout later)
                    ExportStepView(appViewModel: appViewModel, projectViewModel: projectViewModel)
        }
            } else if appViewModel.isInWizard {
                // Project setup (steps 1-3) - no project yet
                ProjectSetupWizardView(appViewModel: appViewModel, projectViewModel: nil)
            } else {
                // Welcome screen
                WelcomeView(appViewModel: appViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Wire MenuActions to app view model
            MenuActions.shared.appViewModel = appViewModel
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
