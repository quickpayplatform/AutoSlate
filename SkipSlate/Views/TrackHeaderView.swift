//
//  TrackHeaderView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline UI
//  - Modern track header with icons
//  - Video tracks: Teal accent with film icon
//  - Audio tracks: Orange accent with waveform icon
//  - Sleek, minimal design matching app aesthetic
//

import SwiftUI

struct TrackHeaderView: View {
    let track: TimelineTrack
    let isActive: Bool  // Whether track is currently active/armed
    let height: CGFloat
    
    // Future controls (not implemented yet, but space reserved)
    var onMuteToggle: (() -> Void)? = nil
    var onLockToggle: (() -> Void)? = nil
    var onVisibilityToggle: (() -> Void)? = nil
    
    private let headerWidth: CGFloat = 50
    
    // Track colors based on type
    private var trackColor: Color {
        track.kind == .video ? AppColors.tealAccent : AppColors.orangeAccent
    }
    
    private var trackIcon: String {
        track.kind == .video ? "film" : "waveform"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Track indicator bar (thin accent stripe on the left)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [trackColor, trackColor.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
            
            // Main track label area
            HStack(spacing: 6) {
                // Icon with subtle glow effect
                ZStack {
                    // Glow background when active
                    if isActive {
                        Circle()
                            .fill(trackColor.opacity(0.3))
                            .frame(width: 28, height: 28)
                            .blur(radius: 4)
                    }
                    
                    // Icon container
                    ZStack {
                        // Background circle with gradient
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        trackColor.opacity(isActive ? 0.4 : 0.2),
                                        trackColor.opacity(isActive ? 0.2 : 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 26, height: 26)
                        
                        // Subtle border
                        Circle()
                            .strokeBorder(
                                trackColor.opacity(isActive ? 0.8 : 0.4),
                                lineWidth: 1
                            )
                            .frame(width: 26, height: 26)
                        
                        // Icon
                        Image(systemName: trackIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(trackColor)
                    }
                }
                
                // Lock indicator (subtle, only when locked)
                if track.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.orangeAccent.opacity(0.7))
                }
                
                Spacer()
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
        }
        .frame(width: headerWidth, height: height)
        .background(
            // Subtle gradient background
            LinearGradient(
                colors: [
                    AppColors.panelBackground,
                    AppColors.panelBackground.opacity(0.95)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            // Bottom border for separation
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        TrackHeaderView(
            track: TimelineTrack(kind: .video, index: 0),
            isActive: true,
            height: 60
        )
        TrackHeaderView(
            track: TimelineTrack(kind: .video, index: 1),
            isActive: false,
            height: 60
        )
        TrackHeaderView(
            track: TimelineTrack(kind: .audio, index: 0),
            isActive: false,
            height: 50
        )
        TrackHeaderView(
            track: TimelineTrack(kind: .audio, index: 1),
            isActive: true,
            height: 50
        )
    }
    .background(AppColors.background)
}
