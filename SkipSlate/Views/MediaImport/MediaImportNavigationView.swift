//
//  MediaImportNavigationView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Media Import UI - Navigation Component
//  - Displays Back/Next navigation buttons
//  - Completely independent of preview/playback
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct MediaImportNavigationView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        HStack {
            Button("Back") {
                appViewModel.previousStep()
            }
            .buttonStyle(.bordered)
            .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            Button("Next") {
                appViewModel.nextStep()
            }
            .buttonStyle(.borderedProminent)
            .disabled(projectViewModel.clips.isEmpty)
            .tint(projectViewModel.clips.isEmpty ? .gray : AppColors.podcastColor)
        }
        .padding(30)
        .background(AppColors.panelBackground)
    }
}
