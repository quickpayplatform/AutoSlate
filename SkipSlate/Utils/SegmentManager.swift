//
//  SegmentManager.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//

import Foundation

/// Centralized segment manager that handles all segment operations
/// This simplifies deletion by ensuring all references are cleaned up automatically
class SegmentManager {
    
    // MARK: - Core Data Structures
    
    /// Central segment pool - single source of truth
    private(set) var segments: [Segment] = []
    
    /// Track-to-segment mapping: Track ID -> [Segment IDs on that track]
    private(set) var trackSegments: [UUID: [UUID]] = [:]
    
    // MARK: - Initialization
    
    init(segments: [Segment] = [], tracks: [TimelineTrack] = []) {
        self.segments = segments
        
        // Build track-to-segment mapping from tracks
        for track in tracks {
            trackSegments[track.id] = track.segments
        }
    }
    
    // MARK: - Query Operations
    
    /// Get all segments
    func allSegments() -> [Segment] {
        return segments
    }
    
    /// Get segment by ID
    func segment(withID id: UUID) -> Segment? {
        return segments.first { $0.id == id }
    }
    
    /// Get segments for a specific track
    func segments(forTrackID trackID: UUID) -> [Segment] {
        guard let segmentIDs = trackSegments[trackID] else { return [] }
        let segmentDict = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        return segmentIDs.compactMap { segmentDict[$0] }
    }
    
    /// Get all tracks that reference a segment
    func tracksContaining(segmentID: UUID) -> [UUID] {
        return trackSegments.compactMap { trackID, segmentIDs in
            segmentIDs.contains(segmentID) ? trackID : nil
        }
    }
    
    // MARK: - Add Operations
    
    /// Add a new segment to the pool
    @discardableResult
    func addSegment(_ segment: Segment) -> UUID {
        // Don't add duplicates
        if segments.contains(where: { $0.id == segment.id }) {
            return segment.id
        }
        segments.append(segment)
        return segment.id
    }
    
    /// Add a segment to a specific track
    func addSegment(_ segmentID: UUID, toTrack trackID: UUID) {
        // Ensure segment exists
        guard segments.contains(where: { $0.id == segmentID }) else {
            print("SkipSlate: SegmentManager - Warning: Cannot add non-existent segment \(segmentID) to track \(trackID)")
            return
        }
        
        // Initialize track if needed
        if trackSegments[trackID] == nil {
            trackSegments[trackID] = []
        }
        
        // Add if not already present
        if !trackSegments[trackID]!.contains(segmentID) {
            trackSegments[trackID]!.append(segmentID)
        }
    }
    
    // MARK: - Delete Operations (SIMPLIFIED!)
    
    /// Delete segments by ID - automatically cleans up ALL references
    /// This is the ONLY function you need to call for deletion
    func deleteSegments(withIDs ids: Set<UUID>) -> DeletionResult {
        guard !ids.isEmpty else {
            return DeletionResult(deletedSegmentIDs: [], gapSegmentsCreated: [])
        }
        
        var deletedSegmentIDs: [UUID] = []
        var gapSegmentsCreated: [Segment] = []
        
        // Process each segment to delete
        for segmentID in ids {
            guard let index = segments.firstIndex(where: { $0.id == segmentID }) else {
                continue // Segment doesn't exist, skip
            }
            
            let segment = segments[index]
            
            // Only convert clip segments to gaps; skip if already a gap
            guard segment.isClip else {
                // Already a gap, just remove it
                segments.remove(at: index)
                deletedSegmentIDs.append(segmentID)
                continue
            }
            
            // Create gap segment with same time range
            let gapSegment = Segment(
                gapDuration: segment.duration,
                compositionStartTime: segment.compositionStartTime
            )
            
            // Replace clip segment with gap segment
            segments[index] = gapSegment
            gapSegmentsCreated.append(gapSegment)
            
            // Update ALL track references automatically
            for (trackID, segmentIDs) in trackSegments {
                if let segmentIndex = segmentIDs.firstIndex(of: segmentID) {
                    trackSegments[trackID]?[segmentIndex] = gapSegment.id
                }
            }
            
            deletedSegmentIDs.append(segmentID)
        }
        
        return DeletionResult(
            deletedSegmentIDs: deletedSegmentIDs,
            gapSegmentsCreated: gapSegmentsCreated
        )
    }
    
    /// Result of a deletion operation
    struct DeletionResult {
        let deletedSegmentIDs: [UUID]
        let gapSegmentsCreated: [Segment]
    }
    
    // MARK: - Update Operations
    
    /// Update an existing segment
    func updateSegment(_ segment: Segment) {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else {
            print("SkipSlate: SegmentManager - Warning: Cannot update non-existent segment \(segment.id)")
            return
        }
        segments[index] = segment
    }
    
    /// Move a segment from one track to another
    func moveSegment(_ segmentID: UUID, fromTrack: UUID, toTrack: UUID, atIndex: Int? = nil) {
        // Remove from source track
        if let sourceIndex = trackSegments[fromTrack]?.firstIndex(of: segmentID) {
            trackSegments[fromTrack]?.remove(at: sourceIndex)
        }
        
        // Add to destination track
        if trackSegments[toTrack] == nil {
            trackSegments[toTrack] = []
        }
        
        if let index = atIndex {
            let clampedIndex = max(0, min(index, trackSegments[toTrack]!.count))
            trackSegments[toTrack]!.insert(segmentID, at: clampedIndex)
        } else {
            trackSegments[toTrack]!.append(segmentID)
        }
    }
    
    // MARK: - Export to Project Format
    
    /// Convert back to Project format (for saving/loading)
    func toProjectFormat() -> (segments: [Segment], tracks: [TimelineTrack]) {
        // Rebuild tracks from trackSegments mapping
        var tracks: [TimelineTrack] = []
        
        // Note: We need the original track metadata (type, name) which we don't store
        // This is a limitation - we'd need to pass original tracks or store metadata
        // For now, this is a placeholder that shows the structure
        
        return (segments: segments, tracks: tracks)
    }
    
    /// Initialize from Project format
    static func fromProject(_ project: Project) -> SegmentManager {
        let manager = SegmentManager(segments: project.segments, tracks: project.tracks)
        return manager
    }
    
    /// Apply changes back to a Project
    func applyToProject(_ project: inout Project) {
        project.segments = segments
        
        // Update track segment references
        for (trackID, segmentIDs) in trackSegments {
            if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }) {
                project.tracks[trackIndex].segments = segmentIDs
            }
        }
    }
}

