//
//  ReviewStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct ReviewStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            GlobalStepIndicator(currentStep: .edit)
            
            Divider()
            
            // Main editor content
            VStack(spacing: 0) {
                // Top toolbar
                HStack {
                    Text(projectViewModel.projectName)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                }
                .padding()
                .background(AppColors.panelBackground)
                
                // Main content area
                HStack(spacing: 0) {
                    // Left: Preview - MUST have explicit size
                    VStack(spacing: 0) {
                        PreviewPanel(projectViewModel: projectViewModel)
                            .frame(minWidth: 600, minHeight: 400)
                            .frame(width: 600, height: nil)
                        
                        // DEBUG: Temporary button to test raw clip playback
                        #if DEBUG
                        HStack {
                            Button("DEBUG: Play First Clip Raw") {
                                projectViewModel.debugPlayFirstClipRaw()
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(4)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        #endif
                    }
                    
                    Divider()
                    
                    // Right: Inspector
                    InspectorPanel(projectViewModel: projectViewModel)
                        .frame(width: 300)
                }
                
                Divider()
                
                // Bottom: Timeline - using clean minimal timeline
                TimelineView(projectViewModel: projectViewModel)
            }
            .background(AppColors.background)
            
            Divider()
            
            // User guidance banner with actions
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.podcastColor)
                Text("This is your auto-generated draft. Delete unwanted segments, then use 'Fill Gaps' to replace them with better clips.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                
                // Fill Gaps button
                Button("Fill Gaps") {
                    projectViewModel.fillGaps()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.tealAccent)
                .disabled(projectViewModel.isAutoEditing || projectViewModel.clips.isEmpty)
                
                if projectViewModel.isAutoEditing {
                    ProgressView()
                        .progressViewStyle(.tealCircular)
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                    Text(projectViewModel.autoEditStatus)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppColors.cardBase)
            
            Divider()
            
            // Navigation
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
                .tint(AppColors.podcastColor)
            }
            .padding(30)
            .background(AppColors.panelBackground)
        }
        .background(AppColors.background)
        .focusable()
        .onKeyPress(.leftArrow) {
            handleLeftArrow()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleRightArrow()
            return .handled
        }
        .onKeyPress(.delete) {
            handleDelete()
            return .handled
        }
    }
    
    private func handleLeftArrow() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        guard let currentIndex = projectViewModel.segments.firstIndex(where: { $0.id == selectedSegment.id }) else { return }
        
        if currentIndex > 0 {
            let prevSegment = projectViewModel.segments[currentIndex - 1]
            projectViewModel.selectedSegment = prevSegment
            projectViewModel.seekToSegment(prevSegment)
        }
    }
    
    private func handleRightArrow() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        guard let currentIndex = projectViewModel.segments.firstIndex(where: { $0.id == selectedSegment.id }) else { return }
        
        if currentIndex < projectViewModel.segments.count - 1 {
            let nextSegment = projectViewModel.segments[currentIndex + 1]
            projectViewModel.selectedSegment = nextSegment
            projectViewModel.seekToSegment(nextSegment)
        }
    }
    
    private func handleDelete() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        projectViewModel.deleteSegment(selectedSegment)
    }
}

