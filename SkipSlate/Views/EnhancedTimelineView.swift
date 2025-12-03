//
//  EnhancedTimelineView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Timeline
//  - Primary timeline UI for segment editing
//  - Reads project data from ProjectViewModel
//  - Updates segments via ProjectViewModel methods (moveSegment, splitSegment, etc.)
//  - Does NOT know about media import UI or stock providers
//  - Communication: TimelineView → projectViewModel.moveSegment(...) → project updated → composition rebuild
//

import SwiftUI
import AVFoundation

struct EnhancedTimelineView: View {
    // Project data source
    @ObservedObject private var projectViewModel: ProjectViewModel
    // CRITICAL: Observe PlayerViewModel directly for preview observation rule
    @ObservedObject private var playerViewModel: PlayerViewModel
    @StateObject private var timelineViewModel = TimelineViewModel()
    // ISOLATED: Tool state is separate from project/player (Kdenlive pattern)
    // Changing tools NEVER triggers composition rebuilds
    @ObservedObject private var toolState = ToolState.shared
    @State private var draggingSegment: Segment?
    @State private var trimmingSegment: Segment?
    @State private var trimHandle: TrimHandle?
    @State private var dragOffset: CGFloat = 0
    
    init(projectViewModel: ProjectViewModel, selectedTool: EditingTool = .select) {
        self._projectViewModel = ObservedObject(wrappedValue: projectViewModel)
        // CRITICAL: Observe PlayerViewModel directly for Preview Observation Rule
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
        
        // NOTE: Don't force tool selection in init - let user's selection persist
        // The tool selection is managed by ProjectViewModel and should persist across view updates
        
        // Map EditingTool to EditorTool (for TimelineViewModel compatibility)
        _timelineViewModel = StateObject(wrappedValue: {
            let vm = TimelineViewModel()
            switch selectedTool {
            case .select: vm.currentTool = .segmentSelect
            case .cut: vm.currentTool = .blade
            case .trim: vm.currentTool = .trim
            }
            return vm
        }())
    }
    
    // Track height constants
    private let defaultTrackHeight: CGFloat = 60
    private let minTrackHeight: CGFloat = 40
    private let maxTrackHeight: CGFloat = 200
    private let baseTimelineWidth: CGFloat = 1000
    
    // TIMELINE "HOUSE" - Fixed ruler duration (5 hours) independent of content
    // The ruler is always this long - segments just live within it
    private let rulerDuration: Double = 18000.0  // 5 hours in seconds
    
