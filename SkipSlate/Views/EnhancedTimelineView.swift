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
        .focusable()
        .onKeyPress { keyPress in
            return handleKeyPress(keyPress)
        }
        .onAppear {
            setupKeyboardNavigation()
        }
    }
    
    /// Handle keyboard shortcuts for timeline operations
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let key = keyPress.key
        let modifiers = keyPress.modifiers
        
        // MARK: - Playback Controls (no modifiers)
        if modifiers.isEmpty {
            switch key {
            case .space: // Space - Play/Pause
                playerViewModel.togglePlayPause()
                return .handled
                
            case KeyEquivalent("j"): // J - Reverse/slower
                handleJKey()
                return .handled
                
            case KeyEquivalent("k"): // K - Pause
                playerViewModel.pause()
                return .handled
                
            case KeyEquivalent("l"): // L - Forward/faster
                handleLKey()
                return .handled
                
            case KeyEquivalent("v"): // V - Selection tool
                toolState.selectTool(.cursor)
                return .handled
                
            case KeyEquivalent("c"), KeyEquivalent("b"): // C or B - Cut tool
                toolState.selectTool(.cut)
                return .handled
                
            case KeyEquivalent("t"): // T - Trim tool
                toolState.selectTool(.trim)
                return .handled
                
            case KeyEquivalent("m"): // M - Move tool
                toolState.selectTool(.move)
                return .handled
                
            case .leftArrow: // Left arrow - Previous frame
                let frameTime = 1.0 / 30.0
                let newTime = max(0, playerViewModel.currentTime - frameTime)
                playerViewModel.seek(to: newTime, precise: true)
                return .handled
                
            case .rightArrow: // Right arrow - Next frame
                let frameTime = 1.0 / 30.0
                let newTime = min(playerViewModel.duration, playerViewModel.currentTime + frameTime)
                playerViewModel.seek(to: newTime, precise: true)
                return .handled
                
            case .downArrow: // Down arrow - Next segment
                selectNextSegment()
                return .handled
                
            case .upArrow: // Up arrow - Previous segment
                selectPreviousSegment()
                return .handled
                
            case .delete: // Delete - Delete selected segment
                if let selectedSegment = projectViewModel.selectedSegment {
                    projectViewModel.deleteSegment(selectedSegment)
                }
                return .handled
                
            default:
                break
            }
        }
        
        // MARK: - Command shortcuts
        if modifiers == .command {
            switch key {
            case KeyEquivalent("z"): // Cmd+Z - Undo
                projectViewModel.undo()
                return .handled
                
            case KeyEquivalent("a"): // Cmd+A - Select all
                projectViewModel.selectAllSegments()
                return .handled
                
            case KeyEquivalent("c"): // Cmd+C - Copy selected segments
                projectViewModel.copySelectedSegments()
                return .handled
                
            case KeyEquivalent("v"): // Cmd+V - Paste segments at playhead
                projectViewModel.pasteSegments(at: playerViewModel.currentTime)
                return .handled
                
            case KeyEquivalent("d"): // Cmd+D - Duplicate selected segments
                projectViewModel.duplicateSelectedSegments()
                return .handled
                
            default:
                break
            }
        }
        
        // MARK: - Shift+Command shortcuts
        if modifiers == [.command, .shift] {
            switch key {
            case KeyEquivalent("z"): // Cmd+Shift+Z - Redo
                projectViewModel.redo()
                return .handled
                
            default:
                break
            }
        }
        
        // MARK: - Shift shortcuts (larger seek steps)
        if modifiers == .shift {
            switch key {
            case .leftArrow: // Shift+Left - Seek back 1 second
                let newTime = max(0, playerViewModel.currentTime - 1.0)
                playerViewModel.seek(to: newTime, precise: true)
                return .handled
                
            case .rightArrow: // Shift+Right - Seek forward 1 second
                let newTime = min(playerViewModel.duration, playerViewModel.currentTime + 1.0)
                playerViewModel.seek(to: newTime, precise: true)
                return .handled
                
            default:
                break
            }
        }
        
        // MARK: - Control+Command shortcuts
        if modifiers == [.command, .control] {
            switch key {
            case KeyEquivalent("s"): // Cmd+Ctrl+S - Split at playhead
                splitAtPlayhead()
                return .handled
                
            default:
                break
            }
        }
        
        return .ignored
    }
    
    private func handleJKey() {
        let currentRate = playerViewModel.playbackRate
        if currentRate > 0 {
            playerViewModel.setPlaybackRate(-1.0)
        } else if currentRate == -1.0 {
            playerViewModel.setPlaybackRate(-2.0)
        } else if currentRate == -2.0 {
            playerViewModel.setPlaybackRate(-4.0)
        } else {
            playerViewModel.setPlaybackRate(-1.0)
        }
    }
    
    private func handleLKey() {
        let currentRate = playerViewModel.playbackRate
        if currentRate < 0 || currentRate == 0 {
            playerViewModel.setPlaybackRate(1.0)
        } else if currentRate == 1.0 {
            playerViewModel.setPlaybackRate(2.0)
        } else if currentRate == 2.0 {
            playerViewModel.setPlaybackRate(4.0)
        } else {
            playerViewModel.setPlaybackRate(1.0)
        }
    }
    
    private func selectNextSegment() {
        let sortedSegments = projectViewModel.segments.filter { $0.kind == .clip }.sorted { $0.compositionStartTime < $1.compositionStartTime }
        guard !sortedSegments.isEmpty else { return }
        
        if let current = projectViewModel.selectedSegment,
           let currentIndex = sortedSegments.firstIndex(where: { $0.id == current.id }),
           currentIndex < sortedSegments.count - 1 {
            let nextSegment = sortedSegments[currentIndex + 1]
            projectViewModel.selectedSegment = nextSegment
            projectViewModel.selectedSegmentIDs = [nextSegment.id]
            playerViewModel.seek(to: nextSegment.compositionStartTime, precise: true)
        } else if let first = sortedSegments.first {
            projectViewModel.selectedSegment = first
            projectViewModel.selectedSegmentIDs = [first.id]
            playerViewModel.seek(to: first.compositionStartTime, precise: true)
        }
    }
    
    private func selectPreviousSegment() {
        let sortedSegments = projectViewModel.segments.filter { $0.kind == .clip }.sorted { $0.compositionStartTime < $1.compositionStartTime }
        guard !sortedSegments.isEmpty else { return }
        
        if let current = projectViewModel.selectedSegment,
           let currentIndex = sortedSegments.firstIndex(where: { $0.id == current.id }),
           currentIndex > 0 {
            let prevSegment = sortedSegments[currentIndex - 1]
            projectViewModel.selectedSegment = prevSegment
            projectViewModel.selectedSegmentIDs = [prevSegment.id]
            playerViewModel.seek(to: prevSegment.compositionStartTime, precise: true)
        } else if let last = sortedSegments.last {
            projectViewModel.selectedSegment = last
            projectViewModel.selectedSegmentIDs = [last.id]
            playerViewModel.seek(to: last.compositionStartTime, precise: true)
        }
    }
    
    private func splitAtPlayhead() {
        let playheadTime = playerViewModel.currentTime
        
        for segment in projectViewModel.segments where segment.kind == .clip {
            let segStart = segment.compositionStartTime
            let segEnd = segStart + segment.duration
            
            if playheadTime > segStart + 0.1 && playheadTime < segEnd - 0.1 {
                projectViewModel.splitSegment(segment, at: playheadTime)
                return
            }
        }
        
        print("SkipSlate: ⚠️ No segment found at playhead position for split")
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
                
                // Playback controls - moved from top bar to timeline
                TimelinePlaybackControls(playerViewModel: playerViewModel)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppColors.panelBackground)
    }
    
    // Track header width - must match TrackHeaderView width for alignment
    private let trackHeaderWidth: CGFloat = 50  // Must match TrackHeaderView.headerWidth exactly
    
    // NOTE: timeRulerSection is no longer used - ruler is now inside timelineContent
    // for synchronized scrolling
    @ViewBuilder
    private var timeRulerSection: some View {
        // Empty placeholder - ruler is now part of the main scrollable content
        EmptyView()
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
                let rulerHeight: CGFloat = 30
                let sortedTracks = getSortedTracks()
                let trackHeightsList = sortedTracks.map { trackHeight(for: $0.id) }
                
                VStack(spacing: 0) {
                    // ROW 1: Gray corner + Ruler (both 30px height)
                    HStack(spacing: 0) {
                        // Gray corner (matches track header width)
                        Rectangle()
                            .fill(AppColors.panelBackground)
                            .frame(width: trackHeaderWidth, height: rulerHeight)
                        
                        // Time ruler - scrolls horizontally
                        ScrollView(.horizontal, showsIndicators: false) {
                            TimeRulerView(
                                playerViewModel: playerViewModel,
                                timelineViewModel: timelineViewModel,
                                rulerDuration: rulerDuration,
                                contentDuration: totalDuration,
                                earliestStartTime: earliestSegmentStartTime,
                                onSeek: { time in
                                    playerViewModel.seek(to: time, precise: true)
                                },
                                frameRate: 30.0
                            )
                            .frame(height: rulerHeight)
                        }
                    }
                    .frame(height: rulerHeight)
                    
                    // ROW 2: Track headers + Track content (both aligned to top)
                    HStack(alignment: .top, spacing: 0) {
                        // FIXED: Track headers column
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                                TrackHeaderView(
                                    track: track,
                                    isActive: track.index == 0,
                                    height: trackHeightsList[index]
                                )
                                .frame(height: trackHeightsList[index])
                                
                                // Divider between tracks
                                if index < sortedTracks.count - 1 {
                                    Rectangle()
                                        .fill(Color(white: 0.3))
                                        .frame(height: 1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: trackHeaderWidth)
                        .background(AppColors.panelBackground)
                        
                        // SCROLLABLE: Track content (scrollbar hidden to blend with dark background)
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                // CRITICAL FIX: Use composite ID that includes segment list hash
                                // This forces SwiftUI to recreate the view when segments move between tracks
                                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                                    let currentTrackHeight = trackHeightsList[index]
                                    let trackYOffset = trackHeightsList.prefix(index).reduce(0, +) + CGFloat(index)
                                    // Get fresh track data to ensure view has latest segments
                                    let freshTrack = projectViewModel.project.tracks.first { $0.id == track.id } ?? track
                                    
                                    TimelineTrackView(
                                        track: freshTrack,  // Use fresh track data, not stale snapshot
                                        projectViewModel: projectViewModel,
                                        playerViewModel: playerViewModel,
                                        timelineViewModel: timelineViewModel,
                                        totalDuration: rulerDuration,
                                        zoomLevel: timelineViewModel.zoomLevel,
                                        trackHeight: currentTrackHeight,
                                        timelineWidth: timelineWidth,
                                        allTracks: sortedTracks,
                                        trackYOffset: trackYOffset,
                                        onCrossTrackMove: { segmentID, newTime, absoluteY in
                                            handleCrossTrackMove(
                                                segmentID: segmentID,
                                                newTime: newTime,
                                                absoluteY: absoluteY,
                                                sortedTracks: sortedTracks,
                                                trackHeights: trackHeightsList
                                            )
                                        }
                                    )
                                    .id("\(track.id)-\(freshTrack.segments.hashValue)")  // Force view recreation when segments change
                                    .frame(height: currentTrackHeight)
                                    
                                    // Divider between tracks (matches header column)
                                    if index < sortedTracks.count - 1 {
                                        Rectangle()
                                            .fill(Color(white: 0.3))
                                            .frame(height: 1)
                                    }
                                }
                            }
                            .frame(width: timelineWidth, alignment: .topLeading)
                        }
                    }
                }
                .onAppear {
                    timelineViewModel.baseTimelineWidth = 1000
                }
            }
        }
    }
    
    // Helper to get sorted tracks (video on top, audio on bottom)
    private func getSortedTracks() -> [TimelineTrack] {
        projectViewModel.tracks.sorted { track1, track2 in
            if track1.kind != track2.kind {
                return track1.kind == .video && track2.kind == .audio
            }
            if track1.kind == .video {
                return track1.index > track2.index
            } else {
                return track1.index < track2.index
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
    /// SIMPLE: Find target track based on Y, move segment there
    private func handleCrossTrackMove(
        segmentID: Segment.ID,
        newTime: Double,
        absoluteY: CGFloat,
        sortedTracks: [TimelineTrack],
        trackHeights: [CGFloat]
    ) {
        // Find target track at Y position
        var cumulativeY: CGFloat = 0
        var targetTrack: TimelineTrack? = nil
        
        for (index, track) in sortedTracks.enumerated() {
            let trackBottom = cumulativeY + trackHeights[index]
            if absoluteY >= cumulativeY && absoluteY < trackBottom {
                targetTrack = track
                break
            }
            cumulativeY = trackBottom + 1
        }
        
        // Clamp to first/last track if beyond bounds
        if targetTrack == nil && !sortedTracks.isEmpty {
            targetTrack = absoluteY < 0 ? sortedTracks.first : sortedTracks.last
        }
        
        guard let targetTrack = targetTrack else { return }
        
        // Move segment to target track at new time
        // moveSegmentToTrackAndTime handles all the logic (same track, different track, etc.)
        projectViewModel.moveSegmentToTrackAndTime(segmentID, to: newTime, targetTrackID: targetTrack.id)
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

// MARK: - Timeline Playback Controls
// Playback controls displayed in the timeline header
struct TimelinePlaybackControls: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Timecode display
            Text(timecodeString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppColors.tealAccent)
                .frame(width: 100)
            
            // Skip to start
            Button(action: {
                playerViewModel.seek(to: 0)
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.primaryText)
            
            // Play/Pause
            Button(action: {
                if playerViewModel.isPlaying {
                    playerViewModel.pause()
                } else {
                    playerViewModel.play()
                }
            }) {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.tealAccent)
            
            // Skip to end
            Button(action: {
                playerViewModel.seek(to: playerViewModel.duration)
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.primaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColors.panelBackground.opacity(0.8))
        .cornerRadius(8)
    }
    
    private var timecodeString: String {
        let time = playerViewModel.currentTime
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}

