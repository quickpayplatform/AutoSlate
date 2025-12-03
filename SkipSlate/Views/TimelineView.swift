//
//  TimelineView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct TimelineView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var zoomLevel: TimelineZoom = .fit
    // ISOLATED: Tool state separate from project/player (Kdenlive pattern)
    @ObservedObject private var toolState = ToolState.shared
    
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
            // Timeline header with tool selector, zoom controls, delete button, and go-to-segment button
            HStack(spacing: 12) {
                Text("Timeline")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                // Tool selector buttons - ISOLATED from player/preview
                HStack(spacing: 4) {
                    ForEach(TimelineTool.allCases) { tool in
                        Button(action: {
                            // Use isolated ToolState - no connection to player
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
                
                Spacer()
                
                // Trash icon button - SIMPLE DELETE
                // CRITICAL: Check both selectedSegmentIDs and selectedSegment for deletion
                let hasSelection = !projectViewModel.selectedSegmentIDs.isEmpty || projectViewModel.selectedSegment != nil
                
                Button(action: {
                    print("SkipSlate: 🗑️ DELETE BUTTON CLICKED")
                    print("SkipSlate: 🗑️ Selected IDs: \(projectViewModel.selectedSegmentIDs)")
                    print("SkipSlate: 🗑️ Selected Segment ID: \(projectViewModel.selectedSegment?.id.uuidString.prefix(8) ?? "nil")")
                    
                    // CRITICAL: Sync selection before deleting
                    if projectViewModel.selectedSegmentIDs.isEmpty, let seg = projectViewModel.selectedSegment {
                        projectViewModel.selectedSegmentIDs = [seg.id]
                        print("SkipSlate: 🗑️ Synced selectedSegmentIDs from selectedSegment")
                    }
                    
                    projectViewModel.deleteSelectedSegments()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(hasSelection ? .red : .gray)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasSelection)
                .help(hasSelection ? "Delete selected segment" : "Click a segment first, then click this to delete")
                
                // Go to Segment Start button
                if !projectViewModel.selectedSegmentIDs.isEmpty {
                    Button(action: {
                        if let firstSelectedID = projectViewModel.selectedSegmentIDs.first,
                           let segment = projectViewModel.segments.first(where: { $0.id == firstSelectedID }) {
                            projectViewModel.seekToSegment(segment)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.circle")
                            Text("Go to Start")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
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
                
                if totalDuration > 0 {
                    Text("Total: \(timeString(from: totalDuration))")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppColors.panelBackground)
            
            Divider()
            
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
                    let contentWidth = baseTimelineWidth * zoomLevel.scale
                    let availableHeight = geometry.size.height
                    
                    ZStack(alignment: .leading) {
                        // Global cursor update based on selected tool
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onHover { hovering in
                                if hovering {
                                    toolState.selectedTool.cursor.push()
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
                                        playerViewModel: projectViewModel.playerVM,
                                        totalDuration: totalDuration,
                                        zoomLevel: zoomLevel,
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
                        
                    }
                }
            }
        }
        .background(AppColors.background)
        .focusable()
        .onKeyPress(.delete) {
            projectViewModel.deleteSelectedSegments()
            return .handled
        }
    }
    
    private var totalDuration: Double {
        // Calculate total duration including gaps (max end time of any segment)
        let enabledSegments = projectViewModel.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else { return 60.0 } // Minimum 60 seconds even when empty
        
        // Find maximum end time (compositionStartTime + duration)
        var maxEndTime = enabledSegments.map { $0.compositionStartTime + $0.duration }.max() ?? 0.0
        
        // Fallback: if no segments have explicit start times, sum durations (backward compatibility)
        if maxEndTime == 0.0 {
            maxEndTime = enabledSegments.reduce(0) { $0 + $1.duration }
        }
        
        // ENDLESS TIMELINE: Add extra space beyond the last segment
        // This allows users to drag segments to new positions beyond the current end
        let minDuration: Double = 60.0 // Minimum 60 seconds
        let extraSpace: Double = 30.0  // Extra space beyond last segment
        
        return max(minDuration, maxEndTime + extraSpace)
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Drag and Drop Delegate

struct SegmentDropDelegate: DropDelegate {
    let segment: Segment
    let segments: [Segment]
    let onMove: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }
        
        var hasHandled = false
        
        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, error in
            guard !hasHandled,
                  let data = data as? Data,
                  let draggedSegmentID = String(data: data, encoding: .utf8),
                  let draggedUUID = UUID(uuidString: draggedSegmentID),
                  let fromIndex = segments.firstIndex(where: { $0.id == draggedUUID }),
                  let toIndex = segments.firstIndex(where: { $0.id == segment.id }),
                  fromIndex != toIndex else {
                return
            }
            
            hasHandled = true
            DispatchQueue.main.async {
                onMove(fromIndex, toIndex)
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback when dragging over a segment
    }
    
    func dropExited(info: DropInfo) {
        // Visual feedback when leaving a segment
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// TimelineZoom is now defined in TimelineViewModel.swift
// This enum definition has been removed to avoid conflicts
