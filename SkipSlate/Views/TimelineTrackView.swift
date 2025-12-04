//
//  TimelineTrackView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Individual track row in the timeline
struct TimelineTrackView: View {
    let track: TimelineTrack
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject var playerViewModel: PlayerViewModel
    let timelineViewModel: TimelineViewModel?  // Optional - not all views have TimelineViewModel
    let totalDuration: Double
    let zoomLevel: TimelineZoom
    let trackHeight: CGFloat
    let timelineWidth: CGFloat
    // Cross-track movement support
    let allTracks: [TimelineTrack]
    let trackYOffset: CGFloat  // Y position of this track within the timeline scroll area
    let onCrossTrackMove: ((Segment.ID, Double, CGFloat) -> Void)?  // segmentID, newTime, yOffset
    // ISOLATED tool state - no connection to player/preview
    @ObservedObject private var toolState = ToolState.shared
    
    init(
        track: TimelineTrack,
        projectViewModel: ProjectViewModel,
        playerViewModel: PlayerViewModel,
        timelineViewModel: TimelineViewModel? = nil,
        totalDuration: Double,
        zoomLevel: TimelineZoom,
        trackHeight: CGFloat,
        timelineWidth: CGFloat,
        allTracks: [TimelineTrack] = [],
        trackYOffset: CGFloat = 0,
        onCrossTrackMove: ((Segment.ID, Double, CGFloat) -> Void)? = nil
    ) {
        self.track = track
        self.projectViewModel = projectViewModel
        self.playerViewModel = playerViewModel
        self.timelineViewModel = timelineViewModel
        self.totalDuration = totalDuration
        self.zoomLevel = zoomLevel
        self.trackHeight = trackHeight
        self.timelineWidth = timelineWidth
        self.allTracks = allTracks
        self.trackYOffset = trackYOffset
        self.onCrossTrackMove = onCrossTrackMove
    }
    
    @State private var draggedSegmentID: Segment.ID?
    @State private var dragOffset: CGFloat = 0
    @State private var trimmingSegmentID: Segment.ID?
    @State private var trimHandle: TrimHandle?
    
