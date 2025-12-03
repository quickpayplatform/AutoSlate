//
//  TimelineViewModel.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Timeline State Management
//  - Centralizes timeline editing state (selection, tools, zoom, tracks)
//  - Manages segment selection across all tracks
//  - Coordinates editing tools (Select, Blade, Trim)
//  - Handles track creation and management
//  - Does NOT manage playback (that's PlayerViewModel)
//  - Does NOT manage project data (that's ProjectViewModel)
//

import SwiftUI
import AVFoundation

/// Unified geometry model for timeline rendering
/// Ensures time ruler ticks, segment positions, and playhead all use the same math
struct TimelineGeometry {
    /// Pixels per second (scaled by zoom)
    var pixelsPerSecond: CGFloat
    
    /// Left edge of visible viewport, in seconds (for horizontal scrolling)
    var visibleStartTime: Double
    
    /// Total duration of the timeline
    var totalDuration: Double
    
    /// Base timeline width (before zoom)
    var baseTimelineWidth: CGFloat
    
    /// Calculate X position for a given time
    /// - Parameter time: Time in seconds (composition timeline)
    /// - Returns: X position in pixels relative to timeline start
    func xPosition(for time: Double) -> CGFloat {
        let clampedTime = max(0.0, time)
        let relativeTime = clampedTime - visibleStartTime
        return CGFloat(relativeTime) * pixelsPerSecond
    }
    
    /// Calculate time for a given X position
    /// - Parameter xPosition: X position in pixels
    /// - Returns: Time in seconds (composition timeline)
    func time(for xPosition: CGFloat) -> Double {
        let relativeTime = Double(xPosition) / Double(pixelsPerSecond)
        return relativeTime + visibleStartTime
    }
    
    /// Content width (base width * zoom)
    var contentWidth: CGFloat {
        let basePixelsPerSecond = totalDuration > 0 ? baseTimelineWidth / CGFloat(totalDuration) : 80
        return baseTimelineWidth * (pixelsPerSecond / basePixelsPerSecond)
    }
}

/// Timeline editing tools
enum EditorTool: String, CaseIterable, Identifiable {
    case segmentSelect  // Dedicated Select Segment tool
    case blade
    case trim
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .segmentSelect: return "Select Segment"
        case .blade: return "Blade"
        case .trim: return "Trim"
        }
    }
    
    var iconName: String {
        switch self {
        case .segmentSelect: return "cursorarrow"
        case .blade: return "scissors"
        case .trim: return "slider.horizontal.3"
        }
    }
    
    var helpText: String {
        switch self {
        case .segmentSelect: return "Select segments"
        case .blade: return "Cut segments at click position"
        case .trim: return "Trim segment start/end points"
        }
    }
    
    var cursor: NSCursor {
        switch self {
        case .segmentSelect: return .arrow
        case .blade: return NSCursor(image: NSImage(systemSymbolName: "scissors", accessibilityDescription: nil) ?? NSImage(), hotSpot: NSPoint(x: 8, y: 8))
        case .trim: return .resizeLeftRight
        }
    }
}

/// Timeline zoom levels
enum TimelineZoom: CGFloat, CaseIterable {
    case fit = 1.0
    case x2 = 2.0
    case x4 = 4.0
    
    var label: String {
        switch self {
        case .fit: return "Fit"
        case .x2: return "2x"
        case .x4: return "4x"
        }
    }
    
    var scale: CGFloat { rawValue }
}

/// Placeholder for timeline effects (to be implemented)
struct TimelineEffect {
    enum EffectType {
        case colorGrading(presetID: UUID)
        case transition(type: String)
        case stabilization(enabled: Bool)
    }
    
    let type: EffectType
}

class TimelineViewModel: ObservableObject {
    // Selection state
    @Published var selectedSegmentIDs: Set<UUID> = []
    
    // Tool state
    @Published var currentTool: EditorTool = .segmentSelect
    
    // Zoom state
    @Published var zoomLevel: TimelineZoom = .fit
    
    // Viewport state (for horizontal scrolling)
    @Published var visibleStartTime: Double = 0.0
    
    // Base timeline width (pixels) - can be set from view
    var baseTimelineWidth: CGFloat = 1000.0
    
    // Base pixels per second (before zoom) - calculated from baseTimelineWidth and totalDuration
    func basePixelsPerSecond(totalDuration: Double) -> CGFloat {
        guard totalDuration > 0 else { return 80.0 }
        return baseTimelineWidth / CGFloat(totalDuration)
    }
    
    // Track management (read-only - tracks are owned by ProjectViewModel)
    // This view model provides helper methods for track operations
    
    // MARK: - Selection Management
    
    /// Select only this segment (clear others)
    func selectOnly(_ id: UUID) {
        selectedSegmentIDs = [id]
    }
    
    /// Toggle selection for a segment (for Cmd-click multi-select)
    func toggleSelection(_ id: UUID) {
        if selectedSegmentIDs.contains(id) {
            selectedSegmentIDs.remove(id)
        } else {
            selectedSegmentIDs.insert(id)
        }
    }
    
    /// Clear all selection
    func clearSelection() {
        selectedSegmentIDs.removeAll()
    }
    
    /// Select all segments from all tracks
    func selectAllSegments(videoTracks: [TimelineTrack], audioTracks: [TimelineTrack], allSegments: [Segment]) {
        // Get all segment IDs from all tracks
        var allIDs: Set<UUID> = []
        
        // Add segment IDs from video tracks
        for track in videoTracks {
            for segmentID in track.segments {
                allIDs.insert(segmentID)
            }
        }
        
        // Add segment IDs from audio tracks
        for track in audioTracks {
            for segmentID in track.segments {
                allIDs.insert(segmentID)
            }
        }
        
        selectedSegmentIDs = allIDs
    }
    
    // Legacy methods for backward compatibility
    func selectAllSegments(from segments: [Segment]) {
        selectedSegmentIDs = Set(segments.map { $0.id })
    }
    
    func selectSegment(_ segmentID: UUID, clearOthers: Bool = true) {
        if clearOthers {
            selectedSegmentIDs = [segmentID]
        } else {
            selectedSegmentIDs.insert(segmentID)
        }
    }
    
    // MARK: - Effects Application (Placeholder)
    
    func applyEffectToSelectedSegments(_ effect: TimelineEffect, segments: [Segment]) {
        // TODO: Implement effect application
        // This will iterate over selectedSegmentIDs and apply the effect
        print("SkipSlate: Applying effect to selected segments: \(selectedSegmentIDs.count)")
    }
    
    func applyEffectToAllSegments(_ effect: TimelineEffect, segments: [Segment]) {
        // TODO: Implement effect application
        // This will iterate over all segments and apply the effect
        print("SkipSlate: Applying effect to all segments: \(segments.count)")
    }
    
    // MARK: - Timeline Geometry
    
    /// Calculate unified geometry for timeline rendering
    /// - Parameter totalDuration: Total duration of the timeline in seconds
    /// - Returns: TimelineGeometry with correct pixel-to-time conversion
    func geometry(totalDuration: Double) -> TimelineGeometry {
        // Calculate pixels per second based on zoom
        let basePPS = basePixelsPerSecond(totalDuration: totalDuration)
        let pixelsPerSecond = basePPS * zoomLevel.scale
        
        return TimelineGeometry(
            pixelsPerSecond: pixelsPerSecond,
            visibleStartTime: visibleStartTime,
            totalDuration: totalDuration,
            baseTimelineWidth: baseTimelineWidth
        )
    }
}
