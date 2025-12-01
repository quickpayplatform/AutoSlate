//
//  ColorGradingStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/26/25.
//

import SwiftUI

struct ColorGradingStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        DaVinciStyleLayout(
            appViewModel: appViewModel,
            projectViewModel: projectViewModel
        ) {
            // Video viewer positioned on the left side
            HStack(spacing: 0) {
                // Video preview - takes up left portion
                PreviewPanel(projectViewModel: projectViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
    }
}

