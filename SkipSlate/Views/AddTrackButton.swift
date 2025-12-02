//
//  AddTrackButton.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline UI
//  - Button component for adding new video/audio tracks
//  - Small teal "+ V" or "+ A" button with hover states
//  - DaVinci-style compact design
//

import SwiftUI

struct AddTrackButton: View {
    let trackKind: TrackKind
    let onAdd: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text(trackKind == .video ? "V" : "A")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isHovered ? .white : AppColors.tealAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? AppColors.tealAccent : AppColors.tealAccent.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Add \(trackKind == .video ? "video" : "audio") track")
    }
}