    var body: some View {
        // Track content area only - headers are rendered separately in EnhancedTimelineView
        // This allows headers to stay fixed while content scrolls
        ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(AppColors.background)
                    .frame(height: trackHeight)
                
                // Render gaps and segments in timeline order
                ForEach(timelineItems, id: \.id) { item in
                    if case .segment(let segment) = item {
                        // Only render clip segments (gaps are rendered separately) - using helper
                        if segment.isClip {
                            TimelineSegmentView(
                                segment: segment,
                                track: track,
                                isSelected: projectViewModel.selectedSegmentIDs.contains(segment.id),
                                totalDuration: totalDuration,
                                zoomLevel: zoomLevel,
                                trackHeight: trackHeight,
                                timelineWidth: timelineWidth,
                                projectViewModel: projectViewModel,
                                onSelect: { isCommandKey in
                                    // CRITICAL: Only allow selecting clip segments, not gaps
                                    guard segment.kind == .clip else {
                                        print("SkipSlate: ⚠️ Ignoring selection of gap segment")
                                        return
                                    }
                                    
                                    // CRITICAL: Always fetch the latest segment from the project to avoid stale references
                                    guard let latestSegment = projectViewModel.segments.first(where: { $0.id == segment.id }) else {
                                        print("SkipSlate: ⚠️ Segment not found in project segments: \(segment.id)")
                                        return
                                    }
                                    
                                    print("SkipSlate: 🔵 SELECTING segment: \(segment.id)")
                                    
                                    // CRITICAL: Update selection SYNCHRONOUSLY on main thread
                                    // We're already in a gesture handler, so we're on main thread
                                    if isCommandKey {
                                        // Toggle selection (Cmd-click) - multi-select
                                        if projectViewModel.selectedSegmentIDs.contains(segment.id) {
                                            projectViewModel.selectedSegmentIDs.remove(segment.id)
                                            if projectViewModel.selectedSegment?.id == segment.id {
                                                projectViewModel.selectedSegment = nil
                                            }
                                        } else {
                                            projectViewModel.selectedSegmentIDs.insert(segment.id)
                                            projectViewModel.selectedSegment = latestSegment
                                        }
                                    } else {
                                        // Single click - select ONLY this segment (clear others)
                                        projectViewModel.selectedSegmentIDs = [segment.id]
                                        projectViewModel.selectedSegment = latestSegment
                                    }
                                    
                                    print("SkipSlate: ✅ Selection updated - Segment: \(latestSegment.id), selectedSegmentIDs count: \(projectViewModel.selectedSegmentIDs.count), selectedSegment set: \(projectViewModel.selectedSegment != nil)")
                                    
                                    // CRITICAL: Force SwiftUI to update immediately
                                    projectViewModel.objectWillChange.send()
                                },
                                onDelete: {
                                    projectViewModel.removeSegment(segment.id)
                                },
                                onTrimStart: { newStart in
                                    trimSegment(segment, start: newStart, end: nil)
                                },
                                onTrimEnd: { newEnd in
                                    trimSegment(segment, start: nil, end: newEnd)
                                },
                                trackYOffset: trackYOffset,
                                onCrossTrackMove: onCrossTrackMove
                            )
                            .offset(x: itemXPosition(for: item))
                            .animation(.easeInOut(duration: 0.2), value: itemXPosition(for: item))  // Smooth animation for position changes
                        }
                    } else if case .gap(let gapDuration, let gapStart) = item {
                        // Render gap as dark gray rectangle
                        let gapWidth = gapWidth(for: gapDuration)
                        let gapX = gapXPosition(for: gapStart)
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .frame(width: gapWidth, height: trackHeight - 4)
                            .offset(x: gapX)
                            .overlay(
                                // Subtle pattern to indicate gap
                                Rectangle()
                                    .strokeBorder(Color(white: 0.25), lineWidth: 1)
                            )
                    }
                }
                // NOTE: No horizontal padding - segments must align exactly with time ruler
                
                // Empty space click handler for seeking - ONLY when cursor tool is selected
                // Other tools should not move the playhead when clicking empty space
                // CRITICAL: This Rectangle must be behind segments so it doesn't block tool interactions
                Group {
                    if totalDuration > 0 && toolState.selectedTool == .cursor {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: trackHeight)
                            .contentShape(Rectangle())
                            .allowsHitTesting(true)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        // Only allow seeking with cursor tool
                                        guard toolState.selectedTool == .cursor else { return }
                                        
                                        // Calculate time from click position
                                        let clickX = value.location.x
                                        let clampedX = max(0, min(timelineWidth, clickX))
                                        let timeRatio = clampedX / timelineWidth
                                        let seekTime = timeRatio * totalDuration
                                        
                                        // Seek to clicked position
                                        playerViewModel.seek(to: max(0, min(totalDuration, seekTime)), precise: true) { _ in }
                                        
                                        // Clear selection when clicking empty space
                                        projectViewModel.selectedSegmentIDs.removeAll()
                                        projectViewModel.selectedSegment = nil
                                    }
                            )
                            .onDrop(of: [UTType.segmentID], isTargeted: nil) { providers, location in
                                return handleSegmentDrop(providers: providers, location: location, timelineWidth: timelineWidth, totalDuration: totalDuration)
                            }
                    } else {
                        // When other tools are active, don't block interactions - just provide drop zone
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: trackHeight)
                            .allowsHitTesting(false) // Don't block segment interactions
                            .onDrop(of: [UTType.segmentID], isTargeted: nil) { providers, location in
                                // Only allow drops when cursor tool is selected
                                guard toolState.selectedTool == .cursor else { return false }
                                return handleSegmentDrop(providers: providers, location: location, timelineWidth: timelineWidth, totalDuration: totalDuration)
                            }
                    }
                }
        }
        .clipped() // CRITICAL: Prevent segments from visually leaking behind track header when dragged
        .frame(height: trackHeight)
    }
    
    // CRITICAL: Always get the FRESH track from projectViewModel to avoid stale segment lists
    // The `track` parameter is a snapshot - we need the current version
    private var currentTrack: TimelineTrack {
        projectViewModel.project.tracks.first { $0.id == track.id } ?? track
    }
    
    private var segmentsInOrder: [Segment] {
        projectViewModel.segmentsInOrder(for: currentTrack)
    }
    
    // Handle dropping segments onto the timeline
    private func handleSegmentDrop(providers: [NSItemProvider], location: CGPoint, timelineWidth: CGFloat, totalDuration: Double) -> Bool {
        guard let provider = providers.first else { return false }
        
        // Load the segment ID from the drop
        provider.loadItem(forTypeIdentifier: UTType.segmentID.identifier, options: nil) { item, error in
            guard error == nil else {
                print("SkipSlate: Failed to load segment from drop: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            // Decode the SegmentIDTransfer
            guard let data = item as? Data,
                  let transfer = try? JSONDecoder().decode(SegmentIDTransfer.self, from: data) else {
                print("SkipSlate: Failed to decode segment transfer")
                return
            }
            
            // Get the cached segment
            guard let cachedSegment = projectViewModel.getCachedSegment(by: transfer.segmentID) else {
                print("SkipSlate: Cached segment not found for ID: \(transfer.segmentID)")
                return
            }
            
            // Calculate drop position from location
            let dropX = location.x
            let clampedX = max(0, min(timelineWidth, dropX))
            let timeRatio = totalDuration > 0 ? clampedX / timelineWidth : 0
            let dropTime = timeRatio * totalDuration
            
            DispatchQueue.main.async {
                // Add segment to timeline at drop position
                projectViewModel.addSegmentToTimeline(cachedSegment, at: max(0, dropTime))
                print("SkipSlate: ✅ Dropped segment at \(dropTime)s (location: \(location))")
            }
        }
        
        return true
    }
    
    // Timeline item type for rendering gaps and segments
    private enum TimelineItem: Identifiable {
        case segment(Segment)
        case gap(duration: Double, startTime: Double)
        
        var id: String {
            switch self {
            case .segment(let seg): 
                return "segment-\(seg.id.uuidString)"
            case .gap(let duration, let startTime):
                // Create a stable ID for gaps
                return "gap-\(startTime)-\(duration)"
            }
        }
    }
    
    // Build timeline items (segments + gaps) in chronological order
    private var timelineItems: [TimelineItem] {
        // Get all segments (both clip and gap) for this track
        let allSegments = segmentsInOrder.filter { $0.enabled }
        guard !allSegments.isEmpty else { return [] }
        
        var items: [TimelineItem] = []
        
        // Sort all segments (clips and gaps) by composition start time
        // CRITICAL: Use >= 0, not > 0, because position 0.0 is valid (sentinel is -1.0)
        let sortedSegments = allSegments.sorted { seg1, seg2 in
            let start1 = seg1.compositionStartTime >= 0 ? seg1.compositionStartTime : projectViewModel.compositionStart(for: seg1)
            let start2 = seg2.compositionStartTime >= 0 ? seg2.compositionStartTime : projectViewModel.compositionStart(for: seg2)
            return start1 < start2
        }
        
        // Convert segments to timeline items
        for segment in sortedSegments {
            if segment.kind == .gap {
                // Explicit gap segment - render as gap
                items.append(.gap(duration: segment.duration, startTime: segment.compositionStartTime))
            } else {
                // Clip segment - render as segment
                items.append(.segment(segment))
            }
        }
        
        return items
    }
    
    // Fixed pixels per second (must match TimeRulerView for alignment)
    private let basePixelsPerSecond: CGFloat = 80.0
    
    private var pixelsPerSecond: CGFloat {
        basePixelsPerSecond * zoomLevel.scale
    }
    
    private func itemXPosition(for item: TimelineItem) -> CGFloat {
        let time: Double
        
        switch item {
        case .segment(let segment):
            // CRITICAL: Use >= 0, not > 0, because position 0.0 is valid (sentinel is -1.0)
            time = segment.compositionStartTime >= 0 ? segment.compositionStartTime : projectViewModel.compositionStart(for: segment)
        case .gap(_, let startTime):
            time = startTime
        }
        
        // Use fixed pixels per second for consistent positioning with ruler
        return CGFloat(time) * pixelsPerSecond
    }
    
    private func gapXPosition(for startTime: Double) -> CGFloat {
        return CGFloat(startTime) * pixelsPerSecond
    }
    
    private func gapWidth(for duration: Double) -> CGFloat {
        return CGFloat(duration) * pixelsPerSecond
    }
    
    private func trimSegment(_ segment: Segment, start: Double?, end: Double?) {
        guard let index = projectViewModel.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        
        // Mark that user has manually modified the auto-edit
        projectViewModel.hasUserModifiedAutoEdit = true
        
        var updatedSegment = projectViewModel.segments[index]
        let originalDuration = updatedSegment.duration
        let originalCompStart = updatedSegment.compositionStartTime
        
        if let newStart = start {
            // Ensure minimum duration
            let minEnd = newStart + 0.1
            if updatedSegment.sourceEnd < minEnd {
                updatedSegment.sourceEnd = minEnd
            }
            updatedSegment.sourceStart = max(0, newStart)
            
            // When trimming left edge, compositionStartTime changes
            let newDuration = updatedSegment.sourceEnd - updatedSegment.sourceStart
            let durationDelta = newDuration - originalDuration
            updatedSegment.compositionStartTime = max(0, originalCompStart - durationDelta)
        }
        
        if let newEnd = end {
            // Ensure minimum duration
            let minStart = newEnd - 0.1
            if updatedSegment.sourceStart > minStart {
                updatedSegment.sourceStart = minStart
            }
            updatedSegment.sourceEnd = newEnd
        }
        
        // Ensure we don't go beyond source clip bounds (only for clip segments)
        if segment.kind == .clip,
           let sourceClipID = segment.sourceClipID,
           let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) {
            updatedSegment.sourceStart = max(0, min(updatedSegment.sourceStart, clip.duration - 0.1))
            updatedSegment.sourceEnd = max(updatedSegment.sourceStart + 0.1, min(updatedSegment.sourceEnd, clip.duration))
        }
        
        // Ensure compositionStartTime doesn't go negative
        updatedSegment.compositionStartTime = max(0, updatedSegment.compositionStartTime)
        
        // REMOVED: Manual playback state management
        // PlayerViewModel handles playback preservation during composition rebuilds
        // Preview should be a pure mirror - only reflect composition changes
        
        projectViewModel.segments[index] = updatedSegment
        projectViewModel.updateSegmentTiming(updatedSegment, start: updatedSegment.sourceStart, end: updatedSegment.sourceEnd)
        
        print("SkipSlate: ✅ Trim complete - segment updated")
    }
}

