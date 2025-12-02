//
//  TrackHeaderView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline UI
//  - DaVinci-style track header component
//  - Shows "V" or "A" label in compact pill style
//  - Teal outline when track is active/armed
//  - Space reserved for future controls (mute, lock, visibility)
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
    
    var body: some View {
        HStack(spacing: 4) {
            // Main track label pill
            ZStack {
                // Background pill
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? AppColors.tealAccent.opacity(0.15) : AppColors.panelBackground)
                    .frame(width: 32, height: 24)
                
                // Teal border when active
                if isActive {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(AppColors.tealAccent, lineWidth: 1.5)
                        .frame(width: 32, height: 24)
                }
                
                // Track label ("V" or "A")
                Text(track.kind == .video ? "V" : "A")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isActive ? AppColors.tealAccent : AppColors.secondaryText)
            }
            
            // Future controls area (mute, lock, visibility icons)
            // For now, just reserve space - these will be added later
            HStack(spacing: 2) {
                // Mute button (for audio tracks, or video tracks with audio)
                if track.kind == .audio {
                    Button(action: {
                        onMuteToggle?()
                    }) {
                        Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 9))
                            .foregroundColor(track.isMuted ? AppColors.orangeAccent : AppColors.secondaryText)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(track.isMuted ? "Unmute track" : "Mute track")
                }
                
                // Lock button
                Button(action: {
                    onLockToggle?()
                }) {
                    Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 9))
                        .foregroundColor(track.isLocked ? AppColors.orangeAccent : AppColors.secondaryText)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(track.isLocked ? "Unlock track" : "Lock track")
            }
            .opacity(0.6)  // Subtle appearance for future controls
            
            Spacer()
        }
        .frame(width: headerWidth, height: height)
        .padding(.horizontal, 4)
        .background(AppColors.panelBackground)
    }
}
