//
//  TimelineModel.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Timeline Model (Kdenlive Pattern)
//
//  This model manages timeline-specific data separately from ProjectViewModel.
//  It handles:
//  - Track arrangement (order, visibility)
//  - Segment positions on the timeline
//  - Timeline-specific operations (move, trim, split)
//
//  ARCHITECTURE NOTE:
//  Following Kdenlive's pattern, this model is separate from:
//  - ToolState (UI interaction mode)
//  - PlayerViewModel (playback state)
//  - CompositionEngine (AVFoundation composition)
//
//  Changes to TimelineModel trigger composition rebuilds ONLY when
//  segment structure actually changes (via hash comparison).
//

import SwiftUI
import Combine

/// Timeline model - manages track and segment arrangement
/// Separate from playback and tool state (Kdenlive pattern)
final class TimelineModel: ObservableObject {
    
    // MARK: - Track Management
    
    /// All tracks in the timeline
    @Published var tracks: [TimelineTrack] = []
    
    /// Track heights (ID -> height in points)
    @Published var trackHeights: [UUID: CGFloat] = [:]
    
    // MARK: - Segment Management
    
    /// All segments on the timeline
    @Published var segments: [Segment] = []
    
    // MARK: - Selection State
    
    /// Currently selected segment IDs
    @Published var selectedSegmentIDs: Set<UUID> = []
    
    /// Primary selected segment (for inspector)
    @Published var selectedSegment: Segment?
    
    // MARK: - Constants
    
    let defaultTrackHeight: CGFloat = 60
    let minTrackHeight: CGFloat = 40
    let maxTrackHeight: CGFloat = 200
    
    // MARK: - Computed Properties
    
    /// Video tracks sorted for display (newest on top)
    var sortedVideoTracks: [TimelineTrack] {
        tracks
            .filter { $0.kind == .video }
            .sorted { $0.index > $1.index }
    }
    
    /// Audio tracks sorted for display (newest on bottom)
    var sortedAudioTracks: [TimelineTrack] {
        tracks
            .filter { $0.kind == .audio }
            .sorted { $0.index < $1.index }
    }
    
    /// All tracks sorted for display (video on top, audio on bottom)
    var sortedTracks: [TimelineTrack] {
        sortedVideoTracks + sortedAudioTracks
    }
    
    /// Enabled segments only
    var enabledSegments: [Segment] {
        segments.filter { $0.enabled }
    }
    
    /// Total duration of timeline content
    var totalDuration: Double {
        guard !enabledSegments.isEmpty else { return 60.0 }
        let maxEndTime = enabledSegments.map { $0.compositionStartTime + $0.duration }.max() ?? 0
        return max(60.0, maxEndTime + 30.0)  // At least 60s, with 30s padding
    }
    
    /// Video track count
    var videoTrackCount: Int {
        tracks.filter { $0.kind == .video }.count
    }
    
    /// Audio track count
    var audioTrackCount: Int {
        tracks.filter { $0.kind == .audio }.count
    }
    
    // MARK: - Track Operations
    
    /// Get height for a track
    func trackHeight(for trackID: UUID) -> CGFloat {
        trackHeights[trackID] ?? defaultTrackHeight
    }
    
    /// Set height for a track
    func setTrackHeight(_ height: CGFloat, for trackID: UUID) {
        let clampedHeight = max(minTrackHeight, min(maxTrackHeight, height))
        trackHeights[trackID] = clampedHeight
    }
    
    /// Add a new track
    func addTrack(kind: TrackKind) {
        let existingTracks = tracks.filter { $0.kind == kind }
        let newTrack = TimelineTrack(
            kind: kind,
            index: existingTracks.count,
            segments: []
        )
        
        if kind == .video {
            // Insert video tracks after last video track
            if let lastVideoIndex = tracks.lastIndex(where: { $0.kind == .video }) {
                tracks.insert(newTrack, at: lastVideoIndex + 1)
            } else {
                tracks.insert(newTrack, at: 0)
            }
        } else {
            tracks.append(newTrack)
        }
        
        updateTrackIndices(for: kind)
    }
    
    /// Remove a track
    @discardableResult
    func removeTrack(kind: TrackKind) -> Bool {
        let tracksOfKind = tracks.filter { $0.kind == kind }
        
        guard tracksOfKind.count > 1 else { return false }
        
        guard let trackToRemove = tracksOfKind.max(by: { $0.index < $1.index }) else {
            return false
        }
        
        // Remove segments on this track
        let segmentIDsToRemove = trackToRemove.segments
        segments.removeAll { segmentIDsToRemove.contains($0.id) }
        
        // Remove track
        tracks.removeAll { $0.id == trackToRemove.id }
        
        updateTrackIndices(for: kind)
        return true
    }
    
    /// Update track indices to be consecutive
    private func updateTrackIndices(for kind: TrackKind) {
        let tracksOfKind = tracks.filter { $0.kind == kind }.sorted { $0.index < $1.index }
        for (newIndex, track) in tracksOfKind.enumerated() {
            if let trackIndex = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[trackIndex].index = newIndex
            }
        }
    }
    
    // MARK: - Segment Operations
    
    /// Get segments for a track
    func segments(for track: TimelineTrack) -> [Segment] {
        let segmentIDs = track.segments
        return segments.filter { segmentIDs.contains($0.id) }
    }
    
    /// Move segment to new position
    func moveSegment(_ segmentID: UUID, toTime newTime: Double) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else { return }
        let clampedTime = max(0, newTime)
        segments[index].compositionStartTime = clampedTime
    }
    
    /// Select a segment
    func selectSegment(_ segment: Segment, addToSelection: Bool = false) {
        if addToSelection {
            selectedSegmentIDs.insert(segment.id)
        } else {
            selectedSegmentIDs = [segment.id]
        }
        selectedSegment = segment
    }
    
    /// Clear selection
    func clearSelection() {
        selectedSegmentIDs.removeAll()
        selectedSegment = nil
    }
    
    // MARK: - Hash for Change Detection
    
    /// Compute hash of timeline state for change detection
    func computeHash() -> Int {
        var hasher = Hasher()
        hasher.combine(segments.count)
        for segment in segments {
            hasher.combine(segment.id)
            hasher.combine(segment.compositionStartTime)
            hasher.combine(segment.duration)
            hasher.combine(segment.sourceStart)
            hasher.combine(segment.enabled)
        }
        hasher.combine(tracks.count)
        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(track.segments.count)
        }
        return hasher.finalize()
    }
}