/// Individual segment view within a track - SIMPLIFIED for responsiveness
/// Only uses projectViewModel for data, toolState for cursor behavior
struct TimelineSegmentView: View {
    let segment: Segment
    let track: TimelineTrack
    let isSelected: Bool
    let totalDuration: Double
    let zoomLevel: TimelineZoom
    let trackHeight: CGFloat
    let timelineWidth: CGFloat
    @ObservedObject var projectViewModel: ProjectViewModel
    // REMOVED: playerViewModel - not needed for segment display, improves performance
    let onSelect: (Bool) -> Void  // Bool indicates if Command key is pressed
    let onDelete: () -> Void
    let onTrimStart: (Double) -> Void
    let onTrimEnd: (Double) -> Void
    // Cross-track movement support
    let trackYOffset: CGFloat
    let onCrossTrackMove: ((Segment.ID, Double, CGFloat) -> Void)?
    // ISOLATED tool state - no connection to player/preview
    @ObservedObject private var toolState = ToolState.shared
    
    @State private var isDragging = false
    @State private var isTrimming = false
    @State private var hoveredEdge: TrimHandle?
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dragStartTime: Double = 0
    @State private var dragLastUpdateTime: TimeInterval? = nil
    @State private var dragVisualOffset: CGFloat = 0
    
