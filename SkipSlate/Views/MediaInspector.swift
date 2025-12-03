//
//  MediaInspector.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Media Inspector

struct MediaInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Available Media")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                // Debug: Show count of cached segments
                if !projectViewModel.allCachedSegments.isEmpty {
                    Text("\(projectViewModel.allCachedSegments.count) segments")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                }
            }
            
            Text("Drag segments to the timeline to add them. Select clips for rerun or delete ones you don't want.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                TextField("Search clips or segments...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(AppColors.panelBackground.opacity(0.5))
            .cornerRadius(6)
            
            Divider()
            
            // Media list - Show ALL individual segments
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Get all cached segments - force refresh when cache updates
                    let allCachedSegments = projectViewModel.allCachedSegments
                        .filter { segment in
                            // Filter by search text
                            if !searchText.isEmpty {
                                guard let clipID = segment.clipID,
                                      let clip = projectViewModel.clips.first(where: { $0.id == clipID }) else {
                                    return false
                                }
                                return clip.fileName.localizedCaseInsensitiveContains(searchText) ||
                                       String(format: "%.1fs", segment.duration).contains(searchText)
                            }
                            return true
                        }
                        .sorted { seg1, seg2 in
                            // Sort by clip name, then by source start time
                            guard let clipID1 = seg1.clipID,
                                  let clipID2 = seg2.clipID,
                                  let clip1 = projectViewModel.clips.first(where: { $0.id == clipID1 }),
                                  let clip2 = projectViewModel.clips.first(where: { $0.id == clipID2 }) else {
                                return false
                            }
                            if clip1.fileName != clip2.fileName {
                                return clip1.fileName < clip2.fileName
                            }
                            return seg1.sourceStart < seg2.sourceStart
                        }
                    
                    if allCachedSegments.isEmpty {
                        VStack(spacing: 12) {
                            Text("No segments available")
                                .foregroundColor(AppColors.secondaryText)
                                .font(.subheadline)
                            
                            Text("Run auto-edit first to generate segments from your clips")
                                .foregroundColor(AppColors.secondaryText.opacity(0.7))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Show individual segments grouped by clip (expandable)
                        let groupedByClip = Dictionary(grouping: allCachedSegments) { $0.clipID }
                        
                        ForEach(Array(groupedByClip.keys.compactMap { $0 }.sorted { clipID1, clipID2 in
                            guard let clip1 = projectViewModel.clips.first(where: { $0.id == clipID1 }),
                                  let clip2 = projectViewModel.clips.first(where: { $0.id == clipID2 }) else {
                                return false
                            }
                            return clip1.fileName < clip2.fileName
                        }), id: \.self) { clipID in
                            if let clip = projectViewModel.clips.first(where: { $0.id == clipID }),
                               let segments = groupedByClip[clipID] {
                                CachedMediaClipRow(
                                    clip: clip,
                                    segments: segments,
                                    projectViewModel: projectViewModel,
                                    isSelected: projectViewModel.isClipSelected(clipID),
                                    isDeleted: projectViewModel.isClipDeleted(clipID)
                                )
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Cached Media Clip Row

struct CachedMediaClipRow: View {
    let clip: MediaClip
    let segments: [Segment]
    @ObservedObject var projectViewModel: ProjectViewModel
    let isSelected: Bool
    let isDeleted: Bool
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Clip header (always visible)
            HStack(spacing: 12) {
                // Clip icon
                Image(systemName: iconName)
                    .foregroundColor(isDeleted ? AppColors.secondaryText.opacity(0.5) : AppColors.tealAccent)
                    .frame(width: 24)
                    .font(.system(size: 16))
                
                // Clip info
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.fileName)
                        .font(.caption)
                        .foregroundColor(isDeleted ? AppColors.secondaryText.opacity(0.5) : AppColors.primaryText)
                        .lineLimit(1)
                        .strikethrough(isDeleted)
                    
                    HStack(spacing: 6) {
                        Text("\(segments.count) segment\(segments.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                        
                        if clip.hasAudioTrack {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    // Expand/collapse button
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.secondaryText)
                    .disabled(isDeleted)
                    
                    // Select/favorite button
                    Button(action: {
                        projectViewModel.toggleClipSelection(clip.id)
                    }) {
                        Image(systemName: isSelected ? "star.fill" : "star")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isSelected ? AppColors.orangeAccent : AppColors.secondaryText)
                    .help(isSelected ? "Remove from favorites" : "Add to favorites")
                    .disabled(isDeleted)
                    
                    // Delete button
                    Button(action: {
                        // Show confirmation dialog before deleting
                        projectViewModel.removeClip(clip.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isDeleted ? AppColors.secondaryText.opacity(0.5) : .red)
                    .help("Delete clip from project")
                    .disabled(isDeleted)
                }
            }
            
            // Expanded segments list
            if isExpanded && !isDeleted {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(segments.sorted(by: { $0.sourceStart < $1.sourceStart }), id: \.id) { segment in
                        DraggableSegmentRow(segment: segment, clip: clip, projectViewModel: projectViewModel)
                    }
                }
                .padding(.leading, 36) // Indent segments under clip
            }
            
            // Clip summary (when collapsed)
            if !isExpanded && !isDeleted {
                HStack {
                    let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
                    Text("Total: \(String(format: "%.1f", totalDuration))s")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                    
                    Spacer()
                    
                    // Show status indicators
                    if projectViewModel.isClipSelected(clip.id) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("Favorited")
                                .font(.caption2)
                        }
                        .foregroundColor(AppColors.orangeAccent)
                    }
                }
            }
        }
        .padding(10)
        .background(isDeleted ? AppColors.panelBackground.opacity(0.3) : AppColors.cardBase)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? AppColors.orangeAccent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch clip.type {
        case .videoWithAudio, .videoOnly:
            return "video.fill"
        case .audioOnly:
            return "waveform"
        case .image:
            return "photo.fill"
        }
    }
}

// MARK: - Draggable Segment Row

struct DraggableSegmentRow: View {
    let segment: Segment
    let clip: MediaClip
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var showPreview: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(AppColors.secondaryText.opacity(0.5))
            
            // Segment info
            VStack(alignment: .leading, spacing: 2) {
                // CRASH-PROOF: Safe duration formatting with fallbacks
                Text("\(String(format: "%.1f", max(0, segment.duration)))s")
                    .font(.caption)
                    .foregroundColor(AppColors.primaryText)
                
                // CRASH-PROOF: Safe time range formatting with validation
                Text("\(String(format: "%.1f", max(0, segment.sourceStart)))s - \(String(format: "%.1f", max(segment.sourceStart, segment.sourceEnd)))s")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
            }
            
            Spacer()
            
            // Favorite button for segment
            // CRASH-PROOF: Safe favorite toggling with error handling
            Button(action: {
                // CRASH-PROOF: Validate segment has valid ID before toggling
                guard segment.id != nil else {
                    print("SkipSlate: ⚠️ Cannot favorite segment - segment has nil ID")
                    return
                }
                projectViewModel.toggleSegmentFavorite(segment.id)
            }) {
                Image(systemName: projectViewModel.isSegmentFavorited(segment.id) ? "star.fill" : "star")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundColor(projectViewModel.isSegmentFavorited(segment.id) ? AppColors.orangeAccent : AppColors.secondaryText)
            .help(projectViewModel.isSegmentFavorited(segment.id) ? "Remove from favorites" : "Add to favorites for rerun")
            .disabled(segment.id == nil) // CRASH-PROOF: Disable if segment has no ID
            
            // Play button for video segments
            if clip.type == .videoWithAudio || clip.type == .videoOnly {
                Button(action: {
                    showPreview = true
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.tealAccent)
                }
                .buttonStyle(.plain)
                .help("Preview this segment")
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.tealAccent)
            }
        }
        .padding(6)
        .background(
            // CRITICAL: Highlight if this segment is being previewed
            Group {
                if projectViewModel.previewedSegmentID == segment.id {
                    AppColors.tealAccent.opacity(0.3) // Highlight previewed segment
                } else {
                    AppColors.panelBackground.opacity(0.5)
                }
            }
        )
        .cornerRadius(4)
        .overlay(
            // Visual indicator for previewed segment
            Group {
                if projectViewModel.previewedSegmentID == segment.id {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppColors.tealAccent, lineWidth: 2)
                }
            }
        )
        .draggable(SegmentIDTransfer(segmentID: segment.id))
        .help("Drag to timeline to add this segment")
        .sheet(isPresented: $showPreview) {
            SegmentPreviewWindow(
                segment: segment,
                clip: clip,
                projectViewModel: projectViewModel,
                isPresented: $showPreview
            )
        }
        .onChange(of: showPreview) { oldValue, newValue in
            // CRITICAL: Track which segment is being previewed
            if newValue {
                // Preview opened - mark this segment as previewed
                projectViewModel.previewedSegmentID = segment.id
                print("SkipSlate: 📹 Preview opened for segment \(segment.id)")
            } else {
                // Preview closed - keep highlighting for a moment so user can see which one it was
                // The highlight will remain until another segment is previewed or user navigates away
                print("SkipSlate: 📹 Preview closed for segment \(segment.id)")
            }
        }
    }
}

