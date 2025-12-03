//
//  PlayheadIndicator.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

/// Playhead indicator that shows current playback position on the timeline
struct PlayheadIndicator: View {
    @ObservedObject var playerVM: PlayerViewModel
    let totalDuration: Double
    let timelineWidth: CGFloat
    let zoomLevel: TimelineZoom
    let trackHeight: CGFloat // Spans video (60) + divider + audio (50)
    let selectedTool: TimelineTool // Current timeline tool - playhead only draggable with cursor tool
    
    init(
        playerVM: PlayerViewModel,
        totalDuration: Double,
        timelineWidth: CGFloat,
        zoomLevel: TimelineZoom,
        trackHeight: CGFloat = 110,
        selectedTool: TimelineTool = .cursor
    ) {
        self.playerVM = playerVM
        self.totalDuration = totalDuration
        self.timelineWidth = timelineWidth
        self.zoomLevel = zoomLevel
        self.trackHeight = trackHeight
        self.selectedTool = selectedTool
    }
    
    @State private var isDragging = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartTime: Double = 0
    
    private let baseTimelineWidth: CGFloat = 1000 // Base width for timeline calculations
    private let trackLabelWidth: CGFloat = 40 // Width of track labels (V1, V2, A1, etc.)
    
    var body: some View {
        let currentTime = playerVM.currentTime
        
        if totalDuration > 0 && currentTime >= 0 {
            // Calculate X position based on current time
            // Use the actual timeline width (from scrollable content) or fall back to base width
            let effectiveWidth = timelineWidth > 0 ? timelineWidth : (baseTimelineWidth * zoomLevel.scale)
            let timeRatio = min(1.0, max(0.0, currentTime / totalDuration))
            // CRITICAL: Offset by track label width so playhead starts at the first clip, not before labels
            let xPosition = trackLabelWidth + (timeRatio * effectiveWidth)
            
            ZStack(alignment: .topLeading) {
                // Short vertical line - just a small indicator, not spanning full height
                Rectangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 2, height: 20)
                    .offset(x: xPosition - 1, y: 0)
                
                // Arrow/cursor at top
                Triangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 12, height: 8)
                    .offset(x: xPosition - 6, y: -8)
                
                // Drag area for playhead (only active with cursor tool)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 40, height: 30)
                    .offset(x: xPosition - 20, y: -8)
                    .contentShape(Rectangle())
                    .cursor(selectedTool == .cursor ? .pointingHand : .arrow)
                    .gesture(
                        // Only allow dragging playhead when cursor tool is selected
                        selectedTool == .cursor ?
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                        // CRITICAL: Account for track label width in drag start position
                                    dragStartX = value.startLocation.x
                                    dragStartTime = currentTime
                                    if playerVM.isPlaying {
                                        playerVM.pause()
                                    }
                                }
                                
                                // Calculate new time based on absolute position, not relative translation
                                // This provides more precise control
                                    // CRITICAL: Account for track label width when calculating time from X position
                                let absoluteX = dragStartX + value.translation.width
                                    let contentX = max(0, absoluteX - trackLabelWidth) // Subtract label width
                                    let clampedX = max(0, min(effectiveWidth, contentX))
                                let newTimeRatio = clampedX / effectiveWidth
                                let newTime = newTimeRatio * totalDuration
                                
                                // Use precise seeking during drag for frame-accurate positioning
                                playerVM.seek(to: max(0, min(totalDuration, newTime)), precise: true)
                            }
                            .onEnded { _ in
                                isDragging = false
                                } : nil
                    )
            }
            // No animation - direct position updates for frame-accurate playhead
            // Animation causes lag and makes playhead appear behind the actual playback position
        } else {
            // Return empty view if no duration or invalid time
            EmptyView()
        }
    }
}

/// Triangle shape for playhead arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

