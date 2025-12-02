//
//  MediaImportHeaderView.swift
//  SkipSlate
//
//  Created by Cursor on 12/2/25.
//
//  MODULE: Media Import UI - Header Component
//  - Displays app logo and step indicator
//  - Completely independent of preview/playback
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct MediaImportHeaderView: View {
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
            GlobalStepIndicator(currentStep: .media)
            
            Divider()
        }
    }
}

