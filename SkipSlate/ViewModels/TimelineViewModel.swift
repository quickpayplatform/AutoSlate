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
}
