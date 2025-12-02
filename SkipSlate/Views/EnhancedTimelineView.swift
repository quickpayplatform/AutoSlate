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
    @ObservedObject var projectViewModel: ProjectViewModel
    // CRITICAL: Observe PlayerViewModel directly for preview observation rule
    @ObservedObject private var playerViewModel: PlayerViewModel
    @StateObject private var timelineViewModel = TimelineViewModel()
    @State private var draggingSegment: Segment?
    @State private var trimmingSegment: Segment?
    @State private var trimHandle: TrimHandle?
    @State private var dragOffset: CGFloat = 0
    
    init(projectViewModel: ProjectViewModel, selectedTool: EditingTool = .select) {
        self.projectViewModel = projectViewModel
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
        // Map EditingTool to EditorTool
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
    
    // Get height for a track (with default fallback)
    private func trackHeight(for trackID: UUID) -> CGFloat {
        return projectViewModel.trackHeights[trackID] ?? defaultTrackHeight
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline header with tools, zoom controls, and add track buttons
            HStack(spacing: 12) {
                Text("Timeline")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                // Editor tool buttons (Select, Blade, Trim)
                HStack(spacing: 4) {
                    ForEach(EditorTool.allCases) { tool in
                        Button(action: {
                            timelineViewModel.currentTool = tool
                            tool.cursor.push()
                        }) {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(timelineViewModel.currentTool == tool ? AppColors.tealAccent : AppColors.secondaryText)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(timelineViewModel.currentTool == tool ? AppColors.tealAccent.opacity(0.2) : Color.clear)
                        )
                        .help(tool.helpText)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.panelBackground.opacity(0.5))
                .cornerRadius(6)
                
                // Add track buttons
                HStack(spacing: 4) {
                    AddTrackButton(trackKind: .video) {
                        projectViewModel.addTrack(kind: .video)
                    }
                    AddTrackButton(trackKind: .audio) {
                        projectViewModel.addTrack(kind: .audio)
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
            
            Divider()
            
            // Time ruler (only show if we have segments)
            if !projectViewModel.segments.isEmpty && totalDuration > 0 {
                GeometryReader { geometry in
                    let baseTimelineWidth: CGFloat = 1000
                    ScrollView(.horizontal, showsIndicators: false) {
                        TimeRulerView(
                            playerViewModel: playerViewModel,
                            totalDuration: totalDuration,
                            zoomLevel: timelineViewModel.zoomLevel,
                            baseTimelineWidth: baseTimelineWidth,
                            onSeek: { time in
                                playerViewModel.seek(to: time, precise: true)
                            },
                            frameRate: 30.0  // TODO: Get from project settings
                        )
                        .frame(width: baseTimelineWidth * timelineViewModel.zoomLevel.scale)
                    }
                }
                .frame(height: 30)
                
                Divider()
            }
            
            // Multi-track timeline
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
                    let contentWidth = baseTimelineWidth * timelineViewModel.zoomLevel.scale
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
                        
                        // Scrollable track content
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                ForEach(Array(projectViewModel.tracks.enumerated()), id: \.element.id) { index, track in
                                    let currentTrackHeight = trackHeight(for: track.id)
                                    
                                    TimelineTrackView(
                                        track: track,
                                        projectViewModel: projectViewModel,
                                        playerViewModel: playerViewModel,
                                        totalDuration: totalDuration,
                                        zoomLevel: timelineViewModel.zoomLevel,
                                        trackHeight: currentTrackHeight,
                                        timelineWidth: contentWidth
                                    )
                                    .frame(height: currentTrackHeight)
                                    
                                    // Resizable divider between tracks
                                    if index < projectViewModel.tracks.count - 1 {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(height: 4)
                                            .contentShape(Rectangle())
                                            .background(Color(white: 0.3))
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
                            }
                            .frame(width: contentWidth, alignment: .leading)
                        }
                        
                        // Playhead indicator (spans all tracks)
                        if totalDuration > 0 {
                            // Convert EditorTool to TimelineTool for PlayheadIndicator
                            let timelineTool: TimelineTool = {
                                switch timelineViewModel.currentTool {
                                case .segmentSelect: return .cursor
                                case .blade: return .cut
                                case .trim: return .trim
                                }
                            }()
                            
                            PlayheadIndicator(
                                playerVM: playerViewModel,
                                totalDuration: totalDuration,
                                timelineWidth: contentWidth,
                                zoomLevel: timelineViewModel.zoomLevel,
                                trackHeight: availableHeight,
                                selectedTool: timelineTool
                            )
                        }
                    }
                }
            }
        }
        .background(AppColors.background)
        .onAppear {
            setupKeyboardNavigation()
        }
    }
    
    private var enabledSegments: [Segment] {
        projectViewModel.segments.filter { $0.enabled }
    }
    
    // Calculate total duration from all enabled segments across all tracks
    // Uses compositionStartTime + duration to find the maximum end time
    private var totalDuration: Double {
        let enabledSegments = projectViewModel.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else { return 0 }
        
        // Find the maximum end time (compositionStartTime + duration)
        let maxEndTime = enabledSegments.map { $0.compositionStartTime + $0.duration }.max() ?? 0
        return maxEndTime
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
                                                // CRITICAL: Use directly observed playerViewModel
                                                if playerViewModel.isPlaying {
                                                    playerViewModel.pause()
                                                }
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
                                    // CRITICAL: Use directly observed playerViewModel
                                    if playerViewModel.isPlaying {
                                        playerViewModel.pause()
                                    }
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
                                    // CRITICAL: Use directly observed playerViewModel
                                    if playerViewModel.isPlaying {
                                        playerViewModel.pause()
                                    }
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


