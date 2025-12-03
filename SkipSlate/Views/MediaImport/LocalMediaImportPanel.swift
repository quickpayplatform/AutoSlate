
//  LocalMediaImportPanel.swift
//  SkipSlate
//
//  Created by Cursor on 12/26/25.
//
//  MODULE: Media Import UI - Local Media Import Panel
//  - Combines MediaDropZoneView and MediaListView for local media import
//  - Encapsulates local media import UI
//  - Does NOT touch PlayerViewModel
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct LocalMediaImportPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
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
    }
}