    // Get height for a track (with default fallback)
    private func trackHeight(for trackID: UUID) -> CGFloat {
        return projectViewModel.trackHeights[trackID] ?? defaultTrackHeight
    }
    
    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            Divider()
            timeRulerSection
            Divider()
            timelineContent
        }
        .background(AppColors.background)
        .onAppear {
            setupKeyboardNavigation()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var timelineHeader: some View {
        HStack(spacing: 12) {
                Text("Tools")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                // Timeline tool buttons - ISOLATED from playback (Kdenlive pattern)
                // Tool changes NEVER affect composition or preview
                HStack(spacing: 4) {
                    ForEach(TimelineTool.allCases) { tool in
                        Button(action: {
                            // Use isolated ToolState - no connection to player/composition
                            toolState.selectTool(tool)
                        }) {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(toolState.selectedTool == tool ? AppColors.tealAccent : AppColors.secondaryText)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(toolState.selectedTool == tool ? AppColors.tealAccent.opacity(0.2) : Color.clear)
                        )
                        .help(tool.helpText)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.panelBackground.opacity(0.5))
                .cornerRadius(6)
                
                // Add/Remove track buttons
                HStack(spacing: 4) {
                    // Add buttons (teal)
                    AddTrackButton(trackKind: .video) {
                        projectViewModel.addTrack(kind: .video)
                    }
                    AddTrackButton(trackKind: .audio) {
                        projectViewModel.addTrack(kind: .audio)
                    }
                    
                    // Small separator
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 4)
                    
                    // Remove buttons (orange)
                    RemoveTrackButton(
                        trackKind: .video,
                        isEnabled: projectViewModel.videoTrackCount > 1
                    ) {
                        projectViewModel.removeTrack(kind: .video)
                    }
                    RemoveTrackButton(
                        trackKind: .audio,
                        isEnabled: projectViewModel.audioTrackCount > 1
                    ) {
                        projectViewModel.removeTrack(kind: .audio)
                    }
                }
                
                Spacer()
                
                // Zoom controls
                HStack(spacing: 8) {
                    ForEach(TimelineZoom.allCases, id: \.self) { zoom in
                        Button(zoom.label) {
                            timelineViewModel.zoomLevel = zoom
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(timelineViewModel.zoomLevel == zoom ? AppColors.tealAccent : .gray)
                    }
                }
                
                if !projectViewModel.segments.isEmpty {
                    Text("Total: \(timeString(from: totalDuration))")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppColors.panelBackground)
    }
    
    // Track header width - must match TrackHeaderView width for alignment
    private let trackHeaderWidth: CGFloat = 50  // Must match TrackHeaderView.headerWidth exactly
    
    @ViewBuilder
    private var timeRulerSection: some View {
        // Time ruler - THE "HOUSE" - Always exists, segments live within it
        HStack(spacing: 0) {
            // Empty spacer to align with track header
            Rectangle()
                .fill(Color.clear)
                .frame(width: trackHeaderWidth, height: 30)
            
            // Time ruler content - uses fixed rulerDuration for the "house"
            ScrollView(.horizontal, showsIndicators: false) {
                TimeRulerView(
                    playerViewModel: playerViewModel,
                    timelineViewModel: timelineViewModel,
                    rulerDuration: rulerDuration,  // Fixed ruler length (the "house")
                    contentDuration: totalDuration,  // Actual content for seeking limits
                    earliestStartTime: earliestSegmentStartTime,
                    onSeek: { time in
                        playerViewModel.seek(to: time, precise: true)
                    },
                    frameRate: 30.0
                )
            }
        }
        .frame(height: 30)
        .onAppear {
            timelineViewModel.baseTimelineWidth = 1000
        }
    }
    
    // Fixed pixels per second for timeline (must match TimeRulerView)
    private let basePixelsPerSecond: CGFloat = 80.0
    
    // Timeline width based on fixed ruler duration
    private var timelineWidth: CGFloat {
        CGFloat(rulerDuration) * basePixelsPerSecond * timelineViewModel.zoomLevel.scale
    }
    
    @ViewBuilder
    private var timelineContent: some View {
        // Multi-track timeline - THE "HOUSE" where segments live
        if projectViewModel.segments.isEmpty {
            VStack {
                Spacer()
                Text("No segments yet. Import media and run Auto Edit.")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.caption)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geometry in
                let availableHeight = geometry.size.height
                    
                    ZStack(alignment: .leading) {
                        // Global cursor update based on selected tool
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onHover { hovering in
                                if hovering {
                                    timelineViewModel.currentTool.cursor.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        
                        // Scrollable track content - uses fixed timelineWidth (the "house")
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                // Sort tracks: 
                                // - Video tracks: newest on TOP (reverse order - V3, V2, V1)
                                // - Audio tracks: newest on BOTTOM (normal order - A1, A2, A3)
                                let sortedTracks = projectViewModel.tracks.sorted { track1, track2 in
                                    if track1.kind != track2.kind {
                                        // Video tracks come before audio tracks
                                        return track1.kind == .video && track2.kind == .audio
                                    }
                                    // Video: higher index first (newest on top)
                                    // Audio: lower index first (newest on bottom)
                                    if track1.kind == .video {
                                        return track1.index > track2.index
                                    } else {
                                        return track1.index < track2.index
                                    }
                                }
                                
                                // Calculate cumulative Y offsets for cross-track movement
                                let trackHeights = sortedTracks.map { trackHeight(for: $0.id) }
                                
                                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                                    let currentTrackHeight = trackHeights[index]
                                    // Calculate Y offset: sum of all previous track heights + dividers
                                    let trackYOffset = trackHeights.prefix(index).reduce(0, +) + CGFloat(index) // +1px per divider
                                    
                                    TimelineTrackView(
                                        track: track,
                                        projectViewModel: projectViewModel,
                                        playerViewModel: playerViewModel,
                                        timelineViewModel: timelineViewModel,
                                        totalDuration: rulerDuration,  // Use fixed ruler duration
                                        zoomLevel: timelineViewModel.zoomLevel,
                                        trackHeight: currentTrackHeight,
                                        timelineWidth: timelineWidth,  // Use fixed timeline width
                                        allTracks: sortedTracks,
                                        trackYOffset: trackYOffset,
                                        onCrossTrackMove: { segmentID, newTime, absoluteY in
                                            // Determine target track based on Y position
                                            handleCrossTrackMove(
                                                segmentID: segmentID,
                                                newTime: newTime,
                                                absoluteY: absoluteY,
                                                sortedTracks: sortedTracks,
                                                trackHeights: trackHeights
                                            )
                                        }
                                    )
                                    .frame(height: currentTrackHeight)
                                    
                                    // Thin grid divider between tracks (1px instead of 4px)
                                    if index < sortedTracks.count - 1 {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(height: 1)
                                            .contentShape(Rectangle())
                                            .background(Color(white: 0.2))
                                            .onHover { hovering in
                                                if hovering {
                                                    NSCursor.resizeUpDown.push()
                                                } else {
                                                    NSCursor.pop()
                                        }
                                            }
                                            .gesture(
                                                DragGesture()
                                                    .onChanged { value in
                                                        let delta = value.translation.height
                                                        let newHeight = max(minTrackHeight, min(maxTrackHeight, currentTrackHeight + delta))
                                                        projectViewModel.trackHeights[track.id] = newHeight
                                                    }
                                            )
                                }
                            }
                            .frame(width: timelineWidth, alignment: .leading)  // Fixed timeline width
                        }
                        
                    }
                }
            }
        }
    }
    
    private var enabledSegments: [Segment] {
        projectViewModel.segments.filter { $0.enabled }
    }
    
    // Calculate total duration from all enabled segments across all tracks
    // Uses compositionStartTime + duration to find the maximum end time
    // ENDLESS TIMELINE: Always provide extra space beyond the last segment
    private var totalDuration: Double {
        let enabledSegments = projectViewModel.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else { return 60.0 } // Minimum 60 seconds even when empty
        
        // Find the maximum end time (compositionStartTime + duration)
        let maxEndTime = enabledSegments.map { $0.compositionStartTime + $0.duration }.max() ?? 0
        
        // ENDLESS TIMELINE: Add 30 seconds of extra space beyond the last segment
        // This allows users to drag segments to new positions beyond the current end
        let minDuration: Double = 60.0 // Minimum 60 seconds
        let extraSpace: Double = 30.0  // Extra space beyond last segment
        
        return max(minDuration, maxEndTime + extraSpace)
    }
    
    // Calculate earliest segment start time - timestamps should start where segments begin
    private var earliestSegmentStartTime: Double {
        let enabledSegments = projectViewModel.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else { return 0 }
        
        // Find the minimum compositionStartTime - this is where timestamps should start
        return enabledSegments.map { $0.compositionStartTime }.min() ?? 0
    }
    
    // MARK: - Cross-Track Movement Handler
    
    /// Handle cross-track segment movement
    /// Determines target track based on Y position and moves segment to that track
    private func handleCrossTrackMove(
        segmentID: Segment.ID,
        newTime: Double,
        absoluteY: CGFloat,
        sortedTracks: [TimelineTrack],
        trackHeights: [CGFloat]
    ) {
        // Find the track at the given Y position
        var cumulativeY: CGFloat = 0
        var targetTrack: TimelineTrack? = nil
        
        for (index, track) in sortedTracks.enumerated() {
            let trackBottom = cumulativeY + trackHeights[index]
            
            if absoluteY >= cumulativeY && absoluteY < trackBottom {
                targetTrack = track
                break
            }
            
            cumulativeY = trackBottom + 1 // +1 for divider
        }
        
        // If Y is beyond the last track, use the last track
        if targetTrack == nil && !sortedTracks.isEmpty {
            if absoluteY < 0 {
                targetTrack = sortedTracks.first // Top track
            } else {
                targetTrack = sortedTracks.last // Bottom track
            }
        }
        
        // Get the segment's current track to check compatibility
        guard let segment = projectViewModel.segments.first(where: { $0.id == segmentID }),
              let currentTrack = projectViewModel.trackForSegment(segmentID),
              let targetTrack = targetTrack else {
            // Fallback to same-track move if we can't determine target
            projectViewModel.moveSegment(segmentID, to: newTime)
            return
        }
        
        // Only allow moving to tracks of the same kind (video to video, audio to audio)
        if currentTrack.kind == targetTrack.kind && currentTrack.id != targetTrack.id {
            // Cross-track move to different track of same type
            projectViewModel.moveSegmentToTrackAndTime(segmentID, to: newTime, targetTrackID: targetTrack.id)
            print("SkipSlate: ✅ Moved segment to track \(targetTrack.id) at time \(newTime)")
        } else if currentTrack.id == targetTrack.id {
            // Same track - just update time
            projectViewModel.moveSegment(segmentID, to: newTime)
        } else {
            // Different track types - just update time on current track
            print("SkipSlate: ⚠️ Cannot move \(currentTrack.kind) segment to \(targetTrack.kind) track")
            projectViewModel.moveSegment(segmentID, to: newTime)
        }
    }
    
    private func isSegmentPlaying(_ segment: Segment) -> Bool {
        let currentTime = playerViewModel.currentTime
        
        // Calculate composition start for this segment
        var compositionStart: Double = 0.0
        for seg in projectViewModel.segments {
            if seg.id == segment.id {
                break
            }
            if seg.enabled {
                compositionStart += seg.duration
            }
        }
        
        return currentTime >= compositionStart && currentTime < compositionStart + segment.duration
    }
    
    private func trimSegment(_ segment: Segment, start: Double?, end: Double?) {
        guard let index = projectViewModel.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        
        var updatedSegment = projectViewModel.segments[index]
        
        if let newStart = start {
            // Ensure minimum duration
            let minEnd = newStart + 0.2
            if updatedSegment.sourceEnd < minEnd {
                updatedSegment.sourceEnd = minEnd
            }
            updatedSegment.sourceStart = newStart
        }
        
        if let newEnd = end {
            // Ensure minimum duration
            let minStart = newEnd - 0.2
            if updatedSegment.sourceStart > minStart {
                updatedSegment.sourceStart = minStart
            }
            updatedSegment.sourceEnd = newEnd
        }
        
        // Ensure we don't go beyond source clip bounds
        if let clip = projectViewModel.clips.first(where: { $0.id == segment.sourceClipID }) {
            updatedSegment.sourceStart = max(0, min(updatedSegment.sourceStart, clip.duration - 0.2))
            updatedSegment.sourceEnd = max(updatedSegment.sourceStart + 0.2, min(updatedSegment.sourceEnd, clip.duration))
        }
        
        projectViewModel.segments[index] = updatedSegment
        projectViewModel.updateSegmentTiming(updatedSegment, start: updatedSegment.sourceStart, end: updatedSegment.sourceEnd)
    }
    
    private func setupKeyboardNavigation() {
        // Keyboard navigation handled via keyDown in NSView
        // Arrow keys will be handled in the parent view
    }
    
    private func handleSegmentDrag(segment: Segment, offset: CGFloat) {
        // This is called during drag for visual feedback
        // Actual reordering is handled by onDrop delegate
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

enum TrimHandle {
    case start
    case end
}

// TimelineZoom and SegmentDropDelegate are defined in TimelineView.swift

struct EnhancedSegmentBlock: View {
    let segment: Segment
    let index: Int
    let compositionStart: Double
    let isSelected: Bool
    let isPlaying: Bool
    let totalDuration: Double
    let zoomLevel: TimelineZoom
    @ObservedObject var projectViewModel: ProjectViewModel
    // CRITICAL: Observe PlayerViewModel directly for preview observation rule
    @ObservedObject var playerViewModel: PlayerViewModel
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTrimStart: (Double) -> Void
    let onTrimEnd: (Double) -> Void
    let onDrag: (CGFloat) -> Void
    let onMove: (Int, Int) -> Void
    var selectedTool: EditingTool = .select // Pass tool from parent
    
    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isTrimming = false
    @State private var trimHandle: TrimHandle?
    @State private var dragStartX: CGFloat = 0
    
    private var segmentColor: Color {
        if !segment.enabled {
            return Color.gray.opacity(0.3)
        }
        
        // Get quality score for this segment
        if let qualityScore = projectViewModel.qualityScore(for: segment) {
            // Color-code by quality: green (high), yellow (medium), red (low)
            if qualityScore >= 0.7 {
                return Color.green.opacity(0.7)
            } else if qualityScore >= 0.5 {
                return Color.yellow.opacity(0.7)
            } else {
                return Color.red.opacity(0.7)
            }
        }
        
        // Fallback to original color palette if no quality score
        return ColorPalette.color(for: segment.colorIndex)
    }
    
    private var width: CGFloat {
        let baseWidth: CGFloat = 1000 // Base timeline width
        let ratio = segment.duration / max(totalDuration, 1.0)
        // Note: zoomLevel is passed from parent, not from timelineViewModel
        let scaledWidth = ratio * baseWidth * zoomLevel.scale
        return max(scaledWidth, 60) // Minimum 60 points for trim handles
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
                    // Main segment block
                    Button(action: onSelect) {
                        VStack(spacing: 0) {
                            // Segment block
                            ZStack {
                                Rectangle()
                                    .fill(segmentColor)
                                    .frame(width: width, height: 60)
                        
                        // Selected/Playing indicator
                        if isSelected || isPlaying {
                            Rectangle()
                                .stroke(
                                    isPlaying ? AppColors.tealAccent : Color.white,
                                    lineWidth: isPlaying ? 3 : 2
                                )
                                .frame(width: width, height: 60)
                        }
                        
                        // Disabled pattern
                        if !segment.enabled {
                            Rectangle()
                                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .frame(width: width, height: 60)
                        }
                        
                        // Content overlay
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Start time
                                Text(timeString(from: compositionStart))
                                    .font(.caption2)
                                    .foregroundColor(AppColors.primaryText)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                // Duration
                                Text(timeString(from: segment.duration))
                                    .font(.caption2)
                                    .foregroundColor(AppColors.primaryText)
                                    .padding(4)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            // Disabled indicator
                            if !segment.enabled {
                                HStack {
                                    Spacer()
                                    Image(systemName: "eye.slash")
                                        .foregroundColor(AppColors.primaryText)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                        .padding(4)
                    }
                    
                    // Clip name and time range label
                    VStack(alignment: .leading, spacing: 2) {
                        // Show clip name if available
                        if let clip = projectViewModel.clips.first(where: { $0.id == segment.sourceClipID }) {
                            Text(clip.fileName)
                                .font(.caption2)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        // Time range in source clip
                        Text("\(timeString(from: segment.sourceStart)) - \(timeString(from: segment.sourceEnd))")
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(width: width, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
                            // Drag gesture for reordering - only when Select tool is active
                            // Note: This uses selectedTool from parent, not timelineViewModel
                            .simultaneousGesture(
                                selectedTool == .select ? 
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            if !isDragging {
                                                isDragging = true
                                                dragStartX = value.startLocation.x
                                                // REMOVED: Don't pause player during drag
                                                // Preview should be a pure mirror - only reflect composition changes
                                            }
                                            onDrag(value.translation.width)
                                        }
                                        .onEnded { _ in
                                            isDragging = false
                                            // Reordering is handled by onDrop delegate
                                        } : nil
                            )
            
            // Trim handles (only when selected and enabled)
            if isSelected && segment.enabled && width > 60 {
                // Left trim handle
                Rectangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 8, height: 60)
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isTrimming {
                                    isTrimming = true
                                    trimHandle = .start
                                    // REMOVED: Don't pause player during trim
                                    // Preview should be a pure mirror - only reflect composition changes
                                }
                                
                                // Calculate new start time based on drag
                                let dragSeconds = value.translation.width / (width / segment.duration)
                                let newStart = max(0, segment.sourceStart + dragSeconds)
                                
                                // Update temporarily (visual feedback only)
                                // Actual update happens on end
                            }
                            .onEnded { value in
                                let dragSeconds = value.translation.width / (width / segment.duration)
                                let newStart = max(0, segment.sourceStart + dragSeconds)
                                onTrimStart(newStart)
                                isTrimming = false
                                trimHandle = nil
                            }
                    )
                
                // Right trim handle
                Rectangle()
                    .fill(AppColors.tealAccent)
                    .frame(width: 8, height: 60)
                    .offset(x: width - 8)
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isTrimming {
                                    isTrimming = true
                                    trimHandle = .end
                                    // REMOVED: Don't pause player during trim
                                    // Preview should be a pure mirror - only reflect composition changes
                                }
                                
                                // Calculate new end time based on drag
                                let dragSeconds = value.translation.width / (width / segment.duration)
                                let newEnd = segment.sourceEnd + dragSeconds
                                
                                // Update temporarily (visual feedback only)
                            }
                            .onEnded { value in
                                let dragSeconds = value.translation.width / (width / segment.duration)
                                let newEnd = segment.sourceEnd + dragSeconds
                                onTrimEnd(newEnd)
                                isTrimming = false
                                trimHandle = nil
                            }
                    )
            }
        }
        .contextMenu {
            Button(segment.enabled ? "Disable" : "Enable") {
                onToggle()
            }
            
            Button("Delete", role: .destructive) {
                onDelete()
            }
            
            Divider()
            
                            Button("Split at Playhead") {
                                // CRITICAL: Use directly observed playerViewModel
                                projectViewModel.splitSegment(segment, at: playerViewModel.currentTime)
                            }
                            .disabled(!isSelected || !segment.enabled)
        }
    }
    
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}


