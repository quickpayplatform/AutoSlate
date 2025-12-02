//
//  TimeRulerView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline
//  - Time ruler component for timeline with timestamps and playhead
//  - Shows time markers based on zoom level
//  - Syncs playhead with PlayerViewModel.currentTime
//  - Supports clicking to seek and snap-to-grid
//

import SwiftUI
import AVFoundation

struct TimeRulerView: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    let totalDuration: Double
    let zoomLevel: TimelineZoom
    let baseTimelineWidth: CGFloat
    let onSeek: (Double) -> Void
    
    // Height of the ruler
    private let rulerHeight: CGFloat = 30
    
    // Calculate content width based on zoom
    private var contentWidth: CGFloat {
        baseTimelineWidth * zoomLevel.scale
    }
    
    // Calculate pixels per second
    private var pixelsPerSecond: CGFloat {
        guard totalDuration > 0 else { return 100 }
        return contentWidth / CGFloat(totalDuration)
    }
    
    // Calculate time interval between markers based on zoom
    private var timeInterval: Double {
        switch zoomLevel {
        case .fit:
            // At fit, show markers every 5 seconds
            return 5.0
        case .x2:
            // At 2x, show markers every 2 seconds
            return 2.0
        case .x4:
            // At 4x, show markers every 1 second
            return 1.0
        }
    }
    
    // Calculate sub-interval for minor ticks (half of main interval)
    private var subInterval: Double {
        return timeInterval / 2.0
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(AppColors.panelBackground)
                .frame(height: rulerHeight)
            
            // Time markers and labels
            ForEach(timeMarkers, id: \.time) { marker in
                TimeMarker(
                    time: marker.time,
                    xPosition: marker.xPosition,
                    isMajor: marker.isMajor,
                    height: rulerHeight
                )
            }
            
            // Playhead indicator
            if totalDuration > 0 {
                let currentTime = playerViewModel.currentTime
                let playheadX = CGFloat(currentTime) * pixelsPerSecond
                
                Rectangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 2)
                    .offset(x: playheadX)
                    .frame(height: rulerHeight)
                
                // Playhead triangle
                Triangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 8, height: 6)
                    .offset(x: playheadX - 4, y: rulerHeight - 6)
            }
        }
        .frame(width: contentWidth, height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Seek to clicked position
                    let clickedX = value.location.x
                    let clickedTime = Double(clickedX / pixelsPerSecond)
                    let clampedTime = max(0, min(totalDuration, clickedTime))
                    
                    // Snap to nearest marker if close enough
                    let snappedTime = snapToGrid(time: clampedTime)
                    onSeek(snappedTime)
                }
                .onEnded { value in
                    // Final seek on release
                    let clickedX = value.location.x
                    let clickedTime = Double(clickedX / pixelsPerSecond)
                    let clampedTime = max(0, min(totalDuration, clickedTime))
                    let snappedTime = snapToGrid(time: clampedTime)
                    onSeek(snappedTime)
                }
        )
    }
    
    // Generate time markers based on zoom and duration
    private var timeMarkers: [TimeMarkerData] {
        var markers: [TimeMarkerData] = []
        
        guard totalDuration > 0 else { return markers }
        
        // Generate major markers (every timeInterval)
        var currentTime: Double = 0
        while currentTime <= totalDuration {
            let xPosition = CGFloat(currentTime) * pixelsPerSecond
            markers.append(TimeMarkerData(
                time: currentTime,
                xPosition: xPosition,
                isMajor: true
            ))
            currentTime += timeInterval
        }
        
        // Generate minor markers (every subInterval, but skip if they overlap with major)
        currentTime = subInterval
        while currentTime <= totalDuration {
            // Only add if it's not too close to a major marker
            let isCloseToMajor = markers.contains { abs($0.time - currentTime) < 0.1 }
            if !isCloseToMajor {
                let xPosition = CGFloat(currentTime) * pixelsPerSecond
                markers.append(TimeMarkerData(
                    time: currentTime,
                    xPosition: xPosition,
                    isMajor: false
                ))
            }
            currentTime += subInterval
        }
        
        // Sort by time
        return markers.sorted { $0.time < $1.time }
    }
    
    // Snap time to nearest grid point
    private func snapToGrid(time: Double) -> Double {
        // Snap to nearest subInterval
        let snapped = round(time / subInterval) * subInterval
        return max(0, min(totalDuration, snapped))
    }
    
    // Helper struct for marker data
    private struct TimeMarkerData {
        let time: Double
        let xPosition: CGFloat
        let isMajor: Bool
    }
}

// Individual time marker view
private struct TimeMarker: View {
    let time: Double
    let xPosition: CGFloat
    let isMajor: Bool
    let height: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Tick mark
            Rectangle()
                .fill(AppColors.secondaryText.opacity(isMajor ? 0.8 : 0.4))
                .frame(width: isMajor ? 1.5 : 1, height: isMajor ? height * 0.6 : height * 0.4)
                .offset(x: xPosition, y: 0)
            
            // Time label (only for major markers, positioned at bottom)
            if isMajor {
                Text(timeString(from: time))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .offset(x: xPosition + 2, y: height - 12)
            }
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// Triangle shape is defined in PlayheadIndicator.swift - reuse that one
