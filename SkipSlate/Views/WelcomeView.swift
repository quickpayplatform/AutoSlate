//
//  WelcomeView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var appViewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App Logo
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .compositingGroup()
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text("Smart editor that automatically skips dead space and bad takes")
                .font(.title2)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                appViewModel.startNewProject()
            }) {
                Text("New Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(AppColors.orangeAccent)
                    .cornerRadius(10)
                    .shadow(color: AppColors.orangeAccent.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

