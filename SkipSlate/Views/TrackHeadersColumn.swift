//
//  TrackHeadersColumn.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Timeline (Kdenlive Pattern)
//  - Fixed column of track headers on the left side of timeline
//  - Does NOT scroll horizontally (stays fixed while content scrolls)
//  - Scrolls vertically with track content
//
//  ARCHITECTURE NOTE:
//  This follows Kdenlive's pattern where track headers are fixed on the left.
//  The horizontal ScrollView only contains track content, not headers.
//

import SwiftUI

/// Fixed column of track headers - doesn't scroll horizontally
struct TrackHeadersColumn: View {
    let tracks: [TimelineTrack]
    let trackHeightForID: (UUID) -> CGFloat
    let defaultTrackHeight: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                let height = trackHeightForID(track.id)
                
                TrackHeaderView(
                    track: track,
                    isActive: false,
                    height: height
                )
                .frame(height: height)
                
                // Track divider
                if index < tracks.count - 1 {
                    Rectangle()
                        .fill(Color(white: 0.2))
                        .frame(height: 1)
                }
            }
        }
        .frame(width: 50)  // Fixed width for headers
        .background(AppColors.panelBackground)
    }
}

// MARK: - Preview

#Preview {
    TrackHeadersColumn(
        tracks: [
            TimelineTrack(kind: .video, index: 0),
            TimelineTrack(kind: .video, index: 1),
            TimelineTrack(kind: .audio, index: 0),
        ],
        trackHeightForID: { _ in 60 },
        defaultTrackHeight: 60
    )
    .frame(height: 200)
    .background(AppColors.background)
}

