
//  SourceButton.swift
//  SkipSlate
//
//  Created by Cursor on 12/26/25.
//
//  MODULE: Media Import UI - Source Selection Button
//  - Reusable button component for selecting media source (local vs stock)
//  - Styled to match ProjectTypeCard style (big, plush, nice)
//  - Completely independent of preview/playback
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct SourceButton: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let accentColor: Color // Teal or Orange
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(isSelected ? accentColor : AppColors.secondaryText)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : AppColors.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                ZStack {
                    // Base dark background
                    AppColors.cardBase
                    
                    // Gradient overlay
                    LinearGradient(
                        gradient: Gradient(colors: [
                            accentColor.opacity(isSelected ? 0.25 : 0.1),
                            accentColor.opacity(isSelected ? 0.05 : 0.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? accentColor : (isHovered ? accentColor.opacity(0.3) : Color.clear),
                        lineWidth: isSelected ? 3 : 2
                    )
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.3) : .clear,
                radius: isSelected ? 8 : 0
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isHovered)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
