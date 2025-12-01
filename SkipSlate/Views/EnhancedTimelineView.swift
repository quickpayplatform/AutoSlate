//
//  EnhancedTimelineView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI
import AVFoundation

struct EnhancedTimelineView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var zoomLevel: TimelineZoom = .fit
    @State private var draggingSegment: Segment?
    @State private var trimmingSegment: Segment?
    @State private var trimHandle: TrimHandle?
    @State private var dragOffset: CGFloat = 0
    var selectedTool: EditingTool = .select // Tool selection from parent (for cursor changes)
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline header with zoom controls
            HStack {
                Text("Timeline")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                // Zoom controls
                HStack(spacing: 8) {
                    ForEach(TimelineZoom.allCases, id: \.self) { zoom in
                        Button(zoom.label) {
                            zoomLevel = zoom
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(zoomLevel == zoom ? AppColors.tealAccent : .gray)
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
            
            // Segment blocks
            if projectViewModel.segments.isEmpty {
                VStack {
                    Spacer()
                    Text("No segments yet. Go back to Auto Edit or add clips.")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if enabledSegments.isEmpty {
                VStack {
                    Spacer()
                    Text("All segments are disabled; nothing to play.")
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                GeometryReader { geometry in
                    let baseTimelineWidth: CGFloat = 1000
                    let contentWidth = baseTimelineWidth * zoomLevel.scale
                    
                    ZStack(alignment: .leading) {
                        
                        // Segment blocks with drag-and-drop reordering
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 2) {
                                ForEach(Array(projectViewModel.segments.enumerated()), id: \.element.id) { index, segment in
                                    EnhancedSegmentBlock(
                                        segment: segment,
                                        index: index,
                                        compositionStart: projectViewModel.compositionStart(for: segment),
                                        isSelected: projectViewModel.selectedSegment?.id == segment.id,
                                        isPlaying: isSegmentPlaying(segment),
                                        totalDuration: totalDuration,
                                        zoomLevel: zoomLevel,
                                        projectViewModel: projectViewModel,
                                        onSelect: {
                                            projectViewModel.selectedSegment = segment
                                            projectViewModel.seekToSegment(segment)
                                        },
                                        onToggle: {
                                            projectViewModel.toggleSegmentEnabled(segment)
                                        },
                                        onDelete: {
                                            projectViewModel.deleteSegment(segment)
                                        },
                                        onTrimStart: { newStart in
                                            trimSegment(segment, start: newStart, end: nil)
                                        },
                                        onTrimEnd: { newEnd in
                                            trimSegment(segment, start: nil, end: newEnd)
                                        },
                                        onDrag: { offset in
                                            // Handle drag for reordering
                                            handleSegmentDrag(segment: segment, offset: offset)
                                        },
                                        onMove: { from, to in
                                            // Handle move for reordering
                                            projectViewModel.reorderSegments(from: IndexSet(integer: from), to: to)
                                        },
                                        selectedTool: selectedTool
                                    )
                                    .onDrag {
                                        // Create drag item for reordering - only when Select tool is active
                                        guard selectedTool == .select else {
                                            return NSItemProvider()
                                        }
                                        let itemProvider = NSItemProvider()
                                        itemProvider.registerDataRepresentation(forTypeIdentifier: "public.text", visibility: .all) { completion in
                                            let data = segment.id.uuidString.data(using: .utf8) ?? Data()
                                            completion(data, nil)
                                            return nil
                                        }
                                        return itemProvider
                                    }
                                    .onDrop(of: [.text], delegate: SegmentDropDelegate(
                                        segment: segment,
                                        segments: projectViewModel.segments,
                                        onMove: { from, to in
                                            // Only allow reordering when Select tool is active
                                            guard selectedTool == .select else { return }
                                            projectViewModel.reorderSegments(from: IndexSet(integer: from), to: to)
                                        }
                                    ))
                                }
                            }
                            .padding(.horizontal)
                            .frame(width: contentWidth, alignment: .leading)
                        }
                        
                        // Playhead indicator overlay - positioned relative to scrollable content
                        // Observe playerVM directly for real-time updates
                        if totalDuration > 0 {
                            PlayheadIndicator(
                                playerVM: projectViewModel.playerVM,
                                totalDuration: totalDuration,
                                timelineWidth: contentWidth,
                                zoomLevel: zoomLevel
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
    
    private var totalDuration: Double {
        enabledSegments.reduce(0) { $0 + $1.duration }
    }
    
    private func isSegmentPlaying(_ segment: Segment) -> Bool {
        guard let playerVM = projectViewModel.playerVM as? PlayerViewModel else { return false }
        let currentTime = playerVM.currentTime
        
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
    let projectViewModel: ProjectViewModel
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
                            .simultaneousGesture(
                                selectedTool == .select ? 
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            if !isDragging {
                                                isDragging = true
                                                dragStartX = value.startLocation.x
                                                if projectViewModel.playerVM.isPlaying {
                                                    projectViewModel.playerVM.pause()
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
                                    if projectViewModel.playerVM.isPlaying {
                                        projectViewModel.playerVM.pause()
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
                                    if projectViewModel.playerVM.isPlaying {
                                        projectViewModel.playerVM.pause()
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
                                projectViewModel.splitSegment(segment, at: projectViewModel.playerVM.currentTime)
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


