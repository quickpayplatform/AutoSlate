//
//  TrackContentView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Timeline (Kdenlive Pattern)
//  - Track content area WITHOUT header (header is rendered separately)
//  - Contains only segments and their interactions
//  - Designed to be placed in a horizontal ScrollView while headers stay fixed
//
//  ARCHITECTURE NOTE:
//  This follows Kdenlive's pattern where track headers are fixed on the left
//  and track content scrolls horizontally independently.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Track content view - segments only, no header
/// Used in conjunction with fixed TrackHeaderView for Kdenlive-style scrolling
struct TrackContentView: View {
    let track: TimelineTrack
    @ObservedObject var projectViewModel: ProjectViewModel
    // CRITICAL: Direct observation for Preview Observation Rule
    @ObservedObject var playerViewModel: PlayerViewModel
    let timelineViewModel: TimelineViewModel?
    let totalDuration: Double
    let zoomLevel: TimelineZoom
    let trackHeight: CGFloat
    let timelineWidth: CGFloat
    
    // ISOLATED: Tool state separate from player (Kdenlive pattern)
    @ObservedObject private var toolState = ToolState.shared
    
    @State private var draggedSegmentID: Segment.ID?
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(AppColors.background)
                .frame(width: timelineWidth, height: trackHeight)
            
            // Render segments
            ForEach(segmentsInTrack, id: \.id) { segment in
                if segment.kind == .clip {
                    segmentView(for: segment)
                }
            }
            
            // Empty space click handler for seeking
            if totalDuration > 0 && toolState.allowsSeek {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: timelineWidth, height: trackHeight)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .zIndex(-1)  // Behind segments
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard toolState.allowsSeek else { return }
                                let clickX = value.location.x
                                let clampedX = max(0, min(timelineWidth, clickX))
                                let timeRatio = clampedX / timelineWidth
                                let seekTime = timeRatio * totalDuration
                                playerViewModel.seek(to: max(0, min(totalDuration, seekTime)), precise: true) { _ in }
                            }
                    )
            }
        }
        .frame(width: timelineWidth, height: trackHeight)
        .clipped()
    }
    
    // MARK: - Segment Rendering
    
    private var segmentsInTrack: [Segment] {
        let segmentIDs = track.segments
        return projectViewModel.segments.filter { segmentIDs.contains($0.id) && $0.enabled }
    }
    
    private func segmentView(for segment: Segment) -> some View {
        let pixelsPerSecond = timelineWidth / CGFloat(totalDuration)
        let xPosition = CGFloat(segment.compositionStartTime) * pixelsPerSecond
        let width = CGFloat(segment.duration) * pixelsPerSecond
        let isSelected = projectViewModel.selectedSegmentIDs.contains(segment.id)
        let clipName = clipNameFor(segment)
        
        return SegmentBlockView(
            segment: segment,
            width: width,
            height: trackHeight - 4,
            isSelected: isSelected,
            color: segmentColor(for: segment),
            clipName: clipName,
            onSelect: {
                handleSegmentSelect(segment)
            }
        )
        .offset(x: xPosition)
    }
    
    private func clipNameFor(_ segment: Segment) -> String {
        guard let sourceClipID = segment.sourceClipID,
              let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) else {
            return ""
        }
        return clip.fileName
    }
    
    private func segmentColor(for segment: Segment) -> Color {
        guard let sourceClipID = segment.sourceClipID,
              let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) else {
            return Color.gray
        }
        
        // CRITICAL: Audio-only clips get the special audio color (teal-orange blend)
        if clip.type == .audioOnly {
            return ClipColorPalette.audioColor
        }
        
        if projectViewModel.project.type == .highlightReel {
            return ClipColorPalette.highlightReelColor(for: clip.colorIndex)
        } else {
            return ClipColorPalette.color(for: clip.colorIndex)
        }
    }
    
    private func handleSegmentSelect(_ segment: Segment) {
        guard toolState.allowsSelection else { return }
        
        let isCommandKey = NSEvent.modifierFlags.contains(.command)
        
        if isCommandKey {
            // Multi-select toggle
            if projectViewModel.selectedSegmentIDs.contains(segment.id) {
                projectViewModel.selectedSegmentIDs.remove(segment.id)
            } else {
                projectViewModel.selectedSegmentIDs.insert(segment.id)
            }
        } else {
            // Single select
            projectViewModel.selectedSegmentIDs = [segment.id]
        }
        projectViewModel.selectedSegment = segment
    }
}

// MARK: - Segment Block View

/// A simple visual block representing a segment
private struct SegmentBlockView: View {
    let segment: Segment
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let color: Color
    let clipName: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: width, height: height)
                
                // Selection border
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(AppColors.tealAccent, lineWidth: 2)
                        .frame(width: width, height: height)
                }
                
                // Clip name (if fits)
                if width > 60 {
                    Text(clipName)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

