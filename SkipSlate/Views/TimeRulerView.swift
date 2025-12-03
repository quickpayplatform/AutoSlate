//
//  TimeRulerView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline
//  - Time ruler component - THE "HOUSE" for the timeline
//  - Extends to a fixed duration (5 hours) independent of content
//  - Segments live within this ruler
//  - Supports clicking to seek within content bounds
//

import SwiftUI
import AVFoundation

struct TimeRulerView: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    let timelineViewModel: TimelineViewModel
    
    // THE "HOUSE" - Fixed ruler duration (e.g., 5 hours)
    let rulerDuration: Double
    
    // THE "RESIDENTS" - Actual content duration (for seeking limits)
    let contentDuration: Double
    
    let earliestStartTime: Double
    let onSeek: (Double) -> Void
    let frameRate: Double
    
    // Height of the ruler
    private let rulerHeight: CGFloat = 30
    
    // Fixed pixels per second for the ruler
    private let basePixelsPerSecond: CGFloat = 80.0
    
    init(
        playerViewModel: PlayerViewModel,
        timelineViewModel: TimelineViewModel,
        rulerDuration: Double,
        contentDuration: Double,
        earliestStartTime: Double = 0.0,
        onSeek: @escaping (Double) -> Void,
        frameRate: Double = 30.0
    ) {
        self.playerViewModel = playerViewModel
        self.timelineViewModel = timelineViewModel
        self.rulerDuration = rulerDuration
        self.contentDuration = contentDuration
        self.earliestStartTime = earliestStartTime
        self.onSeek = onSeek
        self.frameRate = frameRate
    }
    
    // Pixels per second with zoom applied
    private var pixelsPerSecond: CGFloat {
        basePixelsPerSecond * timelineViewModel.zoomLevel.scale
    }
    
    // Total width of the ruler
    private var rulerWidth: CGFloat {
        CGFloat(rulerDuration) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // STATIC: Background and markers (cached, doesn't update with playhead)
            TimeRulerMarkersView(
                rulerDuration: rulerDuration,
                earliestStartTime: earliestStartTime,
                pixelsPerSecond: pixelsPerSecond,
                zoomLevel: timelineViewModel.zoomLevel,
                rulerHeight: rulerHeight,
                rulerWidth: rulerWidth,
                frameRate: frameRate
            )
            
            // DYNAMIC: Playhead only (updates smoothly with video)
            TimeRulerPlayhead(
                playerViewModel: playerViewModel,
                contentDuration: contentDuration,
                pixelsPerSecond: pixelsPerSecond,
                rulerHeight: rulerHeight
            )
        }
        .frame(width: rulerWidth, height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let clickedX = value.location.x
                    let clickedTime = Double(clickedX) / Double(pixelsPerSecond)
                    let clampedTime = max(0, min(contentDuration, clickedTime))
                    onSeek(clampedTime)
                }
                .onEnded { value in
                    let clickedX = value.location.x
                    let clickedTime = Double(clickedX) / Double(pixelsPerSecond)
                    let clampedTime = max(0, min(contentDuration, clickedTime))
                    onSeek(clampedTime)
                }
        )
    }
}

// MARK: - Static Markers View (doesn't observe PlayerViewModel)
private struct TimeRulerMarkersView: View {
    let rulerDuration: Double
    let earliestStartTime: Double
    let pixelsPerSecond: CGFloat
    let zoomLevel: TimelineZoom
    let rulerHeight: CGFloat
    let rulerWidth: CGFloat
    let frameRate: Double
    
    // Calculate time interval between major markers based on zoom
    private var timeInterval: Double {
        switch zoomLevel {
        case .fit:
            return 10.0  // Every 10 seconds
        case .x2:
            return 5.0   // Every 5 seconds
        case .x4:
            return 2.0   // Every 2 seconds
        }
    }
    
    private var subInterval: Double {
        return timeInterval / 2.0
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(AppColors.panelBackground)
                .frame(width: rulerWidth, height: rulerHeight)
            
            // Time markers - rendered as a single cached layer for performance
            Canvas { context, size in
                let startTime = floor(earliestStartTime / timeInterval) * timeInterval
                
                // Draw major markers
                var currentTime = max(0, startTime)
                while currentTime <= rulerDuration {
                    let xPosition = CGFloat(currentTime) * pixelsPerSecond
                    
                    // Major tick
                    let tickRect = CGRect(x: xPosition, y: 0, width: 1.5, height: rulerHeight * 0.6)
                    context.fill(Path(tickRect), with: .color(AppColors.secondaryText.opacity(0.8)))
                    
                    // Time label
                    let timeText = formatTime(currentTime)
                    let text = Text(timeText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    context.draw(text, at: CGPoint(x: xPosition + 4, y: rulerHeight - 8), anchor: .leading)
                    
                    currentTime += timeInterval
                }
                
                // Draw minor markers
                currentTime = max(0, startTime) + subInterval
                while currentTime <= rulerDuration {
                    let xPosition = CGFloat(currentTime) * pixelsPerSecond
                    
                    // Check if close to major marker
                    let closestMajor = round(currentTime / timeInterval) * timeInterval
                    if abs(currentTime - closestMajor) > 0.1 {
                        let tickRect = CGRect(x: xPosition, y: 0, width: 1, height: rulerHeight * 0.4)
                        context.fill(Path(tickRect), with: .color(AppColors.secondaryText.opacity(0.4)))
                    }
                    
                    currentTime += subInterval
                }
            }
            .frame(width: rulerWidth, height: rulerHeight)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Dynamic Playhead View (observes PlayerViewModel for smooth updates)
private struct TimeRulerPlayhead: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    let contentDuration: Double
    let pixelsPerSecond: CGFloat
    let rulerHeight: CGFloat
    
    var body: some View {
        if contentDuration > 0 {
            let playheadX = CGFloat(playerViewModel.currentTime) * pixelsPerSecond
            
            // Playhead line
            Rectangle()
                .fill(AppColors.tealAccent)
                .frame(width: 2, height: rulerHeight)
                .offset(x: playheadX)
            
            // Playhead triangle
            Triangle()
                .fill(AppColors.tealAccent)
                .frame(width: 8, height: 6)
                .offset(x: playheadX - 4, y: rulerHeight - 6)
        }
    }
}

// Triangle shape is defined in PlayheadIndicator.swift
