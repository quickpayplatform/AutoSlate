//
//  RemoveTrackButton.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Timeline UI
//  - Button component for removing video/audio tracks
//  - Small orange "- V" or "- A" button with hover states
//  - Removes topmost video track or bottommost audio track
//

import SwiftUI

struct RemoveTrackButton: View {
    let trackKind: TrackKind
    let isEnabled: Bool  // Disabled if only one track of this type exists
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 2) {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .semibold))
                Text(trackKind == .video ? "V" : "A")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isEnabled ? (isHovered ? .white : AppColors.orangeAccent) : AppColors.secondaryText.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isEnabled ? (isHovered ? AppColors.orangeAccent : AppColors.orangeAccent.opacity(0.2)) : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isEnabled ? "Remove \(trackKind == .video ? "top video" : "bottom audio") track" : "Cannot remove the only \(trackKind == .video ? "video" : "audio") track")
    }
}