    private let trimHandleWidth: CGFloat = 8
    
    private var segmentColor: Color {
        // CRASH-PROOF: Comprehensive validation
        if !segment.enabled {
            return Color.gray.opacity(0.3)
        }
        
        // Gap segments should not be rendered here (they're handled separately)
        guard segment.kind == .clip,
              let sourceClipID = segment.sourceClipID else {
            return Color.gray
        }
        
        // Find the clip and use its assigned colorIndex
        if let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) {
            // CRITICAL: Audio-only clips get the special audio color (teal-orange blend)
            // colorIndex of -1 also indicates audio color
            if clip.type == .audioOnly || clip.colorIndex == -1 {
                return ClipColorPalette.audioColor
            }
            
            // Use unified color palette - works for all project types
            // Each clip has a unique colorIndex assigned during import
            return ClipColorPalette.color(for: clip.colorIndex)
        }
        
        // CRASH-PROOF: Fallback with bounds checking
        let hash = sourceClipID.uuidString.hashValue
        let fallbackIndex = abs(hash)
        return ClipColorPalette.color(for: fallbackIndex)
    }
    
    private var compositionStart: Double {
        projectViewModel.compositionStart(for: segment)
    }
    
    // Fixed pixels per second (must match TimeRulerView for alignment)
    private let basePixelsPerSecond: CGFloat = 80.0
    
    private var pixelsPerSecond: CGFloat {
        basePixelsPerSecond * zoomLevel.scale
    }
    
    private var width: CGFloat {
        // Use fixed pixels per second for consistent sizing with ruler
        let calculatedWidth = CGFloat(segment.duration) * pixelsPerSecond
        return max(calculatedWidth, 40) // Minimum width for trim handles
    }
    
    private var xPosition: CGFloat {
        // Use fixed pixels per second for consistent positioning with ruler
        return CGFloat(compositionStart) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main segment block - SOLID VISUAL APPEARANCE
            // Smooth animation for position changes
            RoundedRectangle(cornerRadius: 4)
                .fill(segmentColor)
                .frame(width: width, height: trackHeight - 4)
                .offset(x: dragVisualOffset)  // Visual offset during drag for smooth motion
                .overlay(
                    // Solid border to separate segments - more visible for solid appearance
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                )
                .overlay(
                    // SELECTED indicator (teal border when selected - DaVinci-style)
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppColors.tealAccent, lineWidth: 2.5)
                                .shadow(color: AppColors.tealAccent.opacity(0.5), radius: 2, x: 0, y: 0)
                        }
                    }
                )
                .overlay(
                    // Disabled pattern
                    Group {
                        if !segment.enabled {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.3))
                            
                            // Diagonal stripes
                            Path { path in
                                let stripeWidth: CGFloat = 4
                                var x: CGFloat = 0
                                while x < width {
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x + stripeWidth, y: trackHeight - 4))
                                    x += stripeWidth * 2
                                }
                            }
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                    }
                )
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .gesture(
                    // Tool-specific gesture handling
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            // Only treat as tap if movement was minimal (not a drag)
                            let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            guard dragDistance < 3 else { return } // Less than 3 pixels = tap
                            
                            // CRITICAL: Only allow selecting clip segments, not gaps
                            guard segment.kind == .clip else {
                                print("SkipSlate: ⚠️ Ignoring tap on gap segment")
                                return
                            }
                            
                            // Check TimelineTool from ProjectViewModel (primary tool system)
                            let timelineTool = toolState.selectedTool
                            
                            print("SkipSlate: 🔵 TAP DETECTED with TimelineTool: \(timelineTool.name) for segment: \(segment.id)")
                            
                            // Handle selection when segmentSelector tool is active
                            switch timelineTool {
                            case .segmentSelector, .cursor:
                                // Selection behavior - segmentSelector is the dedicated select tool
                                let isCommandKey = NSEvent.modifierFlags.contains(.command)
                                
                                // Call onSelect which handles the actual selection logic
                                onSelect(isCommandKey)
                                print("SkipSlate: ✅ Selection complete (segmentSelector tool) - selectedSegmentIDs count: \(projectViewModel.selectedSegmentIDs.count)")
                                
                            case .move:
                                // Move tool - select segment first, then user can drag it
                                onSelect(false)
                                print("SkipSlate: 🎯 Move tool - selected segment for dragging")
                                
                            case .cut:
                                // Cut tool - cut segment at click position (not playhead)
                                // Calculate time from click X position within the segment
                                let clickX = value.location.x
                                let segmentX = xPosition
                                let relativeX = clickX - segmentX
                                
                                // Validate click is actually on the segment
                                guard relativeX >= 0 && relativeX <= width else {
                                    print("SkipSlate: ⚠️ Click outside segment bounds for cut")
                                    return
                                }
                                
                                // Calculate cut time using fixed pixels per second
                                let clickTimeOffset = Double(relativeX) / Double(pixelsPerSecond)
                                let cutTime = compositionStart + clickTimeOffset
                                
                                // Ensure cut time is within segment bounds (with minimum margins)
                                let segmentStart = compositionStart
                                let segmentEnd = compositionStart + segment.duration
                                let clampedCutTime = max(segmentStart + 0.1, min(segmentEnd - 0.1, cutTime))
                                
                                print("SkipSlate: ✂️ CUT TOOL - Cutting segment at click position: \(clampedCutTime)s")
                                print("SkipSlate:   Segment bounds: \(segmentStart)s - \(segmentEnd)s, duration: \(segment.duration)s")
                                print("SkipSlate:   Click at: \(clickX)px (relative: \(relativeX)px)")
                                
                                // Only allow cutting clip segments
                                guard segment.kind == .clip else {
                                    print("SkipSlate: ⚠️ Cannot cut gap segment")
                                    return
                                }
                                
                                // First select the segment so user can see what's being cut
                                onSelect(false)
                                
                                // Then split the segment at the click position
                                projectViewModel.splitSegment(segment, at: clampedCutTime)
                                
                            case .trim:
                                // Trim tool - select segment for trimming (trim handles will appear)
                                print("SkipSlate: ✂️ TRIM TOOL - Selecting segment for trimming")
                                onSelect(false)
                            }
                        }
                )
                .simultaneousGesture(
                    // Drag gesture for moving segments - works with move tool and cursor tool
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            // Allow dragging with move tool or cursor tool
                            let tool = toolState.selectedTool
                            guard tool == .move || tool == .cursor else { return }
                            
                            // CRASH-PROOF: Only allow moving clip segments (not gaps)
                            guard segment.kind == .clip else { return }
                            
                            if !isDragging {
                                isDragging = true
                                dragStartLocation = value.startLocation
                                dragStartTime = compositionStart
                                dragVisualOffset = 0  // Reset visual offset
                                
                                // REMOVED: Don't pause player during drag
                                // Preview should be a pure mirror - only reflect composition changes
                                
                                // Select segment if not already selected
                                if !isSelected {
                                    onSelect(false)
                                }
                                
                                print("SkipSlate: 🎯 Started dragging segment \(segment.id) from position \(compositionStart)s")
                            }
                            
                            // Calculate new position based on drag distance using fixed pixels per second
                            let deltaX = value.translation.width
                            let deltaTime = Double(deltaX) / Double(pixelsPerSecond)
                            let rawTime = max(0, dragStartTime + deltaTime)
                            
                            // CRASH-PROOF: Validate new time is reasonable
                            guard rawTime >= 0 && rawTime.isFinite else {
                                print("SkipSlate: ⚠️ Invalid drag time: \(rawTime)")
                                return
                            }
                            
                            // SNAP TO GRID: Calculate snapped position for visual feedback
                            let snappedTime = projectViewModel.snapToGrid(rawTime)
                            
                            // VISUAL ONLY: Convert snapped time back to pixel offset for smooth visual feedback
                            let snappedDeltaTime = snappedTime - dragStartTime
                            let snappedDeltaX = CGFloat(snappedDeltaTime) * pixelsPerSecond
                            dragVisualOffset = snappedDeltaX
                        }
                        .onEnded { value in
                            guard isDragging else { return }
                            
                            // Calculate final position using fixed pixels per second
                            let deltaX = value.translation.width
                            let deltaY = value.translation.height
                            let deltaTime = Double(deltaX) / Double(pixelsPerSecond)
                            let rawFinalTime = max(0, dragStartTime + deltaTime)
                            
                            // SNAP TO GRID: Final position is always snapped to grid for solid, locked feel
                            let finalTime = projectViewModel.snapToGrid(rawFinalTime)
                            
                            // Reset visual offset immediately since we're committing to the model
                            dragVisualOffset = 0
                            
                            // CROSS-TRACK MOVEMENT: If Y offset is significant, check for track change
                            if let onCrossTrackMove = onCrossTrackMove, abs(deltaY) > trackHeight * 0.3 {
                                // Report the Y offset relative to this track's position for parent to determine target track
                                let absoluteY = trackYOffset + deltaY
                                onCrossTrackMove(segment.id, finalTime, absoluteY)
                                print("SkipSlate: ✅ Cross-track move: segment \(segment.id) to time \(finalTime)s, yOffset \(absoluteY)")
                            } else {
                                // Same track movement - use track.id which is the track this view represents
                                // The parent view (EnhancedTimelineView) now passes fresh track data
                                projectViewModel.moveSegmentToTrackAndTime(segment.id, to: finalTime, targetTrackID: track.id)
                                print("SkipSlate: ✅ Finished dragging segment \(segment.id) to position \(finalTime)s (snapped from \(rawFinalTime)s)")
                            }
                            
                            isDragging = false
                            dragLastUpdateTime = nil
                        }
                )
                .onHover { hovering in
                    // Update cursor based on selected tool when hovering over segment
                    if hovering {
                        let tool = toolState.selectedTool
                        tool.cursor.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            
            // Trim handles - show when segment is selected AND trim tool is active
            let showTrimHandles = isSelected && segment.enabled && width > 40 && toolState.selectedTool == .trim
            
            // Left trim handle
            if showTrimHandles {
                Rectangle()
                    .fill(hoveredEdge == .start ? AppColors.tealAccent : Color.white.opacity(0.5))
                    .frame(width: trimHandleWidth, height: trackHeight - 4)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredEdge = inside ? .start : nil
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else if hoveredEdge == .start {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isTrimming {
                                    isTrimming = true
                                    // REMOVED: Don't pause player during trim
                                    // Preview should be a pure mirror - only reflect composition changes
                                }
                                
                                // Calculate new start time using fixed pixels per second
                                let deltaTime = -(Double(value.translation.width) / Double(pixelsPerSecond))
                                
                                // Find adjacent segment to the left (in same track)
                                let segmentCompStart = compositionStart
                                var leftAdjacentSegment: Segment? = nil
                                var leftAdjacentEnd: Double = 0.0
                                
                                // Find segments in the same track
                                if let trackIndex = projectViewModel.tracks.firstIndex(where: { $0.segments.contains(segment.id) }) {
                                    let track = projectViewModel.tracks[trackIndex]
                                    let segmentDict = Dictionary(uniqueKeysWithValues: projectViewModel.segments.map { ($0.id, $0) })
                                    let trackSegments = track.segments.compactMap { segmentDict[$0] }
                                    
                                    // Find segment immediately before this one
                                    for otherSegment in trackSegments {
                                        let otherStart = projectViewModel.compositionStart(for: otherSegment)
                                        if otherStart < segmentCompStart && otherStart + otherSegment.duration <= segmentCompStart {
                                            if leftAdjacentSegment == nil || otherStart > leftAdjacentEnd {
                                                leftAdjacentSegment = otherSegment
                                                leftAdjacentEnd = otherStart + otherSegment.duration
                                            }
                                        }
                                    }
                                }
                                
                                // Calculate new source start
                                let proposedNewStart = segment.sourceStart + deltaTime
                                
                                // Clamp to valid range
                                if segment.kind == .clip,
                                   let sourceClipID = segment.sourceClipID,
                                   let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) {
                                    // Minimum: 0, Maximum: sourceEnd - 0.1 (minimum duration)
                                    var clampedStart = max(0, min(proposedNewStart, segment.sourceEnd - 0.1))
                                    
                                    // If there's an adjacent segment to the left, don't extend past it
                                    if let leftSeg = leftAdjacentSegment {
                                        let leftSegEnd = projectViewModel.compositionStart(for: leftSeg) + leftSeg.duration
                                        // Can't extend left edge past the end of the left segment
                                        // Calculate what sourceStart would be if compositionStart equals leftSegEnd
                                        let minCompositionStart = leftSegEnd
                                        let currentCompositionStart = segmentCompStart
                                        let compositionDelta = minCompositionStart - currentCompositionStart
                                        let minSourceStart = segment.sourceStart + compositionDelta
                                        clampedStart = max(clampedStart, minSourceStart)
                                    }
                                    
                                    onTrimStart(clampedStart)
                                }
                            }
                            .onEnded { _ in
                                isTrimming = false
                            }
                    )
            }
            
            // Right trim handle
            if showTrimHandles {
                Rectangle()
                    .fill(hoveredEdge == .end ? AppColors.tealAccent : Color.white.opacity(0.5))
                    .frame(width: trimHandleWidth, height: trackHeight - 4)
                    .offset(x: width - trimHandleWidth)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredEdge = inside ? .end : nil
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else if hoveredEdge == .end {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isTrimming {
                                    isTrimming = true
                                    // REMOVED: Don't pause player during trim
                                    // Preview should be a pure mirror - only reflect composition changes
                                }
                                
                                // Calculate new end time using fixed pixels per second
                                let deltaTime = Double(value.translation.width) / Double(pixelsPerSecond)
                                
                                // Find adjacent segment to the right (in same track)
                                let segmentCompStart = compositionStart
                                let segmentCompEnd = segmentCompStart + segment.duration
                                var rightAdjacentSegment: Segment? = nil
                                var rightAdjacentStart: Double = Double.infinity
                                
                                // Find segments in the same track
                                if let trackIndex = projectViewModel.tracks.firstIndex(where: { $0.segments.contains(segment.id) }) {
                                    let track = projectViewModel.tracks[trackIndex]
                                    let segmentDict = Dictionary(uniqueKeysWithValues: projectViewModel.segments.map { ($0.id, $0) })
                                    let trackSegments = track.segments.compactMap { segmentDict[$0] }
                                    
                                    // Find segment immediately after this one
                                    for otherSegment in trackSegments {
                                        let otherStart = projectViewModel.compositionStart(for: otherSegment)
                                        if otherStart >= segmentCompEnd {
                                            if otherStart < rightAdjacentStart {
                                                rightAdjacentSegment = otherSegment
                                                rightAdjacentStart = otherStart
                                            }
                                        }
                                    }
                                }
                                
                                // Calculate new source end
                                let proposedNewEnd = segment.sourceEnd + deltaTime
                                
                                // Clamp to valid range
                                if segment.kind == .clip,
                                   let sourceClipID = segment.sourceClipID,
                                   let clip = projectViewModel.clips.first(where: { $0.id == sourceClipID }) {
                                    // Minimum: sourceStart + 0.1 (minimum duration), Maximum: clip.duration
                                    var clampedEnd = max(segment.sourceStart + 0.1, min(proposedNewEnd, clip.duration))
                                    
                                    // If there's an adjacent segment to the right, don't extend past it
                                    if let rightSeg = rightAdjacentSegment {
                                        let rightSegStart = projectViewModel.compositionStart(for: rightSeg)
                                        // Can't extend right edge past the start of the right segment
                                        // Calculate what sourceEnd would be if compositionEnd equals rightSegStart
                                        let maxCompositionEnd = rightSegStart
                                        let currentCompositionEnd = segmentCompEnd
                                        let compositionDelta = maxCompositionEnd - currentCompositionEnd
                                        let maxSourceEnd = segment.sourceEnd + compositionDelta
                                        clampedEnd = min(clampedEnd, maxSourceEnd)
                                    }
                                    
                                    onTrimEnd(clampedEnd)
                                }
                            }
                            .onEnded { _ in
                                isTrimming = false
                            }
                    )
            }
        }
        .contextMenu {
            Button(segment.enabled ? "Disable" : "Enable") {
                projectViewModel.toggleSegmentEnabled(segment)
            }
            
            Button("Delete", role: .destructive) {
                // Ensure segment is selected before deleting
                projectViewModel.selectedSegmentIDs = [segment.id]
                projectViewModel.selectedSegment = segment
                projectViewModel.deleteSelectedSegments()
            }
            
            Divider()
            
            // Scale to Fill Frame
            if segment.kind == .clip {
                Button(segment.transform.scaleToFillFrame ? "Remove Scale to Fill Frame" : "Scale to Fill Frame") {
                    // Select segment first if not already selected
                    if !projectViewModel.selectedSegmentIDs.contains(segment.id) {
                        projectViewModel.selectedSegmentIDs = [segment.id]
                        projectViewModel.selectedSegment = segment
                    }
                    
                    if segment.transform.scaleToFillFrame {
                        projectViewModel.removeScaleToFillFrame()
                    } else {
                        projectViewModel.scaleSelectedSegmentsToFillFrame()
                    }
                }
            }
            
            Divider()
            
            Button("Go to Segment Start") {
                projectViewModel.seekToSegment(segment)
            }
            .disabled(!segment.enabled)
        }
        .onTapGesture(count: 2) {
            // Double-click to seek to segment start
            projectViewModel.seekToSegment(segment)
        }
    }
}
