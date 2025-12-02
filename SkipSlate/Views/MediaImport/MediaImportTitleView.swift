//
//  MediaImportTitleView.swift
//  SkipSlate
//
//  Created by Cursor on 12/2/25.
//
//  MODULE: Media Import UI - Title Component
//  - Displays title and description
//  - Completely independent of preview/playback
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct MediaImportTitleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Import your media")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppColors.primaryText)
            
            Text("Add video and audio files Auto Slate will use to build your edit.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(.top, 40)
    }
}

