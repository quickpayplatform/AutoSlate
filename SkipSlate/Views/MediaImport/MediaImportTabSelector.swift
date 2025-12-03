
//  MediaImportTabSelector.swift
//  SkipSlate
//
//  Created by Cursor on 12/2/25.
//
//  MODULE: Media Import UI - Tab Selector Component
//  - Displays tab buttons (My Media / Stock)
//  - Completely independent of preview/playback
//  - Can be restyled without affecting video preview
//

import SwiftUI

enum ImportTab {
    case myMedia
    case stock
}

struct MediaImportTabSelector: View {
    @Binding var selectedTab: ImportTab
    
    var body: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "My Media",
                isSelected: selectedTab == .myMedia,
                action: { selectedTab = .myMedia }
            )
            
            TabButton(
                title: "Stock",
                isSelected: selectedTab == .stock,
                action: { selectedTab = .stock }
            )
            
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(isSelected ? AppColors.podcastColor.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

