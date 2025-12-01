//
//  PlayerViewModel.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI
import Combine
import AVFoundation
import CoreImage
import AppKit

// KVO context for player item status observation
private var playerItemStatusContext = 0

class PlayerViewModel: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    
    // SINGLE shared AVPlayer instance - never recreate
    var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private(set) var composition: AVMutableComposition? // Made internal for waveform access
    private var currentProject: Project?
    
    private var currentColorSettings: ColorSettings = .default
    private var currentAudioSettings: AudioSettings = .default
    
    // Image segments storage for compositor
    private var imageSegmentsByTime: [CMTime: (url: URL, duration: CMTime)] = [:]
    
    // Debouncing for updatePlayer
    private var updateTask: Task<Void, Never>?
    private var isUpdating = false
    private var lastCompositionDuration: CMTime = .zero
    private var lastCompositionHash: Int = 0
    
    init(project: Project) {
        super.init()
        // Note: On macOS, AVPlayer handles audio routing automatically
        // No need to configure AVAudioSession (iOS-only API)
        
        // Initialize player early
        player = AVPlayer()
        currentProject = project
        rebuildComposition(from: project)
    }
    
    func rebuildComposition(from project: Project) {
        // Cancel any pending updates
        updateTask?.cancel()
        
        // CRASH-PROOF: Validate project has segments before proceeding
        guard !project.segments.isEmpty else {
            print("SkipSlate: ⚠️ Cannot rebuild - project has no segments (count: \(project.segments.count))")
            print("SkipSlate: Project has \(project.clips.count) clips, \(project.tracks.count) tracks")
            return
        }
        
        // Calculate a simple hash of the project state to detect if it actually changed
        let projectHash = projectHash(project)
        if projectHash == lastCompositionHash && composition != nil {
            // Project hasn't actually changed, skip rebuild
            print("SkipSlate: Skipping rebuild - project state unchanged (hash: \(projectHash))")
            return
        }
        
        // CRASH-PROOF: Log rebuild details
        let enabledCount = project.segments.filter { $0.enabled }.count
        print("SkipSlate: 🔄 RebuildComposition called - \(enabledCount) enabled segments from \(project.segments.count) total (hash: \(projectHash), lastHash: \(lastCompositionHash))")
        
        lastCompositionHash = projectHash
        currentProject = project
        // Preserve playback state during rebuild
        let wasPlaying = isPlaying
        let savedTime = currentTime
        
        Task {
            do {
                let composition = try await buildComposition(from: project)
                
                await MainActor.run {
                    // CRASH-PROOF: Validate composition has content before updating player
                    let compositionDuration = composition.duration.seconds
                    guard compositionDuration > 0 && compositionDuration.isFinite else {
                        print("SkipSlate: ⚠️ Composition has invalid duration (\(compositionDuration)s), skipping player update to prevent freeze")
                        return
                    }
                    
                    // CRASH-PROOF: Validate composition has tracks with valid content
                    let videoTracks = composition.tracks(withMediaType: .video)
                    let audioTracks = composition.tracks(withMediaType: .audio)
                    guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
                        print("SkipSlate: ⚠️ Composition has no tracks, skipping player update to prevent freeze")
                        return
                    }
                    
                    // CRASH-PROOF: Validate tracks have valid durations (not zero or invalid)
                    var hasValidContent = false
                    for track in videoTracks {
                        let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                        if trackDuration > 0 && trackDuration.isFinite && !trackDuration.isNaN {
                            hasValidContent = true
                            break
                        }
                    }
                    if !hasValidContent {
                        for track in audioTracks {
                            let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                            if trackDuration > 0 && trackDuration.isFinite && !trackDuration.isNaN {
                                hasValidContent = true
                                break
                            }
                        }
                    }
                    guard hasValidContent else {
                        print("SkipSlate: ⚠️ Composition tracks have invalid durations (all zero/invalid), skipping player update to prevent freeze")
                        return
                    }
                    
                    self.composition = composition
                    self.currentColorSettings = project.colorSettings
                    self.currentAudioSettings = project.audioSettings
                    self.lastCompositionDuration = .zero // Reset to force update
                    self.updatePlayer()
                    
                    // CRASH-PROOF: Restore playback state if it was playing
                    // NOTE: For rerun auto-edit, playback restoration is handled by the caller
                    // Only restore here if this is a regular rebuild (not from rerun)
                    if wasPlaying {
                        // CRASH-PROOF: Validate duration before seeking
                        let maxDuration = (self.duration.isFinite && self.duration > 0) ? self.duration : 50.0
                        let seekTime = min(max(0.0, savedTime), maxDuration)
                        
                        // CRASH-PROOF: Validate seek time
                        guard seekTime.isFinite && seekTime >= 0 else {
                            print("SkipSlate: ⚠️ Invalid seek time in rebuildComposition: \(savedTime), skipping playback restoration")
                            return
                        }
                        
                        // CRASH-PROOF: Non-blocking seek with timeout protection
                        self.seek(to: seekTime, precise: true) { [weak self] finished in
                            // CRASH-PROOF: Proceed even if seek didn't finish (timeout protection)
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                if finished {
                                    self.play()
                                    print("SkipSlate: ✅ Playback restored after rebuild")
                                } else {
                                    // Seek didn't complete, but try to play anyway to prevent freeze
                                    print("SkipSlate: ⚠️ Seek did not complete in rebuildComposition, attempting to play anyway")
                                    self.play()
                                }
                            }
                        }
                    }
                }
            } catch {
                print("SkipSlate: ⚠⚠⚠ CRITICAL ERROR building composition: \(error)")
                if let nsError = error as NSError? {
                    print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code)")
                    print("SkipSlate: Error description: \(nsError.localizedDescription)")
                    if let userInfo = nsError.userInfo as? [String: Any] {
                        print("SkipSlate: Error userInfo: \(userInfo)")
                    }
                }
                // Surface error to UI if possible
                await MainActor.run {
                    // Could set an error state here for UI display
                    print("SkipSlate: Composition build failed - preview may not work correctly")
                }
            }
        }
    }
    
    private func projectHash(_ project: Project) -> Int {
        // Create a simple hash based on segments and settings
        // CRITICAL: Include compositionStartTime to detect segment position changes
        var hasher = Hasher()
        hasher.combine(project.segments.count)
        for segment in project.segments {
            hasher.combine(segment.id)
            hasher.combine(segment.sourceStart)
            hasher.combine(segment.sourceEnd)
            hasher.combine(segment.enabled)
            hasher.combine(segment.compositionStartTime) // CRITICAL: Include position in hash
            hasher.combine(segment.kind.rawValue) // Include segment kind (clip vs gap)
        }
        hasher.combine(project.colorSettings.exposure)
        hasher.combine(project.colorSettings.contrast)
        hasher.combine(project.colorSettings.saturation)
        hasher.combine(project.audioSettings.enableNoiseReduction)
        hasher.combine(project.audioSettings.enableCompression)
        hasher.combine(project.audioSettings.masterGainDB)
        return hasher.finalize()
    }
    
    func updateColorSettings(_ settings: ColorSettings) {
        guard settings != currentColorSettings else { return }
        currentColorSettings = settings
        debouncedUpdatePlayer()
    }
    
    func updateAudioSettings(_ settings: AudioSettings) {
        guard settings != currentAudioSettings else { return }
        currentAudioSettings = settings
        debouncedUpdatePlayer()
    }
    
    private func debouncedUpdatePlayer() {
        // Cancel any pending update
        updateTask?.cancel()
        
        // Schedule a new update after a short delay
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            if !Task.isCancelled {
                updatePlayer()
            }
        }
    }
    
    private func updatePlayer() {
        // Prevent concurrent updates
        guard !isUpdating else {
            print("SkipSlate: updatePlayer already in progress, skipping")
            return
        }
        
        guard let composition = composition else {
            print("SkipSlate: updatePlayer called but composition is nil")
            return
        }
        
        // Check if composition actually changed
        let compositionDuration = composition.duration
        if compositionDuration == lastCompositionDuration && playerItem != nil {
            // Only update if settings changed, not if composition is the same
            // This prevents unnecessary rebuilds when nothing actually changed
            return
        }
        
        isUpdating = true
        defer { isUpdating = false }
        
        lastCompositionDuration = compositionDuration
        print("SkipSlate: Updating player with composition duration: \(CMTimeGetSeconds(compositionDuration))s")
        
        let playerItem = AVPlayerItem(asset: composition)
        
        // Remove old observer if exists
        if let oldItem = self.playerItem {
            oldItem.removeObserver(self, forKeyPath: "status", context: &playerItemStatusContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        }
        
        // Check composition tracks
        let videoTracks = composition.tracks(withMediaType: .video)
        let audioTracks = composition.tracks(withMediaType: .audio)
        print("SkipSlate: Composition has \(videoTracks.count) video tracks and \(audioTracks.count) audio tracks")
        
        // Apply video composition with color settings
        if let videoComposition = createVideoCompositionWithTransitions(
            for: composition,
            settings: currentColorSettings
        ) {
            // Only apply if render size is valid
            if videoComposition.renderSize.width > 0 && videoComposition.renderSize.height > 0 {
                playerItem.videoComposition = videoComposition
                print("SkipSlate: Applied video composition with color settings (render size: \(videoComposition.renderSize))")
                print("SkipSlate: Color settings - exposure: \(currentColorSettings.exposure), contrast: \(currentColorSettings.contrast), saturation: \(currentColorSettings.saturation)")
                print("SkipSlate: Color grading - hue: \(currentColorSettings.colorHue)°, saturation: \(currentColorSettings.colorSaturation)")
            } else {
                print("SkipSlate: Video composition has invalid render size: \(videoComposition.renderSize), skipping")
            }
        } else {
            print("SkipSlate: No video composition created (no valid video tracks or zero duration)")
        }
        
        // Apply audio mix - prefer TransitionService, fallback to simple full-volume mix
        let compositionAudioTracks = composition.tracks(withMediaType: .audio)
        print("SkipSlate: ===== AUDIO MIX SETUP ======")
        print("SkipSlate: updatePlayer - Composition has \(compositionAudioTracks.count) audio track(s)")
        print("SkipSlate: Composition duration: \(CMTimeGetSeconds(composition.duration))s")
        
        if compositionAudioTracks.isEmpty {
            print("SkipSlate: ⚠⚠⚠ WARNING - Composition has NO audio tracks! Audio cannot play.")
            print("SkipSlate: Check if segments have audio or if insertion failed.")
            playerItem.audioMix = nil
        } else {
            // Log all audio tracks
            for (index, track) in compositionAudioTracks.enumerated() {
                let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                let trackStart = CMTimeGetSeconds(track.timeRange.start)
                let trackEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(track.timeRange))
                print("SkipSlate: Audio track \(index):")
                print("SkipSlate:   - Track ID: \(track.trackID)")
                print("SkipSlate:   - Duration: \(trackDuration)s")
                print("SkipSlate:   - TimeRange: \(trackStart)s - \(trackEnd)s")
                
                if trackDuration == 0 {
                    print("SkipSlate:   - ⚠ WARNING: Track has zero duration!")
                }
            }
            
            // Try TransitionService audio mix first (for crossfades)
            // Pass project so it can identify music tracks and skip transitions for them
            let enabledSegments = currentProject?.segments.filter { $0.enabled } ?? []
            let transitionAudioMix = TransitionService.shared.createAudioMixWithTransitions(
                for: composition,
                segments: enabledSegments,
                project: currentProject
            )
            
            if let transitionMix = transitionAudioMix, !transitionMix.inputParameters.isEmpty {
                playerItem.audioMix = transitionMix
                print("SkipSlate: ✓ Using TransitionService audio mix with \(transitionMix.inputParameters.count) input parameter(s)")
            } else {
                // Fallback: Create simple full-volume mix for ALL audio tracks
                print("SkipSlate: TransitionService mix unavailable, creating baseline full-volume mix")
                let baselineMix = AVMutableAudioMix()
                var inputParams: [AVMutableAudioMixInputParameters] = []
                
                let compositionDuration = composition.duration
                for track in compositionAudioTracks {
                    let params = AVMutableAudioMixInputParameters(track: track)
                    if compositionDuration.isValid && compositionDuration > .zero {
                        // Set volume to 1.0 at start and end to maintain throughout
                        params.setVolume(1.0, at: .zero)
                        params.setVolume(1.0, at: compositionDuration)
                        print("SkipSlate: Set volume to 1.0 for track ID \(track.trackID) from 0s to \(CMTimeGetSeconds(compositionDuration))s")
                    } else {
                        params.setVolume(1.0, at: .zero)
                        print("SkipSlate: Set volume to 1.0 for track ID \(track.trackID) (fallback)")
                    }
                    inputParams.append(params)
                }
                
                baselineMix.inputParameters = inputParams
                playerItem.audioMix = baselineMix
                print("SkipSlate: ✓ Applied baseline full-volume audio mix for \(compositionAudioTracks.count) audio track(s)")
                print("SkipSlate: Audio mix has \(inputParams.count) input parameter(s)")
            }
            print("SkipSlate: ================================")
        }
        
        // Add KVO observer for player item status
        playerItem.addObserver(
            self,
            forKeyPath: "status",
            options: [.initial, .new],
            context: &playerItemStatusContext
        )
        
        // Monitor for failed playback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )
        
        // Monitor for playback completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        self.playerItem = playerItem
        
        // Remove old time observer if it exists
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // CRITICAL: Always use the same player instance - never create a new one
        if player == nil {
            player = AVPlayer()
            print("SkipSlate: Created new AVPlayer instance")
        }
        
        // Ensure player volume is set to 1.0 (default should be 1.0, but be explicit)
        player?.volume = 1.0
        player?.isMuted = false
        print("SkipSlate: Set player volume to 1.0, muted: false")
        
        // CRITICAL: Verify audio mix is set before replacing item
        if let audioMix = playerItem.audioMix {
            print("SkipSlate: ✓ PlayerItem has audioMix with \(audioMix.inputParameters.count) input parameter(s)")
            for (index, param) in audioMix.inputParameters.enumerated() {
                // AVAudioMixInputParameters doesn't expose track directly, but we can verify it exists
                print("SkipSlate:   - Input param \(index): present")
            }
        } else {
            print("SkipSlate: ⚠⚠⚠ WARNING - PlayerItem has NO audioMix!")
            if !compositionAudioTracks.isEmpty {
                print("SkipSlate: ⚠⚠⚠ CRITICAL - Composition has \(compositionAudioTracks.count) audio track(s) but no audioMix was set!")
            }
        }
        
        // Verify composition tracks match playerItem asset tracks (async load)
        Task {
            do {
                let itemAudioTracks = try await playerItem.asset.loadTracks(withMediaType: .audio)
                await MainActor.run {
                    print("SkipSlate: PlayerItem asset has \(itemAudioTracks.count) audio track(s)")
                    if itemAudioTracks.count != compositionAudioTracks.count {
                        print("SkipSlate: ⚠ WARNING - Track count mismatch: composition=\(compositionAudioTracks.count), item.asset=\(itemAudioTracks.count)")
                    }
                }
            } catch {
                print("SkipSlate: Could not load playerItem asset audio tracks: \(error)")
            }
        }
        
        // Replace the current item on the existing player
        player?.replaceCurrentItem(with: playerItem)
        print("SkipSlate: Replaced player item on existing player")
        
        // CRITICAL: Verify audio mix is still set after replacing
        if let audioMix = playerItem.audioMix {
            print("SkipSlate: ✓ PlayerItem still has audioMix after replace")
        } else {
            print("SkipSlate: ⚠⚠⚠ ERROR - PlayerItem lost audioMix after replace!")
        }
        
        // Verify player.currentItem has audio tracks
        if let currentItem = player?.currentItem {
            let currentItemTracks = currentItem.tracks
            let currentItemAudioTracks = currentItemTracks.filter { $0.assetTrack?.mediaType == .audio }
            print("SkipSlate: Player.currentItem has \(currentItemTracks.count) total tracks, \(currentItemAudioTracks.count) audio tracks")
            
            if !compositionAudioTracks.isEmpty && currentItemAudioTracks.isEmpty {
                print("SkipSlate: ⚠⚠⚠ CRITICAL ERROR - Composition has audio but player.currentItem has NO audio tracks!")
            }
        }
        
        // Always setup time observer after setting player item
        setupTimeObserver()
        
        // Use the actual composition duration, or fall back to calculated duration if needed
        let itemDuration = playerItem.asset.duration
        let actualDuration = itemDuration.isValid && itemDuration.isNumeric && itemDuration > .zero
            ? itemDuration
            : composition.duration
        
        // If still zero, use calculated duration from segments
        if actualDuration.seconds == 0, let project = currentProject {
            var calculatedDuration = CMTime.zero
            for segment in project.segments.filter({ $0.enabled }) {
                calculatedDuration = CMTimeAdd(calculatedDuration, CMTime(seconds: segment.duration, preferredTimescale: 600))
            }
            if calculatedDuration > .zero {
                duration = CMTimeGetSeconds(calculatedDuration)
                print("SkipSlate: Using calculated duration: \(duration)s")
            } else {
                duration = CMTimeGetSeconds(actualDuration)
            }
        } else {
            duration = CMTimeGetSeconds(actualDuration)
        }
        
        print("SkipSlate: Player updated. Composition duration: \(CMTimeGetSeconds(composition.duration))s, Item duration: \(CMTimeGetSeconds(itemDuration))s, Final duration: \(duration)s")
        
        // Debug: Check if video tracks exist in player item
        Task {
            // Wait a moment for tracks to load
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                let playerItemTracks = playerItem.tracks
                let videoPlayerTracks = playerItemTracks.filter { $0.assetTrack?.mediaType == .video }
                print("SkipSlate: PlayerItem has \(playerItemTracks.count) total tracks, \(videoPlayerTracks.count) video tracks")
                
                if videoPlayerTracks.isEmpty && !videoTracks.isEmpty {
                    print("SkipSlate: ERROR - Composition has video tracks but PlayerItem does not!")
                }
            }
        }
    }
    
    private func createVideoCompositionWithTransitions(
        for composition: AVMutableComposition,
        settings: ColorSettings
    ) -> AVMutableVideoComposition? {
        guard let project = currentProject else {
            return createVideoComposition(for: composition, settings: settings)
        }
        
        // For image-only compositions, calculate duration from segments
        let enabledSegments = project.segments.filter { $0.enabled }
        if !imageSegmentsByTime.isEmpty && composition.duration.seconds == 0 {
            var totalDuration = CMTime.zero
            for segment in enabledSegments {
                totalDuration = CMTimeAdd(totalDuration, CMTime(seconds: segment.duration, preferredTimescale: 600))
            }
            print("SkipSlate: Image-only composition, using calculated duration: \(CMTimeGetSeconds(totalDuration))s")
        }
        
        // Use TransitionService to create composition with transitions
        if let videoComposition = TransitionService.shared.createVideoCompositionWithTransitions(
            for: composition,
            segments: enabledSegments,
            project: project
        ) {
            // Apply color settings to the compositor
            globalColorSettings = settings
            
            // For image-only compositions, ensure render duration matches calculated duration
            if !imageSegmentsByTime.isEmpty && composition.duration.seconds == 0 {
                var totalDuration = CMTime.zero
                for segment in enabledSegments {
                    totalDuration = CMTimeAdd(totalDuration, CMTime(seconds: segment.duration, preferredTimescale: 600))
                }
                // Update instructions to cover the full duration
                if let instruction = videoComposition.instructions.first as? AVMutableVideoCompositionInstruction {
                    instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
                }
            }
            
            return videoComposition
        }
        
        // Fallback to standard composition
        return createVideoComposition(for: composition, settings: settings)
    }
    
    private func createAudioMixWithTransitions(for composition: AVMutableComposition) -> AVAudioMix? {
        guard let project = currentProject else { return nil }
        
        let enabledSegments = project.segments.filter { $0.enabled }
        return TransitionService.shared.createAudioMixWithTransitions(
            for: composition,
            segments: enabledSegments
        )
    }
    
    /// Create a safe baseline video composition with no transforms or opacity changes
    /// This is used for debugging to ensure video is visible before adding transitions
    private func createSafeVideoComposition(for composition: AVMutableComposition) -> AVMutableVideoComposition? {
        guard let videoTrack = composition.tracks(withMediaType: .video).first else {
            print("SkipSlate: No video track found for safe composition")
            return nil
        }
        
        // Check for valid render size - must be positive
        let naturalSize = videoTrack.naturalSize
        guard naturalSize.width > 0 && naturalSize.height > 0 else {
            print("SkipSlate: Video track has invalid naturalSize: \(naturalSize), skipping video composition")
            return nil
        }
        
        // Check for valid duration
        guard composition.duration.seconds > 0 else {
            print("SkipSlate: Composition has zero duration, skipping video composition")
            return nil
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = naturalSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        
        // Set full opacity at start - no ramps, no transforms
        layerInstruction.setOpacity(1.0, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        print("SkipSlate: Safe videoComposition created for duration: \(CMTimeGetSeconds(composition.duration))s, renderSize: \(videoComposition.renderSize)")
        
        return videoComposition
    }
    
    func buildComposition(from project: Project) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        
        // CRASH-PROOF: Validate project has enabled segments BEFORE creating tracks
        let enabledSegments = project.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else {
            print("SkipSlate: ⚠️ buildComposition called with 0 enabled segments - returning empty composition without creating tracks")
            // Return empty composition (don't create tracks that will be invalid)
            return composition
        }
        
        // Clear image segments storage
        imageSegmentsByTime.removeAll()
        
        let timescale: Int32 = 600
        var hasRealVideo = false
        var hasAnyImage = false
        
        // Create video tracks for each video track in the timeline
        var videoTracksByTrackID: [UUID: AVMutableCompositionTrack] = [:]
        for track in project.tracks where track.type == .videoPrimary || track.type == .videoOverlay {
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw NSError(domain: "PlayerViewModel", code: -1)
            }
            videoTracksByTrackID[track.id] = videoTrack
        }
        
        // Create a single audio track for mixing all audio
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "PlayerViewModel", code: -1)
        }
        
        // Create a dedicated image timing track for image-only segments
        guard let imageTimingTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "PlayerViewModel", code: -1)
        }
        
        // Build segment dictionary for quick lookup
        let segmentDict = Dictionary(uniqueKeysWithValues: project.segments.map { ($0.id, $0) })
        
        // Use explicit compositionStartTime from segments (supports gaps - non-ripple behavior)
        // If not set, fall back to calculating from track order (backward compatibility)
        var segmentCompositionStarts: [Segment.ID: CMTime] = [:]
        for track in project.tracks {
            var currentTime = CMTime.zero
            for segmentID in track.segments {
                if let segment = segmentDict[segmentID], segment.enabled {
                    // Use stored compositionStartTime if available, otherwise calculate sequentially
                    if segment.compositionStartTime > 0 {
                        segmentCompositionStarts[segmentID] = CMTime(seconds: segment.compositionStartTime, preferredTimescale: timescale)
                    } else {
                        // Fallback: calculate sequentially (for backward compatibility)
                    segmentCompositionStarts[segmentID] = currentTime
                    currentTime = CMTimeAdd(currentTime, CMTime(seconds: segment.duration, preferredTimescale: timescale))
                    }
                }
            }
        }
        
        // Note: enabledSegments was already calculated above for early validation
        // Re-filter here to ensure we're using the latest state (though it shouldn't change)
        let finalEnabledSegments = project.segments.filter { $0.enabled }
        
        print("SkipSlate: Building composition with \(finalEnabledSegments.count) enabled segments from \(project.clips.count) clips across \(project.tracks.count) tracks")
        
        // Calculate total duration from all segments (including gaps)
        // Find the maximum end time of any segment
        var totalDuration = CMTime.zero
        for segment in finalEnabledSegments {
            let segmentEndTime = segment.compositionStartTime + segment.duration
            let segmentEndCMTime = CMTime(seconds: segmentEndTime, preferredTimescale: timescale)
            if segmentEndCMTime > totalDuration {
                totalDuration = segmentEndCMTime
            }
        }
        
        // Fallback: if no segments have explicit start times, calculate from tracks (backward compatibility)
        if totalDuration == .zero {
        for track in project.tracks {
            var trackDuration = CMTime.zero
            for segmentID in track.segments {
                if let segment = segmentDict[segmentID], segment.enabled {
                    trackDuration = CMTimeAdd(trackDuration, CMTime(seconds: segment.duration, preferredTimescale: timescale))
                }
            }
            totalDuration = max(totalDuration, trackDuration) // Use longest track duration
        }
        }
        print("SkipSlate: Total calculated duration (including gaps): \(CMTimeGetSeconds(totalDuration))s")
        
        // CRASH-PROOF: Double-check we still have enabled segments and valid duration
        // (segments might have been disabled between early check and now)
        guard !finalEnabledSegments.isEmpty, totalDuration > .zero else {
            print("SkipSlate: ⚠️ No enabled segments or zero duration after track creation, returning empty composition")
            print("SkipSlate:   - Enabled segments: \(finalEnabledSegments.count)")
            print("SkipSlate:   - Total segments: \(project.segments.count)")
            print("SkipSlate:   - Total duration: \(CMTimeGetSeconds(totalDuration))s")
            print("SkipSlate:   - Project clips: \(project.clips.count)")
            print("SkipSlate:   - Project tracks: \(project.tracks.count)")
            
            // CRASH-PROOF: Return empty composition (tracks were created but no content)
            // The caller's validation should prevent updatePlayer() from being called
            return composition
        }
        
        // Determine render size for dummy video asset (only if we have image segments)
        var renderSize = CGSize(width: 1920, height: 1080)
        let presetRatio = Double(project.resolution.width) / Double(project.resolution.height)
        let targetRatio = project.aspectRatio.ratio
        let ratioDiff = abs(presetRatio - targetRatio)
        
        if ratioDiff > 0.01 {
            if presetRatio > targetRatio {
                renderSize.height = CGFloat(Double(project.resolution.width) / targetRatio)
                renderSize.width = CGFloat(project.resolution.width)
            } else {
                renderSize.width = CGFloat(Double(project.resolution.height) * targetRatio)
                renderSize.height = CGFloat(project.resolution.height)
            }
        } else {
            renderSize = CGSize(width: CGFloat(project.resolution.width), height: CGFloat(project.resolution.height))
        }
        
        // Create a minimal black frame video asset for image timing (only if we have image segments)
        var dummyVideoAsset: AVAsset?
        var dummyVideoTrack: AVAssetTrack?
        
        // Check if we'll need dummy video for images
        let hasImageSegments = finalEnabledSegments.contains { segment in
            if let clip = project.clips.first(where: { $0.id == segment.sourceClipID }) {
                return clip.type == .image
            }
            return false
        }
        
        if hasImageSegments {
            do {
                dummyVideoAsset = try await createDummyVideoAsset(duration: totalDuration, timescale: timescale, renderSize: renderSize)
                if let asset = dummyVideoAsset {
                    let dummyVideoTracks = try await asset.loadTracks(withMediaType: .video)
                    dummyVideoTrack = dummyVideoTracks.first
                    if let urlAsset = asset as? AVURLAsset {
                        print("SkipSlate: Created dummy video asset for image timing: \(urlAsset.url.absoluteString)")
                    } else {
                        print("SkipSlate: Created dummy video asset for image timing")
                    }
                }
            } catch {
                print("SkipSlate: Error creating dummy video asset: \(error)")
                // Continue without dummy video - will fall back to other methods
            }
        }
        
        // Process segments by iterating through tracks to maintain order
        for track in project.tracks {
            for segmentID in track.segments {
                guard let segment = segmentDict[segmentID], segment.enabled else { continue }
                
                // CRITICAL: Skip gap segments - they render as black (no media inserted)
                if segment.isGap {
                    print("SkipSlate: Skipping gap segment at \(segment.compositionStartTime)s (duration: \(segment.duration)s) - will render as black")
                    continue
                }
                
                // For clip segments, require a valid clipID (using helper)
                guard let clipID = segment.clipID,
                      let clip = project.clips.first(where: { $0.id == clipID }) else {
                    print("SkipSlate: Warning - Clip segment missing clipID or clip not found")
                    continue
                }
                
                let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: timescale)
                guard segmentDuration > .zero else { continue }
                
                // Get composition start time for this segment
                guard let compositionStart = segmentCompositionStarts[segment.id] else {
                    print("SkipSlate: Warning - No composition start time calculated for segment \(segment.id)")
                    continue
                }
                
                print("SkipSlate: Processing segment from clip '\(clip.fileName)' type: \(clip.type), duration: \(segment.duration)s, start: \(segment.sourceStart)s, composition time: \(CMTimeGetSeconds(compositionStart))s")
                
                // Handle images - store for compositor AND insert actual video segment for timing
                if clip.type == .image {
                    hasAnyImage = true
                    imageSegmentsByTime[compositionStart] = (url: clip.url, duration: segmentDuration)
                    print("SkipSlate: Added image segment at time \(CMTimeGetSeconds(compositionStart))")
                    
                    // Insert actual video content from dummy asset to establish duration
                    // The compositor will render the actual image over this placeholder
                    if let dummyTrack = dummyVideoTrack, let dummyAsset = dummyVideoAsset {
                        do {
                            // Use the dummy track's duration, but clamp to segment duration
                            let dummyDuration = try await dummyAsset.load(.duration)
                            let sourceDuration = min(segmentDuration, dummyDuration)
                            let sourceTimeRange = CMTimeRange(
                                start: .zero,
                                duration: sourceDuration
                            )
                            try imageTimingTrack.insertTimeRange(
                                sourceTimeRange,
                                of: dummyTrack,
                                at: compositionStart
                            )
                            print("SkipSlate: Inserted timing segment for image at time \(CMTimeGetSeconds(compositionStart)), duration: \(CMTimeGetSeconds(sourceDuration))s")
                        } catch {
                            print("SkipSlate: Error inserting timing segment for image: \(error)")
                            // Fall back to empty time range if dummy video fails
                            do {
                                try imageTimingTrack.insertEmptyTimeRange(CMTimeRange(start: compositionStart, duration: segmentDuration))
                            } catch {
                                print("SkipSlate: Also failed to insert empty time range: \(error)")
                            }
                        }
                    } else {
                        // Fall back to empty time range if no dummy video available
                        do {
                            try imageTimingTrack.insertEmptyTimeRange(CMTimeRange(start: compositionStart, duration: segmentDuration))
                            print("SkipSlate: Inserted empty time range for image at \(CMTimeGetSeconds(compositionStart))")
                        } catch {
                            print("SkipSlate: Failed to insert empty time range: \(error)")
                        }
                    }
                    
                    // Check for audio-only clips that should play during the entire composition
                    // For image-only compositions, we typically want one audio track playing throughout
                    // Find the first audio-only clip and use it for the full duration
                    if hasAnyImage && !hasRealVideo {
                        // Only insert audio once for the first image segment
                        if compositionStart == .zero {
                            let audioClips = project.clips.filter { $0.type == .audioOnly }
                            if let audioClip = audioClips.first {
                                let audioAsset = AVURLAsset(url: audioClip.url)
                                do {
                                    let sourceAudioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                                    if let sourceAudioTrack = sourceAudioTracks.first {
                                        // Insert audio for the full composition duration
                                        let audioDuration = try await audioAsset.load(.duration)
                                        let insertDuration = min(totalDuration, audioDuration)
                                        let audioTimeRange = CMTimeRange(
                                            start: .zero,
                                            duration: insertDuration
                                        )
                                        try audioTrack.insertTimeRange(
                                            audioTimeRange,
                                            of: sourceAudioTrack,
                                            at: .zero
                                        )
                                        print("SkipSlate: Inserted audio track for image-only composition, duration: \(CMTimeGetSeconds(insertDuration))s, from clip: \(audioClip.fileName)")
                                    } else {
                                        print("SkipSlate: No audio track found in audio clip: \(audioClip.fileName)")
                                    }
                                } catch {
                                    print("SkipSlate: Error inserting audio for image-only composition: \(error)")
                                }
                            } else {
                                print("SkipSlate: No audio-only clips found in project (has \(project.clips.count) clips)")
                            }
                        }
                    }
                    
                    continue
                }
                
                // Create asset and ensure it's ready
                let asset = AVURLAsset(url: clip.url)
            
            // CRITICAL: Pre-load asset properties to ensure tracks are available
            do {
                // Load duration first to ensure asset is ready
                let assetDuration = try await asset.load(.duration)
                print("SkipSlate: Asset '\(clip.fileName)' loaded, duration: \(CMTimeGetSeconds(assetDuration))s")
                
                // Pre-load tracks to ensure they're available
                let _ = try await asset.loadTracks(withMediaType: .video)
                let _ = try await asset.loadTracks(withMediaType: .audio)
            } catch {
                print("SkipSlate: ⚠⚠⚠ ERROR loading asset '\(clip.fileName)': \(error)")
                print("SkipSlate: This asset may not be usable. Error: \(error.localizedDescription)")
                continue
            }
            
            // Insert video if available - use the appropriate track based on timeline track type
            if track.type == .videoPrimary || track.type == .videoOverlay {
                if let compositionVideoTrack = videoTracksByTrackID[track.id] {
                    do {
                        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
                        if let sourceVideoTrack = sourceVideoTracks.first {
                            // CRASH-PROOF: Validate source time range is within asset duration
                            let assetDuration = try await asset.load(.duration)
                            let maxSourceEnd = CMTimeGetSeconds(assetDuration)
                            
                            guard segment.sourceStart >= 0,
                                  segment.sourceEnd > segment.sourceStart,
                                  segment.sourceEnd <= maxSourceEnd else {
                                print("SkipSlate: ⚠️ Invalid source time range for clip '\(clip.fileName)': start=\(segment.sourceStart)s, end=\(segment.sourceEnd)s, asset duration=\(maxSourceEnd)s")
                                continue
                            }
                            
                            let sourceTimeRange = CMTimeRange(
                                start: CMTime(seconds: segment.sourceStart, preferredTimescale: timescale),
                                duration: segmentDuration
                            )
                            
                            // CRASH-PROOF: Ensure source time range doesn't exceed asset duration
                            let sourceEndTime = CMTimeRangeGetEnd(sourceTimeRange)
                            if sourceEndTime > assetDuration {
                                print("SkipSlate: ⚠️ Source time range exceeds asset duration, clamping")
                                let clampedDuration = CMTimeSubtract(assetDuration, sourceTimeRange.start)
                                let clampedTimeRange = CMTimeRange(start: sourceTimeRange.start, duration: clampedDuration)
                                
                                print("SkipSlate: Inserting video track at composition time \(CMTimeGetSeconds(compositionStart)), source range: \(CMTimeGetSeconds(clampedTimeRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(clampedTimeRange)))")
                                
                                try compositionVideoTrack.insertTimeRange(
                                    clampedTimeRange,
                                    of: sourceVideoTrack,
                                    at: compositionStart
                                )
                            } else {
                                print("SkipSlate: Inserting video track at composition time \(CMTimeGetSeconds(compositionStart)), source range: \(CMTimeGetSeconds(sourceTimeRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(sourceTimeRange)))")
                                
                                try compositionVideoTrack.insertTimeRange(
                                    sourceTimeRange,
                                    of: sourceVideoTrack,
                                    at: compositionStart
                                )
                            }
                            hasRealVideo = true
                            print("SkipSlate: ✅ Successfully inserted video segment into track \(track.name) from clip '\(clip.fileName)'")
                        } else {
                            print("SkipSlate: ⚠️ No video track found in clip '\(clip.fileName)' - skipping video insertion")
                        }
                    } catch {
                        print("SkipSlate: Error inserting video segment: \(error)")
                    }
                }
            }
            
            // Insert audio if available - CRITICAL FIX
            // Try to load audio even if hasAudioTrack=false (fallback for detection issues)
            // First try if hasAudioTrack=true, then try as fallback if hasAudioTrack=false
            var shouldTryAudio = clip.hasAudioTrack
            
            // FALLBACK: If clip is marked as videoOnly but we haven't tried audio yet, try it anyway
            // This handles cases where MediaImportService incorrectly detected no audio
            if !shouldTryAudio && clip.type == .videoOnly {
                print("SkipSlate: Clip '\(clip.fileName)' marked as videoOnly, but attempting audio load as fallback...")
                shouldTryAudio = true
            }
            
            if shouldTryAudio {
                do {
                    let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                    print("SkipSlate: Clip '\(clip.fileName)' has \(sourceAudioTracks.count) audio track(s) (hasAudioTrack=\(clip.hasAudioTrack), attempting load)")
                    
                    if sourceAudioTracks.isEmpty {
                        if clip.hasAudioTrack {
                            print("SkipSlate: ⚠⚠⚠ WARNING - Clip marked as hasAudioTrack=true but no audio tracks found!")
                            print("SkipSlate: This may indicate a mismatch between import detection and actual asset.")
                        } else {
                            print("SkipSlate: Fallback audio load confirmed no audio tracks (clip correctly marked as videoOnly)")
                        }
                    } else if let sourceAudioTrack = sourceAudioTracks.first {
                    // Load track properties to ensure they're ready
                    let trackTimeRange = try await sourceAudioTrack.load(.timeRange)
                    let sourceDuration = trackTimeRange.duration
                    let sourceStartTime = CMTime(seconds: segment.sourceStart, preferredTimescale: timescale)
                    
                    // Verify source duration is valid
                    guard sourceDuration.isValid && sourceDuration > .zero else {
                        print("SkipSlate: ⚠⚠⚠ ERROR - Source audio track has invalid duration: \(CMTimeGetSeconds(sourceDuration))s")
                        continue
                    }
                    
                    // Clamp to available duration
                    let actualDuration = min(segmentDuration, sourceDuration)
                    let sourceTimeRange = CMTimeRange(
                        start: sourceStartTime,
                        duration: actualDuration
                    )
                    
                    // Verify time range is valid
                    guard sourceTimeRange.isValid && actualDuration > .zero else {
                        print("SkipSlate: ⚠⚠⚠ ERROR - Invalid audio time range calculated")
                        continue
                    }
                    
                    print("SkipSlate: Inserting audio at composition time \(CMTimeGetSeconds(compositionStart))s")
                    print("SkipSlate: Source audio track duration: \(CMTimeGetSeconds(sourceDuration))s")
                    print("SkipSlate: Requested segment duration: \(CMTimeGetSeconds(segmentDuration))s")
                    print("SkipSlate: Actual duration to insert: \(CMTimeGetSeconds(actualDuration))s")
                    print("SkipSlate: Source time range: \(CMTimeGetSeconds(sourceTimeRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(sourceTimeRange)))s")
                    
                    // Verify audio track is still valid
                    guard audioTrack.trackID != kCMPersistentTrackID_Invalid else {
                        print("SkipSlate: ⚠⚠⚠ ERROR - Audio track is invalid!")
                        continue
                    }
                    
                    // CRITICAL: Insert audio with error handling
                    try audioTrack.insertTimeRange(
                        sourceTimeRange,
                        of: sourceAudioTrack,
                        at: compositionStart
                    )
                    
                    // VERIFY audio was actually inserted by checking the track
                    let insertedTrackTimeRange = audioTrack.timeRange
                    let insertedDuration = CMTimeGetSeconds(insertedTrackTimeRange.duration)
                    print("SkipSlate: ✓✓✓ Successfully inserted audio segment from '\(clip.fileName)'")
                    print("SkipSlate: Audio track now has timeRange: \(CMTimeGetSeconds(insertedTrackTimeRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(insertedTrackTimeRange)))s")
                    print("SkipSlate: Audio track total duration after insert: \(insertedDuration)s")
                    
                    if insertedDuration == 0 {
                        print("SkipSlate: ⚠⚠⚠ CRITICAL: Audio track has ZERO duration after insertion!")
                    } else {
                        print("SkipSlate: ✓ Audio insertion verified - track has \(insertedDuration)s of audio")
                    }
                    }
                } catch {
                    print("SkipSlate: ✗✗✗ CRITICAL ERROR inserting audio segment from '\(clip.fileName)': \(error)")
                    print("SkipSlate: Error details: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code)")
                        print("SkipSlate: Error userInfo: \(nsError.userInfo)")
                    }
                    // Continue to next segment - don't fail entire composition
                }
            } else {
                // Only log if we're not attempting fallback
                if clip.type != .videoOnly {
                    print("SkipSlate: Clip '\(clip.fileName)' has no audio track (hasAudioTrack=false, type: \(clip.type))")
                }
            }
            }
        }
        
        // CRITICAL: For Highlight Reel (and other projects with audio-only music tracks),
        // insert the music track to play throughout the entire composition
        // This should happen AFTER all video segments are inserted
        if project.type == .highlightReel || project.type == .musicVideo || project.type == .danceVideo {
            let audioOnlyClips = project.clips.filter { $0.type == .audioOnly }
            if let musicClip = audioOnlyClips.first {
                print("SkipSlate: Inserting music track '\(musicClip.fileName)' for full composition duration")
                let musicAsset = AVURLAsset(url: musicClip.url)
                do {
                    let sourceAudioTracks = try await musicAsset.loadTracks(withMediaType: .audio)
                    if let sourceAudioTrack = sourceAudioTracks.first {
                        let musicDuration = try await musicAsset.load(.duration)
                        // Use the composition's total duration (calculated from segments)
                        let insertDuration = min(totalDuration, musicDuration)
                        
                        // Check if audio track already has content
                        let existingAudioDuration = CMTimeGetSeconds(audioTrack.timeRange.duration)
                        if existingAudioDuration == 0 {
                            // Audio track is empty, insert music from the start
                            let audioTimeRange = CMTimeRange(
                                start: .zero,
                                duration: insertDuration
                            )
                            try audioTrack.insertTimeRange(
                                audioTimeRange,
                                of: sourceAudioTrack,
                                at: .zero
                            )
                            print("SkipSlate: ✓ Inserted music track for full composition duration: \(CMTimeGetSeconds(insertDuration))s")
                        } else {
                            // Audio track already has content (from video segments with audio)
                            // For Highlight Reel, music is primary - insert it anyway
                            // The audio mix will handle volume levels
                            let audioTimeRange = CMTimeRange(
                                start: .zero,
                                duration: insertDuration
                            )
                            // Insert music track (will mix with any existing audio)
                            try audioTrack.insertTimeRange(
                                audioTimeRange,
                                of: sourceAudioTrack,
                                at: .zero
                            )
                            print("SkipSlate: ✓ Inserted music track (mixing with video audio if present): \(CMTimeGetSeconds(insertDuration))s")
                        }
                    } else {
                        print("SkipSlate: ⚠ No audio tracks found in music clip: \(musicClip.fileName)")
                    }
                } catch {
                    print("SkipSlate: ✗ Error inserting music track: \(error)")
                }
            } else {
                print("SkipSlate: ⚠ No audio-only clips found for music track (project type: \(project.type))")
            }
        }
        
        let isImageOnlyComposition = !hasRealVideo && hasAnyImage
        let actualDuration = composition.duration
        
        print("SkipSlate: Composition built. Has real video: \(hasRealVideo), Has images: \(hasAnyImage), Image-only: \(isImageOnlyComposition)")
        print("SkipSlate: Composition duration from AVFoundation: \(CMTimeGetSeconds(actualDuration))s, calculated: \(CMTimeGetSeconds(totalDuration))s")
        
        // CRITICAL: Verify audio is actually embedded in the composition
        print("SkipSlate: ===== AUDIO VERIFICATION ======")
        let finalAudioTracks = composition.tracks(withMediaType: .audio)
        print("SkipSlate: Final composition has \(finalAudioTracks.count) audio track(s)")
        
        // Check if any segments should have had audio
        var segmentsWithAudio = 0
        var segmentsWithoutAudio = 0
        var clipsWithAudio: [String] = []
        for segment in enabledSegments {
            if let clip = project.clips.first(where: { $0.id == segment.sourceClipID }) {
                // Use hasAudioTrack property for accurate detection
                if clip.hasAudioTrack {
                    segmentsWithAudio += 1
                    clipsWithAudio.append("\(clip.fileName) (hasAudioTrack=true)")
                } else {
                    segmentsWithoutAudio += 1
                }
            }
        }
        
        // GUARANTEE: If segments should have audio, composition MUST have valid audio tracks
        var hasValidAudio = false
        var totalAudioDuration: Double = 0
        
        if finalAudioTracks.isEmpty {
            print("SkipSlate: ⚠⚠⚠ CRITICAL ERROR - Composition has NO audio tracks after building!")
            print("SkipSlate: Segments that should have audio (hasAudioTrack=true): \(segmentsWithAudio)")
            print("SkipSlate: Segments without audio: \(segmentsWithoutAudio)")
            print("SkipSlate: Clips that should have audio: \(clipsWithAudio)")
            
            if segmentsWithAudio > 0 {
                print("SkipSlate: ⚠⚠⚠ ERROR - Expected \(segmentsWithAudio) segments with audio, but composition has 0 audio tracks!")
                print("SkipSlate: Audio insertion must have failed. Check logs above for insertion errors.")
                print("SkipSlate: Possible causes:")
                print("SkipSlate:   1. Source assets don't actually have audio tracks")
                print("SkipSlate:   2. Audio track insertion failed silently")
                print("SkipSlate:   3. Asset loading failed before track access")
                
                // THROW ERROR if we expected audio but got none
                throw NSError(
                    domain: "PlayerViewModel",
                    code: -100,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Composition has no audio tracks but \(segmentsWithAudio) segments should have audio. Audio insertion failed.",
                        "segmentsWithAudio": segmentsWithAudio,
                        "clipsWithAudio": clipsWithAudio
                    ]
                )
            } else {
                print("SkipSlate: ✓ No audio expected (all segments are silent) - this is OK")
            }
        } else {
            // Verify each audio track has content
            for (index, track) in finalAudioTracks.enumerated() {
                let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                let trackStart = CMTimeGetSeconds(track.timeRange.start)
                let trackEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(track.timeRange))
                totalAudioDuration = max(totalAudioDuration, trackEnd)
                
                print("SkipSlate: Audio track \(index):")
                print("SkipSlate:   - Track ID: \(track.trackID)")
                print("SkipSlate:   - Duration: \(trackDuration)s")
                print("SkipSlate:   - TimeRange: \(trackStart)s - \(trackEnd)s")
                
                if trackDuration > 0 {
                    hasValidAudio = true
                    print("SkipSlate:   - ✓ Audio is embedded with \(trackDuration)s of content")
                } else {
                    print("SkipSlate:   - ⚠⚠⚠ WARNING: Track has ZERO duration - audio is NOT embedded!")
                }
            }
            
            print("SkipSlate: Total audio duration: \(totalAudioDuration)s")
            print("SkipSlate: Composition duration: \(CMTimeGetSeconds(actualDuration))s")
            
            // THROW ERROR if we expected audio but all tracks have zero duration
            if segmentsWithAudio > 0 && !hasValidAudio {
                print("SkipSlate: ⚠⚠⚠ CRITICAL ERROR - Expected audio but all tracks have zero duration!")
                throw NSError(
                    domain: "PlayerViewModel",
                    code: -101,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Composition has \(finalAudioTracks.count) audio track(s) but all have zero duration. Audio insertion failed.",
                        "audioTrackCount": finalAudioTracks.count,
                        "segmentsWithAudio": segmentsWithAudio
                    ]
                )
            } else if hasValidAudio {
                print("SkipSlate: ✓✓✓ SUCCESS - Audio IS embedded in the composition!")
            }
        }
        print("SkipSlate: ================================")
        
        // Sanity check: composition duration should match calculated duration
        if totalDuration > .zero && actualDuration.seconds == 0 {
            print("SkipSlate: WARNING - Composition duration is zero but we calculated \(CMTimeGetSeconds(totalDuration))s")
            print("SkipSlate: This may indicate that no track segments were successfully inserted.")
        } else if abs(CMTimeGetSeconds(actualDuration) - CMTimeGetSeconds(totalDuration)) > 0.1 {
            print("SkipSlate: WARNING - Duration mismatch: composition=\(CMTimeGetSeconds(actualDuration))s, calculated=\(CMTimeGetSeconds(totalDuration))s")
        } else {
            print("SkipSlate: Duration matches: \(CMTimeGetSeconds(actualDuration))s")
        }
        
        return composition
    }
    
    /// Creates a dummy video asset with black frames for image timing
    /// This creates a minimal video track that can be used to establish composition duration
    private func createDummyVideoAsset(duration: CMTime, timescale: Int32, renderSize: CGSize) async throws -> AVAsset {
        // For now, use a simpler approach: create a minimal composition with actual video track
        // We'll insert a very short video segment and extend it by inserting time ranges
        // Actually, the simplest: reuse an existing video clip if available, or create minimal frames
        
        // Create a temporary file URL for the dummy video
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        
        // Use AVAssetWriter to create a minimal black video
        guard let writer = try? AVAssetWriter(outputURL: tempFile, fileType: .mov) else {
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create asset writer"])
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(round(renderSize.width)),
            AVVideoHeightKey: Int(round(renderSize.height)),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
        
        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }
        
        writer.add(writerInput)
        
        guard writer.startWriting() else {
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Create frames at 30fps, but we'll create one frame per second to keep it minimal
        let frameDuration = CMTime(value: 1, timescale: timescale)
        var currentTime = CMTime.zero
        
        while currentTime < duration {
            guard let pixelBufferPool = adaptor.pixelBufferPool else {
                writer.cancelWriting()
                throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer pool"])
            }
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                writer.cancelWriting()
                throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
            }
            
            // Fill with black
            CVPixelBufferLockBaseAddress(buffer, [])
            let baseAddress = CVPixelBufferGetBaseAddress(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            if let base = baseAddress {
                memset(base, 0, bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            
            // Append the frame
            if writerInput.isReadyForMoreMediaData {
                if !adaptor.append(buffer, withPresentationTime: currentTime) {
                    writer.cancelWriting()
                    throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to append frame"])
                }
            }
            
            currentTime = CMTimeAdd(currentTime, frameDuration)
        }
        
        writerInput.markAsFinished()
        
        await writer.finishWriting()
        
        guard writer.status == .completed else {
            // Clean up on failure
            try? FileManager.default.removeItem(at: tempFile)
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Writing failed: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        
        // Verify the file exists and is readable before returning
        guard FileManager.default.fileExists(atPath: tempFile.path) else {
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dummy video file was not created"])
        }
        
        // Create the asset and verify it can be loaded
        let asset = AVURLAsset(url: tempFile)
        
        // Try to load duration to verify the asset is valid
        do {
            let assetDuration = try await asset.load(.duration)
            if !assetDuration.isValid || assetDuration.seconds == 0 {
                try? FileManager.default.removeItem(at: tempFile)
                throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dummy video asset has invalid duration"])
            }
            print("SkipSlate: Dummy video asset created successfully: \(tempFile.lastPathComponent), duration: \(assetDuration.seconds)s")
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            throw NSError(domain: "PlayerViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot load dummy video asset: \(error.localizedDescription)"])
        }
        
        return asset
    }
    
    private func createVideoComposition(
        for composition: AVMutableComposition,
        settings: ColorSettings
    ) -> AVMutableVideoComposition? {
        // Store settings globally for compositor access
        globalColorSettings = settings
        
        // Determine render size from project settings
        var renderSize = CGSize(width: 1920, height: 1080)
        if let project = currentProject {
            renderSize = CGSize(width: CGFloat(project.resolution.width), height: CGFloat(project.resolution.height))
            
            // Verify aspect ratio matches
            let presetRatio = Double(project.resolution.width) / Double(project.resolution.height)
            let targetRatio = project.aspectRatio.ratio
            let ratioDiff = abs(presetRatio - targetRatio)
            
            // If aspect ratio doesn't match, adjust dimensions to fit
            if ratioDiff > 0.01 {
                if presetRatio > targetRatio {
                    renderSize.height = CGFloat(Double(renderSize.width) / targetRatio)
                } else {
                    renderSize.width = CGFloat(Double(renderSize.height) * targetRatio)
                }
            }
        } else if let videoTrack = composition.tracks(withMediaType: .video).first {
            let naturalSize = videoTrack.naturalSize
            if naturalSize.width > 0 && naturalSize.height > 0 {
                renderSize = naturalSize
            }
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 24) // 24fps for frame-accurate timeline
        
        // Create instructions for each segment with transitions
        var instructions: [AVMutableVideoCompositionInstruction] = []
        
        if let videoTrack = composition.tracks(withMediaType: .video).first {
            // If we have image segments, use custom compositor
            if !imageSegmentsByTime.isEmpty {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
                
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
                
                // Use custom compositor that handles images
                videoComposition.customVideoCompositorClass = ImageAwareCompositor.self
            } else {
                // Standard video-only composition
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
                
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
                
                // Only use custom compositor if color correction is needed
                let needsColorCorrection = currentColorSettings.exposure != 0.0 || 
                                          currentColorSettings.contrast != 1.0 || 
                                          currentColorSettings.saturation != 1.0
                
                if needsColorCorrection {
                    videoComposition.customVideoCompositorClass = ColorCorrectionCompositor.self
                } else {
                    // No custom compositor - let AVFoundation handle it natively
                    videoComposition.customVideoCompositorClass = nil
                }
            }
        } else if !imageSegmentsByTime.isEmpty {
            // Images only - use custom compositor
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            instruction.layerInstructions = []
            instructions.append(instruction)
            
            videoComposition.customVideoCompositorClass = ImageAwareCompositor.self
        }
        
        videoComposition.instructions = instructions
        
        return videoComposition
    }
    
    private func setupTimeObserver() {
        // Remove existing observer if any
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        guard let player = player else {
            print("SkipSlate: Cannot setup time observer - player is nil")
            return
        }
        
        // Ensure we have a valid player item
        guard player.currentItem != nil else {
            print("SkipSlate: Cannot setup time observer - player item is nil")
            return
        }
        
        // Use 30fps update interval for smooth timer updates (30fps = ~0.033s)
        // This ensures the timer display updates smoothly during playback
        let interval = CMTime(value: 1, timescale: 30) // Exactly 1/30 second = 30fps
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Update current time - we're already on main queue, so update directly
            let timeInSeconds = CMTimeGetSeconds(time)
            if timeInSeconds.isFinite && !timeInSeconds.isNaN && timeInSeconds >= 0 {
                // Update directly since we're already on main queue
                // This ensures the @Published property triggers view updates
                self.currentTime = timeInSeconds
            }
        }
        
        print("SkipSlate: Time observer set up with interval: \(CMTimeGetSeconds(interval))s")
        
        print("SkipSlate: Time observer setup complete")
        
        // Also observe player item status to ensure it's ready
        if let playerItem = playerItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidReachEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        }
        
        // Observe rate changes to update isPlaying
        player.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
    }
    
    func play() {
        guard let player = player else {
            print("SkipSlate: Cannot play - player is nil")
            return
        }
        
        guard let item = player.currentItem else {
            print("SkipSlate: Cannot play - player item is nil")
            return
        }
        
        // Check if video is at the end - if so, restart from beginning
        let isAtEnd = duration > 0 && currentTime >= duration - 0.1 // Small tolerance for floating point comparison
        
        if isAtEnd {
            print("SkipSlate: Video is at end, restarting from beginning")
            // Seek to start first, then play
            seek(to: 0.0) { [weak self] completed in
                guard let self = self, completed else { return }
                self.playAfterSeek()
            }
        } else {
            playAfterSeek()
        }
    }
    
    private func playAfterSeek() {
        guard let player = player else {
            print("SkipSlate: Cannot play - player is nil")
            return
        }
        
        guard let item = player.currentItem else {
            print("SkipSlate: Cannot play - player item is nil")
            return
        }
        
        // Debug: log audio tracks on the current item
        let tracks = item.tracks
        let audioTracks = tracks.filter { $0.assetTrack?.mediaType == .audio }
        print("SkipSlate: play() – PlayerItem has \(tracks.count) total tracks, \(audioTracks.count) audio tracks")
        
        // Log audio mix status
        if let audioMix = item.audioMix {
            print("SkipSlate: play() – PlayerItem has audioMix with \(audioMix.inputParameters.count) input parameter(s)")
            for (index, param) in audioMix.inputParameters.enumerated() {
                // AVAudioMixInputParameters doesn't expose track directly, but we can log the parameter
                print("SkipSlate: play() – Audio mix param \(index): present")
            }
        } else {
            print("SkipSlate: play() – WARNING: PlayerItem has NO audioMix!")
        }
        
        // Ensure volume is set
        player.volume = 1.0
        player.isMuted = false
        
        player.play()
        
        // Update isPlaying based on actual rate
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = player.rate > 0
            print("SkipSlate: Player started, rate: \(player.rate), isPlaying: \(self?.isPlaying ?? false), volume: \(player.volume), muted: \(player.isMuted)")
        }
    }
    
    func pause() {
        player?.pause()
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            print("SkipSlate: Player paused, isPlaying: false")
        }
    }
    
    func seek(to time: Double, precise: Bool = false, completion: ((Bool) -> Void)? = nil) {
        // Use 24fps timescale for frame-accurate positioning
        // 24fps = 1/24 second per frame = timescale 24
        let timescale: Int32 = precise ? 24 : 600  // 24fps for precise, 600 for standard
        let cmTime = CMTime(seconds: time, preferredTimescale: timescale)
        
        if precise {
            // Precise seeking with zero tolerance for frame-accurate positioning at 24fps
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                if completed {
                    DispatchQueue.main.async {
                        // Update immediately for frame-accurate positioning
                        self?.currentTime = time
                    }
                }
                completion?(completed)
            }
        } else {
            // Standard seeking with small tolerance (1 frame at 24fps = ~0.04167s)
            let tolerance = CMTime(value: 1, timescale: 24) // 1 frame tolerance at 24fps
            player?.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] completed in
                if completed {
                    DispatchQueue.main.async {
                        self?.currentTime = time
                    }
                }
                completion?(completed)
            }
        }
    }
    
    @objc private func playerItemDidReachEnd() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
        }
    }
    
    // MARK: - Debug Helper: Play First Clip Raw
    
    /// Debug helper to play the first clip directly without composition
    /// This helps isolate whether the issue is in composition or player view
    func playFirstClipRawForDebug() {
        guard let project = currentProject,
              let firstClip = project.clips.first else {
            print("SkipSlate: DEBUG - No clips available for raw playback")
            return
        }
        
        print("SkipSlate: DEBUG - Playing first clip raw: \(firstClip.fileName)")
        
        // Pause current playback
        pause()
        
        // Create AVAsset from clip URL
        let asset = AVURLAsset(url: firstClip.url)
        
        // Create player item directly from asset (no composition, no videoComposition, no audioMix)
        let item = AVPlayerItem(asset: asset)
        
        // Remove old observer if exists
        if let oldItem = self.playerItem {
            oldItem.removeObserver(self, forKeyPath: "status", context: &playerItemStatusContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        }
        
        // Add observer for debug item
        item.addObserver(
            self,
            forKeyPath: "status",
            options: [.initial, .new],
            context: &playerItemStatusContext
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        
        self.playerItem = item
        
        // Use the same player instance - just replace the item
        guard let player = player else {
            print("SkipSlate: DEBUG - ERROR: player is nil, cannot play raw clip")
            return
        }
        
        // Verify item has audio tracks before playing
        let itemTracks = item.tracks
        let itemAudioTracks = itemTracks.filter { $0.assetTrack?.mediaType == .audio }
        print("SkipSlate: DEBUG - Raw player item has \(itemTracks.count) total tracks, \(itemAudioTracks.count) audio tracks")
        
        if itemAudioTracks.isEmpty {
            print("SkipSlate: DEBUG - ⚠⚠⚠ WARNING - Raw asset has NO audio tracks! This indicates the source file is silent.")
        } else {
            print("SkipSlate: DEBUG - ✓ Raw asset has audio tracks - if you hear sound, the issue is in composition/mixing")
        }
        
        player.volume = 1.0
        player.isMuted = false
        player.replaceCurrentItem(with: item)
        
        // Load duration
        Task {
            do {
                let assetDuration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(assetDuration)
                    print("SkipSlate: DEBUG - Raw clip duration: \(self.duration)s")
                }
            } catch {
                print("SkipSlate: DEBUG - Failed to load asset duration: \(error)")
            }
        }
        
        // Play
        play()
        print("SkipSlate: DEBUG - Started playing raw clip")
    }
    
    // MARK: - KVO and Notification Handlers
    
    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem,
           let error = item.error {
            print("SkipSlate: PlayerItem failed to play to end, error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
            }
        } else {
            print("SkipSlate: PlayerItem failed to play to end for unknown reason")
        }
    }
    
    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        print("SkipSlate: PlayerItem reached end of playback")
        // Optionally loop or pause
        isPlaying = false
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // Handle player item status
        if context == &playerItemStatusContext {
            if keyPath == "status",
               let item = object as? AVPlayerItem {
                switch item.status {
                case .readyToPlay:
                    print("SkipSlate: PlayerItem status = readyToPlay")
                    print("SkipSlate: PlayerItem duration: \(CMTimeGetSeconds(item.duration))s")
                    print("SkipSlate: PlayerItem has video composition: \(item.videoComposition != nil)")
                    if let videoComposition = item.videoComposition {
                        print("SkipSlate: Video composition render size: \(videoComposition.renderSize)")
                        print("SkipSlate: Video composition instructions count: \(videoComposition.instructions.count)")
                        if let firstInstruction = videoComposition.instructions.first as? AVMutableVideoCompositionInstruction {
                            print("SkipSlate: First instruction time range: \(CMTimeGetSeconds(firstInstruction.timeRange.start))s - \(CMTimeGetSeconds(CMTimeRangeGetEnd(firstInstruction.timeRange)))s")
                            print("SkipSlate: First instruction layer instructions count: \(firstInstruction.layerInstructions.count)")
                        }
                    }
                    // Check tracks
                    let tracks = item.tracks
                    let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
                    print("SkipSlate: PlayerItem has \(tracks.count) tracks, \(videoTracks.count) video tracks")
                case .failed:
                    print("SkipSlate: PlayerItem status = FAILED")
                    if let error = item.error {
                        print("SkipSlate: Error: \(error.localizedDescription)")
                        if let nsError = error as NSError? {
                            print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code)")
                            print("SkipSlate: Error userInfo: \(nsError.userInfo)")
                        }
                    } else {
                        print("SkipSlate: Error is nil")
                    }
                case .unknown:
                    print("SkipSlate: PlayerItem status = unknown")
                @unknown default:
                    print("SkipSlate: PlayerItem status = unknown future case")
                }
                return
            }
        }
        
        // Handle player rate changes
        if keyPath == "rate" {
            DispatchQueue.main.async {
                if let player = object as? AVPlayer {
                    self.isPlaying = player.rate > 0
                    print("SkipSlate: Player rate changed to \(player.rate), isPlaying: \(self.isPlaying)")
                }
            }
        }
    }
    
    deinit {
        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        
        // Remove player item observers
        if let item = playerItem {
            item.removeObserver(self, forKeyPath: "status", context: &playerItemStatusContext)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        
        // Remove player rate observer
        player?.removeObserver(self, forKeyPath: "rate")
        
        // Remove all notifications
        NotificationCenter.default.removeObserver(self)
        
        print("SkipSlate: PlayerViewModel deinit")
    }
}

