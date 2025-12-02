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

import SwiftUI

struct MediaImportStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var showImportToast = false
    @State private var importToastMessage = ""
    @State private var selectedTab: ImportTab = .myMedia
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (logo + step indicator)
            MediaImportHeaderView()
            
            // Content
            ScrollView {
                VStack(spacing: 30) {
                    // Title
                    MediaImportTitleView()
                    
                    // Tab selector
                    MediaImportTabSelector(selectedTab: $selectedTab)
                    
                    // Main content area
                    if selectedTab == .myMedia {
                        HStack(spacing: 30) {
                            // Left: Drop zone
                            MediaDropZoneView(projectViewModel: projectViewModel)
                                .frame(maxWidth: .infinity)
                            
                            // Right: Media list
                            MediaListView(projectViewModel: projectViewModel)
                                .frame(width: 350)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    } else {
                        // Stock search view
                        StockSearchView(projectViewModel: projectViewModel)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                    }
                }
            }
            .background(AppColors.background)
            
            Divider()
            
            // Navigation
            MediaImportNavigationView(
                appViewModel: appViewModel,
                projectViewModel: projectViewModel
            )
        }
        .background(AppColors.background)
        .onChange(of: projectViewModel.clips.count) { oldValue, newValue in
            if newValue > oldValue {
                let count = newValue - oldValue
                showImportToast(message: "Imported \(count) file\(count == 1 ? "" : "s")")
            }
        }
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
