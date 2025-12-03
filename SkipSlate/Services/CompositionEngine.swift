//
//  CompositionEngine.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Composition Engine (Kdenlive Pattern)
//
//  This class manages AVFoundation composition building with:
//  - Hash-based change detection (only rebuild when needed)
//  - Cached composition (reuse when possible)
//  - Isolated from UI state changes
//
//  ARCHITECTURE NOTE:
//  Following Kdenlive's MLT pattern, composition rebuilds ONLY when:
//  - Segment positions change
//  - Segment in/out points change
//  - Tracks are added/removed
//  - Effects are modified
//
//  Composition does NOT rebuild when:
//  - Tools are selected
//  - Zoom level changes
//  - Playhead moves
//  - Selection changes
//

import AVFoundation
import Combine

/// Engine for building and caching AVFoundation compositions
/// Uses hash-based change detection for lazy rebuilds (Kdenlive pattern)
final class CompositionEngine: ObservableObject {
    
    // MARK: - Cached State
    
    /// Current cached composition
    private(set) var cachedComposition: AVMutableComposition?
    
    /// Hash of last built composition
    private var lastBuildHash: Int = 0
    
    /// Whether a rebuild is in progress
    @Published private(set) var isRebuilding: Bool = false
    
    // MARK: - Configuration
    
    /// Frame rate for composition
    let frameRate: Int32 = 30
    
    /// Preferred timescale
    let preferredTimescale: CMTimeScale = 600
    
    // MARK: - Public Methods
    
    /// Get composition for the given project, rebuilding only if needed
    /// - Parameters:
    ///   - project: The project to build composition from
    ///   - forceRebuild: Force a rebuild even if hash matches
    /// - Returns: The composition, or nil if build fails
    func getComposition(for project: Project, forceRebuild: Bool = false) async -> AVMutableComposition? {
        let currentHash = computeHash(for: project)
        
        // Check if rebuild is needed
        if !forceRebuild && currentHash == lastBuildHash && cachedComposition != nil {
            print("SkipSlate: CompositionEngine - Using cached composition (hash: \(currentHash))")
            return cachedComposition
        }
        
        print("SkipSlate: CompositionEngine - Rebuilding composition (hash changed: \(lastBuildHash) -> \(currentHash))")
        
        await MainActor.run {
            isRebuilding = true
        }
        
        defer {
            Task { @MainActor in
                isRebuilding = false
            }
        }
        
        // Build new composition
        guard let composition = await buildComposition(from: project) else {
            print("SkipSlate: CompositionEngine - Build failed")
            return cachedComposition  // Return old one if available
        }
        
        // Cache the result
        cachedComposition = composition
        lastBuildHash = currentHash
        
        print("SkipSlate: CompositionEngine - Build succeeded, cached")
        return composition
    }
    
    /// Invalidate the cache, forcing next getComposition to rebuild
    func invalidateCache() {
        lastBuildHash = 0
        print("SkipSlate: CompositionEngine - Cache invalidated")
    }
    
    // MARK: - Private Methods
    
    /// Compute hash of project state for change detection
    private func computeHash(for project: Project) -> Int {
        var hasher = Hasher()
        
        // Hash segments
        hasher.combine(project.segments.count)
        for segment in project.segments {
            hasher.combine(segment.id)
            hasher.combine(segment.sourceStart)
            hasher.combine(segment.sourceEnd)
            hasher.combine(segment.compositionStartTime)
            hasher.combine(segment.enabled)
            hasher.combine(segment.kind.rawValue)
            
            // Include transform effects
            hasher.combine(segment.effects.scale)
            hasher.combine(segment.effects.positionX)
            hasher.combine(segment.effects.positionY)
            hasher.combine(segment.effects.rotation)
            hasher.combine(segment.transform.scaleToFillFrame)
        }
        
        // Hash tracks
        hasher.combine(project.tracks.count)
        for track in project.tracks {
            hasher.combine(track.id)
            hasher.combine(track.segments.count)
            hasher.combine(track.kind.rawValue)
        }
        
        return hasher.finalize()
    }
    
    /// Build AVMutableComposition from project
    private func buildComposition(from project: Project) async -> AVMutableComposition? {
        let composition = AVMutableComposition()
        
        let enabledSegments = project.segments.filter { $0.enabled && $0.kind == .clip }
        
        guard !enabledSegments.isEmpty else {
            print("SkipSlate: CompositionEngine - No enabled segments to build")
            return nil
        }
        
        // Add video track
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("SkipSlate: CompositionEngine - Failed to add video track")
            return nil
        }
        
        // Add audio track
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("SkipSlate: CompositionEngine - Failed to add audio track")
            return nil
        }
        
        // Sort segments by composition start time
        let sortedSegments = enabledSegments.sorted { $0.compositionStartTime < $1.compositionStartTime }
        
        for segment in sortedSegments {
            guard let clipID = segment.clipID ?? segment.sourceClipID,
                  let clip = project.clips.first(where: { $0.id == clipID }) else {
                print("SkipSlate: CompositionEngine - Missing clip for segment \(segment.id)")
                continue
            }
            
            let asset = AVURLAsset(url: clip.url)
            
            // Calculate times
            let sourceStart = CMTime(seconds: segment.sourceStart, preferredTimescale: preferredTimescale)
            let duration = CMTime(seconds: segment.duration, preferredTimescale: preferredTimescale)
            let timeRange = CMTimeRange(start: sourceStart, duration: duration)
            let insertTime = CMTime(seconds: segment.compositionStartTime, preferredTimescale: preferredTimescale)
            
            do {
                // Insert video
                if let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                    try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: insertTime)
                }
                
                // Insert audio
                if let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                    try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: insertTime)
                }
            } catch {
                print("SkipSlate: CompositionEngine - Error inserting segment: \(error.localizedDescription)")
            }
        }
        
        return composition
    }
}

