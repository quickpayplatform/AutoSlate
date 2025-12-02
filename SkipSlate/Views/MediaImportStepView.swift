//
//  MediaImportStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Media Import UI - Main Container
//  - Orchestrates media import components
//  - This view ONLY manages importing media files and adding them to project.clips
//  - It MUST NOT access PlayerViewModel, AVPlayer, or AVMutableComposition
//  - It communicates with ProjectViewModel via: projectViewModel.importMedia(urls:)
//  - Composition rebuild happens automatically when segments are created (during auto-edit)
//  - This ensures media import UI changes don't break video preview
//
//  REFACTORED (Part D):
//  - Broken into smaller, reusable components for easier styling
//  - All components are independent and can be restyled without affecting preview
//
//  REDESIGNED (Part 2):
//  - Replaced tabs with buttons for media source selection
//  - Integrated with DaVinciStyleLayout for visual consistency
//  - Uses SourceButton, LocalMediaImportPanel, and StockMediaImportPanel
//

import SwiftUI

enum MediaImportSource {
    case local
    case stock
}

struct MediaImportStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var showImportToast = false
    @State private var importToastMessage = ""
    @State private var selectedSource: MediaImportSource = .local
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DaVinciStyleLayout(
                appViewModel: appViewModel,
                projectViewModel: projectViewModel,
                showTimeline: false // Hide timeline during media import
            ) {
                // Central content area
                VStack(spacing: 0) {
                    // Content
                    ScrollView {
                        VStack(spacing: 30) {
                            // Title
                            MediaImportTitleView()
                            
                            // Button row instead of tabs
                            HStack(spacing: 12) {
                                SourceButton(
                                    title: "Upload from Computer",
                                    iconName: "folder.fill",
                                    isSelected: selectedSource == .local,
                                    accentColor: AppColors.tealAccent
                                ) {
                                    selectedSource = .local
                                }
                                
                                SourceButton(
                                    title: "Stock Videos",
                                    iconName: "photo.on.rectangle",
                                    isSelected: selectedSource == .stock,
                                    accentColor: AppColors.orangeAccent
                                ) {
                                    selectedSource = .stock
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                            
                            Divider()
                                .padding(.horizontal, 40)
                                .padding(.bottom, 20)
                            
                            // Content area - switch between panels
                            Group {
                                switch selectedSource {
                                case .local:
                                    LocalMediaImportPanel(projectViewModel: projectViewModel)
                                case .stock:
                                    StockMediaImportPanel(projectViewModel: projectViewModel)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .background(AppColors.background)
                }
            }
            
            // Next button at absolute bottom right corner
            Button("Next") {
                appViewModel.nextStep() // Navigate to auto-edit step
            }
            .buttonStyle(BrightProminentButtonStyle(isEnabled: !projectViewModel.clips.isEmpty))
            .disabled(projectViewModel.clips.isEmpty)
            .padding(.trailing, 30)
            .padding(.bottom, 30)
        }
        .onChange(of: projectViewModel.clips.count) { oldValue, newValue in
            if newValue > oldValue {
                let count = newValue - oldValue
                showImportToast(message: "Imported \(count) file\(count == 1 ? "" : "s")")
            }
        }
        .overlay(
            // Toast notification
            VStack {
                Spacer()
                if showImportToast {
                    HStack {
                        Text(importToastMessage)
                            .font(.subheadline)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(AppColors.panelBackground)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    }
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: showImportToast)
        )
    }
    
    private func showImportToast(message: String) {
        importToastMessage = message
        showImportToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showImportToast = false
            }
        }
    }
}
