//
//  AudioEditingStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/26/25.
//

import SwiftUI

struct AudioEditingStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        DaVinciStyleLayout(
            appViewModel: appViewModel,
            projectViewModel: projectViewModel
        ) {
            // Central viewer area - video preview
                PreviewPanel(projectViewModel: projectViewModel)
                    .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                    .background(Color.black)
        }
    }
}

