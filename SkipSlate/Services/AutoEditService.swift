//
//  AutoEditService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  On-device auto-edit service using real audio analysis
//
//  MODULE: Auto Edit
//  - This service generates segments based on audio/video analysis
//  - It does NOT modify PlayerViewModel or composition directly
//  - It returns segments to ProjectViewModel, which handles composition rebuild
//  - Communication: AutoEditService → ProjectViewModel.runAutoEdit() → segments added to project
//

import Foundation
import AVFoundation

enum AutoEditError: Error {
    case noUsableAudio
    case noClips
    case analysisFailed(String)
}

class AutoEditService {
    static let shared = AutoEditService()
    
    private let audioEngine = AudioAnalysisEngine()
    private let frameAnalysis = FrameAnalysisService.shared
    
    private init() {}
    
    // MARK: - Main Entry Point
    
    func generateSegments(
        for project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings,
        progressCallback: ((String) -> Void)? = nil,
        allAnalyzedSegmentsCallback: (([Segment]) -> Void)? = nil
    ) async throws -> [Segment] {
        // CRITICAL: Validate inputs to prevent crashes
        guard !project.clips.isEmpty else {
            print("SkipSlate: AutoEdit - No clips in project")
            throw AutoEditError.noClips
        }
        
        // Validate assets exist for all clips
        let missingAssets = project.clips.filter { assetsByClipID[$0.id] == nil }
        if !missingAssets.isEmpty {
            print("SkipSlate: AutoEdit - Warning: \(missingAssets.count) clips missing assets, will skip them")
        }
        
        // CRITICAL: Wrap all operations in error handling
        do {
            switch project.type {
            case .podcast:
                return try await autoEditPodcast(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings
                )
            case .documentary:
                return try await autoEditDocumentary(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings
                )
            case .musicVideo:
                return try await autoEditMusicVideo(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings
                )
            case .danceVideo:
                return try await autoEditDanceVideo(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings
                )
            case .highlightReel:
                return try await autoEditHighlightReel(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings,
                    progressCallback: progressCallback,
                    allAnalyzedSegmentsCallback: allAnalyzedSegmentsCallback
                )
            case .commercials:
                // Commercials use similar logic to highlight reels
                return try await autoEditHighlightReel(
                    project: project,
                    assetsByClipID: assetsByClipID,
                    settings: settings,
                    progressCallback: progressCallback,
                    allAnalyzedSegmentsCallback: allAnalyzedSegmentsCallback
                )
            }
        } catch let error as AutoEditError {
            // Re-throw known errors
            throw error
        } catch {
            // CRITICAL: Catch all other errors and provide meaningful message
            let errorMessage = "Auto-edit failed: \(error.localizedDescription)"
            print("SkipSlate: AutoEdit - CRITICAL ERROR: \(errorMessage)")
            print("SkipSlate: AutoEdit - Error details: \(error)")
            throw AutoEditError.analysisFailed(errorMessage)
        }
    }
    
    // MARK: - Shared Helpers
    
    private func envelopeForClip(
        _ clip: MediaClip,
        assetsByClipID: [UUID: AVAsset]
    ) async throws -> AudioAnalysisEngine.Envelope? {
        // CRITICAL: Validate clip type
        guard clip.type == .videoWithAudio || clip.type == .audioOnly else {
            return nil
        }
        
        // CRITICAL: Validate asset exists
        guard let asset = assetsByClipID[clip.id] else {
            print("SkipSlate: AutoEdit - Warning: Asset not found for clip \(clip.fileName)")
            return nil
        }
        
        // CRITICAL: Wrap in error handling with timeout
        do {
            return try await withTimeout(seconds: 30) {
                try await self.audioEngine.buildEnvelope(for: asset)
            }
        } catch {
            print("SkipSlate: AutoEdit - Failed to build envelope for clip \(clip.fileName): \(error)")
            // Return nil instead of crashing - allows processing to continue
            return nil
        }
    }
    
    // CRITICAL: Timeout helper to prevent hanging operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "AutoEditService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out after \(seconds) seconds"])
            }
            
            guard let result = try await group.next() else {
                throw NSError(domain: "AutoEditService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed"])
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private func totalAvailableDuration(
        for project: Project,
        assetsByClipID: [UUID: AVAsset]
    ) -> Double {
        var total: Double = 0
        for clip in project.clips {
            if clip.type == .videoWithAudio || clip.type == .videoOnly {
                total += clip.duration
            } else if clip.type == .audioOnly {
                total += clip.duration
            }
        }
        return total
    }
    
    func limitSegmentsToTargetLength(
        _ segments: [Segment],
        targetLength: Double?
    ) -> [Segment] {
        guard let target = targetLength else {
            return segments
        }
        
        var result: [Segment] = []
        var accumulated: Double = 0
        
        for segment in segments {
            let segmentDuration = segment.duration
            let remaining = target - accumulated
            
            if remaining <= 0 {
                break
            }
            
            if accumulated + segmentDuration <= target {
                result.append(segment)
                accumulated += segmentDuration
            } else {
                // Trim last segment
                var trimmed = segment
                trimmed.sourceEnd = trimmed.sourceStart + remaining
                result.append(trimmed)
                break
            }
        }
        
        return result
    }
    
    // MARK: - Podcast Mode
    
    private func autoEditPodcast(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings
    ) async throws -> [Segment] {
        // Get pace parameters
        let (minSpeech, minSilence, thresholdDB) = paceParameters(for: settings.pace, mode: .podcast)
        
        var allSegments: [Segment] = []
        
        // Process each clip - use clip's pre-assigned colorIndex
        for clip in project.clips {
            guard let asset = assetsByClipID[clip.id] else { continue }
            
            // Use the clip's pre-assigned colorIndex from import
            let clipColorIndex = clip.colorIndex
            
            if let envelope = try await envelopeForClip(clip, assetsByClipID: assetsByClipID) {
                // Detect speech segments
                var speechSegments = audioEngine.detectSpeechSegments(
                    envelope: envelope,
                    minSpeechDuration: minSpeech,
                    minSilenceDuration: minSilence,
                    silenceThresholdDB: thresholdDB
                )
                
                // Filter out director/shooter voices (off-camera, quieter speech)
                speechSegments = try await filterOffCameraVoices(
                    speechSegments: speechSegments,
                    envelope: envelope,
                    asset: asset,
                    clip: clip
                )
                
                // If video clip, prioritize high-quality shots
                if clip.type == .videoWithAudio || clip.type == .videoOnly {
                    speechSegments = try await prioritizeHighQualityShots(
                        speechSegments: speechSegments,
                        asset: asset,
                        settings: settings
                    )
                }
                
                // Apply style-specific adjustments
                let adjustedSegments = applyPodcastStyle(
                    speechSegments,
                    style: settings.style,
                    clip: clip
                )
                
                // Convert to Segment objects - all segments from this clip use the same color
                for speechSeg in adjustedSegments {
                    let segment = Segment(
                        id: UUID(),
                        sourceClipID: clip.id,
                        sourceStart: speechSeg.startTime,
                        sourceEnd: speechSeg.endTime,
                        enabled: true,
                        colorIndex: clipColorIndex
                    )
                    allSegments.append(segment)
                }
            }
        }
        
        // Handle image-only clips
        if allSegments.isEmpty {
            return try createImageSegments(for: project)
        }
        
        // Limit to target length
        return limitSegmentsToTargetLength(allSegments, targetLength: settings.targetLengthSeconds)
    }
    
    // MARK: - Documentary Mode
    
    private func autoEditDocumentary(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings
    ) async throws -> [Segment] {
        // Documentary uses slightly longer minimums
        let (minSpeech, minSilence, thresholdDB) = paceParameters(for: settings.pace, mode: .documentary)
        
        var allSegments: [Segment] = []
        
        // OPTIMIZATION: Process audio analysis in parallel (safe - doesn't use CIContext)
        print("SkipSlate: AutoEditService - Processing \(project.clips.count) clips for audio analysis (parallel)")
        
        // Build all envelopes in parallel
        var envelopesByClipID: [UUID: AudioAnalysisEngine.Envelope] = [:]
        await withTaskGroup(of: (UUID, AudioAnalysisEngine.Envelope?).self) { group in
            for clip in project.clips {
                guard let asset = assetsByClipID[clip.id] else { continue }
                
                group.addTask { [weak self] in
                    guard let self = self else { return (clip.id, nil) }
                    do {
                        if let envelope = try await self.envelopeForClip(clip, assetsByClipID: assetsByClipID) {
                            return (clip.id, envelope)
                        }
                    } catch {
                        print("SkipSlate: Error building envelope for \(clip.fileName): \(error)")
                    }
                    return (clip.id, nil)
                }
            }
            
            for await (clipID, envelope) in group {
                if let envelope = envelope {
                    envelopesByClipID[clipID] = envelope
                }
            }
        }
        
        print("SkipSlate: AutoEditService - Built \(envelopesByClipID.count) audio envelopes in parallel")
        
        // Now process each clip sequentially (for video frame analysis safety)
        for clip in project.clips {
            guard let asset = assetsByClipID[clip.id],
                  let envelope = envelopesByClipID[clip.id] else { continue }
            
            // Use the clip's pre-assigned colorIndex from import
            let clipColorIndex = clip.colorIndex
            
            var speechSegments = audioEngine.detectSpeechSegments(
                envelope: envelope,
                minSpeechDuration: minSpeech,
                minSilenceDuration: minSilence,
                silenceThresholdDB: thresholdDB
            )
            
            // Filter out director/shooter voices
            speechSegments = try await filterOffCameraVoices(
                speechSegments: speechSegments,
                envelope: envelope,
                asset: asset,
                clip: clip
            )
            
            // Prioritize high-quality shots for video clips (sequential - uses CIContext)
            if clip.type == .videoWithAudio || clip.type == .videoOnly {
                speechSegments = try await prioritizeHighQualityShots(
                    speechSegments: speechSegments,
                    asset: asset,
                    settings: settings
                )
            }
            
            // Split long segments for soundbites
            let soundbites = splitLongSegments(speechSegments, maxLength: 30.0)
            
            // All segments from this clip use the same color
            for speechSeg in soundbites {
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: clip.id,
                    sourceStart: speechSeg.startTime,
                    sourceEnd: speechSeg.endTime,
                    enabled: true,
                    colorIndex: clipColorIndex
                )
                allSegments.append(segment)
            }
        }
        
        if allSegments.isEmpty {
            return try createImageSegments(for: project)
        }
        
        return limitSegmentsToTargetLength(allSegments, targetLength: settings.targetLengthSeconds)
    }
    
    // MARK: - Music Video Mode
    
    private func autoEditMusicVideo(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings
    ) async throws -> [Segment] {
        // Find main audio reference
        var audioClip: MediaClip?
        var audioAsset: AVAsset?
        
        // Prefer audio-only clip marked as music
        for clip in project.clips where clip.type == .audioOnly {
            audioClip = clip
            audioAsset = assetsByClipID[clip.id]
            break
        }
        
        // Otherwise use first video clip's audio
        if audioClip == nil {
            for clip in project.clips where clip.type == .videoWithAudio {
                audioClip = clip
                audioAsset = assetsByClipID[clip.id]
                break
            }
        }
        
        // Separate video clips and image clips
        let videoClips = project.clips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly }
        let imageClips = project.clips.filter { $0.type == .image }
        
        // If we have no visual content, return image segments
        if videoClips.isEmpty && imageClips.isEmpty {
            throw AutoEditError.noUsableAudio
        }
        
        // If we have audio, use beat detection
        if let clip = audioClip, let asset = audioAsset {
            // Build envelope and detect beats
            let envelope = try await audioEngine.buildEnvelope(for: asset)
            
            let (minSpacing, sensitivity) = beatParameters(for: settings.style, mode: .musicVideo)
            let beatPeaks = audioEngine.detectBeatPeaks(
                envelope: envelope,
                minBeatSpacing: minSpacing,
                sensitivity: sensitivity
            )
            
            print("SkipSlate: Detected \(beatPeaks.count) beat peaks for mashup")
            print("SkipSlate: Available clips - video: \(videoClips.count), images: \(imageClips.count)")
            
            // If no beats detected, fall back to mashup
            if beatPeaks.isEmpty {
                print("SkipSlate: No beats detected, creating mashup without beat sync")
                return try createMashupSegments(videoClips: videoClips, imageClips: imageClips, targetLength: settings.targetLengthSeconds)
            }
            
            // Create mashup: alternate between video and images at beats
            var segments: [Segment] = []
            var videoClipIndex = 0
            var imageClipIndex = 0
            
            var previousTime: Double = 0
            var useVideo = !videoClips.isEmpty // Start with video if available, otherwise images
            
            print("SkipSlate: Starting with useVideo=\(useVideo), videoClips.isEmpty=\(videoClips.isEmpty), imageClips.isEmpty=\(imageClips.isEmpty)")
            
            for peak in beatPeaks {
                if peak > previousTime {
                    let duration = peak - previousTime
                    if duration >= 0.5 && duration <= 4.0 {
                        if useVideo && !videoClips.isEmpty {
                            let clip = videoClips[videoClipIndex % videoClips.count]
                            let clipDuration = min(duration, clip.duration)
                            if clipDuration > 0.3 {
                                let segment = Segment(
                                    id: UUID(),
                                    sourceClipID: clip.id,
                                    sourceStart: 0.0, // Start from beginning of clip
                                    sourceEnd: clipDuration,
                                    enabled: true,
                                    colorIndex: clip.colorIndex // Use clip's assigned color
                                )
                                segments.append(segment)
                                print("SkipSlate: Added video segment from '\(clip.fileName)'")
                                videoClipIndex += 1
                            }
                        } else if !imageClips.isEmpty {
                            let clip = imageClips[imageClipIndex % imageClips.count]
                            let segment = Segment(
                                id: UUID(),
                                sourceClipID: clip.id,
                                sourceStart: 0.0,
                                sourceEnd: min(duration, 3.0), // Images default to 3s
                                enabled: true,
                                colorIndex: clip.colorIndex // Use clip's assigned color
                            )
                            segments.append(segment)
                            print("SkipSlate: Added image segment from '\(clip.fileName)'")
                            imageClipIndex += 1
                        } else {
                            print("SkipSlate: Warning - No visual clips available for segment at peak \(peak)")
                        }
                        useVideo.toggle() // Alternate
                    }
                    previousTime = peak
                }
            }
            
            // Add final segment if we haven't reached the end
            let audioDuration = clip.duration
            if previousTime < audioDuration {
                let remaining = audioDuration - previousTime
                if remaining > 0.3 {
                    if useVideo && !videoClips.isEmpty {
                        let clip = videoClips[videoClipIndex % videoClips.count]
                        let segment = Segment(
                            id: UUID(),
                            sourceClipID: clip.id,
                            sourceStart: 0.0,
                            sourceEnd: min(remaining, clip.duration),
                            enabled: true,
                            colorIndex: clip.colorIndex // Use clip's assigned color
                        )
                        segments.append(segment)
                        print("SkipSlate: Added final video segment")
                    } else if !imageClips.isEmpty {
                        let clip = imageClips[imageClipIndex % imageClips.count]
                        let segment = Segment(
                            id: UUID(),
                            sourceClipID: clip.id,
                            sourceStart: 0.0,
                            sourceEnd: min(remaining, 3.0),
                            enabled: true,
                            colorIndex: clip.colorIndex // Use clip's assigned color
                        )
                        segments.append(segment)
                        print("SkipSlate: Added final image segment")
                    }
                }
            }
            
            if !segments.isEmpty {
                print("SkipSlate: Created \(segments.count) segments from beats (video: \(videoClips.count), images: \(imageClips.count))")
                return limitSegmentsToTargetLength(segments, targetLength: settings.targetLengthSeconds)
            } else {
                print("SkipSlate: No segments created from beats, falling back to mashup")
            }
        }
        
        // Fallback: create mashup without beat detection (use all available visual content)
        print("SkipSlate: Creating mashup without beat detection")
        return try createMashupSegments(videoClips: videoClips, imageClips: imageClips, targetLength: settings.targetLengthSeconds)
    }
    
    // MARK: - Dance Video Mode
    
    private func autoEditDanceVideo(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings
    ) async throws -> [Segment] {
        // Similar to music video
        var audioClip: MediaClip?
        var audioAsset: AVAsset?
        
        for clip in project.clips where clip.type == .audioOnly {
            audioClip = clip
            audioAsset = assetsByClipID[clip.id]
            break
        }
        
        if audioClip == nil {
            for clip in project.clips where clip.type == .videoWithAudio {
                audioClip = clip
                audioAsset = assetsByClipID[clip.id]
                break
            }
        }
        
        guard let clip = audioClip, let asset = audioAsset else {
            return try createImageSegments(for: project)
        }
        
        let envelope = try await audioEngine.buildEnvelope(for: asset)
        
        let (minSpacing, sensitivity) = beatParameters(for: settings.style, mode: .danceVideo)
        let beatPeaks = audioEngine.detectBeatPeaks(
            envelope: envelope,
            minBeatSpacing: minSpacing,
            sensitivity: sensitivity
        )
        
        guard let videoClip = project.clips.first(where: { $0.type == .videoWithAudio || $0.type == .videoOnly }) else {
            return try createImageSegments(for: project)
        }
        
        var segments: [Segment] = []
        
        var previousTime: Double = 0
        for peak in beatPeaks {
            if peak > previousTime {
                let duration = peak - previousTime
                if duration >= 0.5 && duration <= 4.0 {
                    let segment = Segment(
                        id: UUID(),
                        sourceClipID: videoClip.id,
                        sourceStart: previousTime,
                        sourceEnd: peak,
                        enabled: true,
                        colorIndex: videoClip.colorIndex // Use clip's assigned color
                    )
                    segments.append(segment)
                }
                previousTime = peak
            }
        }
        
        if previousTime < videoClip.duration {
            let segment = Segment(
                id: UUID(),
                sourceClipID: videoClip.id,
                sourceStart: previousTime,
                sourceEnd: videoClip.duration,
                enabled: true,
                colorIndex: videoClip.colorIndex // Use clip's assigned color
            )
            segments.append(segment)
        }
        
        if segments.isEmpty {
            return try createImageSegments(for: project)
        }
        
        return limitSegmentsToTargetLength(segments, targetLength: settings.targetLengthSeconds)
    }
    
    // MARK: - Helper Functions
    
    private func paceParameters(for pace: Pace, mode: ProjectType) -> (minSpeech: Double, minSilence: Double, thresholdDB: Float) {
        switch (pace, mode) {
        case (.relaxed, .podcast):
            return (1.0, 0.50, -30.0)
        case (.normal, .podcast):
            return (0.7, 0.35, -25.0)
        case (.tight, .podcast):
            return (0.4, 0.25, -20.0)
        case (.relaxed, .documentary):
            return (1.2, 0.50, -30.0)
        case (.normal, .documentary):
            return (1.0, 0.35, -25.0)
        case (.tight, .documentary):
            return (0.7, 0.25, -20.0)
        default:
            return (0.7, 0.35, -25.0)
        }
    }
    
    private func beatParameters(for style: AutoEditStyle, mode: ProjectType) -> (minSpacing: Double, sensitivity: Float) {
        // Handle highlight reel mode
        if mode == .highlightReel {
            switch style {
            case .quickCuts:
                return (0.10, 0.8) // Very fast cuts
            case .dynamicHighlights:
                return (0.15, 0.7) // Medium-fast
            case .storyArc:
                return (0.25, 0.6) // Slightly slower for narrative
            default:
                return (0.15, 0.7) // Default for highlight reel
            }
        }
        
        // Other modes
        switch style {
        case .performance, .fullPerformances:
            return (0.33, 0.5)
        case .montageMV, .danceHighlights:
            return (0.20, 0.6)
        case .beatHeavyMV, .beatCutsDance:
            return (0.15, 0.7)
        default:
            return (0.25, 0.6)
        }
    }
    
    private func applyPodcastStyle(
        _ segments: [AudioAnalysisEngine.SpeechSegment],
        style: AutoEditStyle,
        clip: MediaClip
    ) -> [AudioAnalysisEngine.SpeechSegment] {
        switch style {
        case .clipHighlights:
            // Split long segments into 10-30s pieces
            var result: [AudioAnalysisEngine.SpeechSegment] = []
            for seg in segments {
                let duration = seg.endTime - seg.startTime
                if duration > 30.0 {
                    // Split into ~20s chunks
                    var currentStart = seg.startTime
                    while currentStart < seg.endTime {
                        let chunkEnd = min(currentStart + 20.0, seg.endTime)
                        result.append(AudioAnalysisEngine.SpeechSegment(
                            startTime: currentStart,
                            endTime: chunkEnd
                        ))
                        currentStart = chunkEnd
                    }
                } else {
                    result.append(seg)
                }
            }
            return result
        default:
            return segments
        }
    }
    
    // MARK: - Shot Quality Analysis and Voice Filtering
    
    /// Prioritize high-quality shots based on multiple factors (framing, lighting, motion, stability)
    /// Scores segments and keeps the best ones based on quality threshold
    private func prioritizeHighQualityShots(
        speechSegments: [AudioAnalysisEngine.SpeechSegment],
        asset: AVAsset,
        settings: AutoEditSettings
    ) async throws -> [AudioAnalysisEngine.SpeechSegment] {
        // CRITICAL: Validate inputs
        guard !speechSegments.isEmpty else {
            print("SkipSlate: AutoEdit - No speech segments to prioritize")
            return []
        }
        
        print("SkipSlate: Analyzing shots for quality...")
        
        // CRITICAL: Wrap frame analysis in error handling
        let frameAnalyses: [FrameAnalysisService.FrameAnalysis]
        do {
            frameAnalyses = try await withTimeout(seconds: 120) {
                try await self.frameAnalysis.analyzeFrames(from: asset, sampleInterval: 0.5)
            }
        } catch {
            print("SkipSlate: AutoEdit - Error analyzing frames: \(error), using all segments as fallback")
            // Return original segments if analysis fails - better than crashing
            return speechSegments
        }
        
        // CRITICAL: Validate we got analyses
        guard !frameAnalyses.isEmpty else {
            print("SkipSlate: AutoEdit - No frame analyses returned, using all segments")
            return speechSegments
        }
        
        // Score each speech segment based on shot quality
        var scoredSegments: [(segment: AudioAnalysisEngine.SpeechSegment, score: Float)] = []
        
        for speechSeg in speechSegments {
            // CRITICAL: Validate segment times
            guard speechSeg.startTime >= 0 && speechSeg.endTime > speechSeg.startTime else {
                print("SkipSlate: AutoEdit - Invalid segment times: \(speechSeg.startTime)-\(speechSeg.endTime)s, skipping")
                continue
            }
            
            // CRITICAL: Safe scoring with error handling
            let score: Float
            do {
                score = frameAnalysis.scoreTimeRange(
                    start: speechSeg.startTime,
                    end: speechSeg.endTime,
                    analyses: frameAnalyses
                )
            } catch {
                print("SkipSlate: AutoEdit - Error scoring segment: \(error), using default score")
                score = 0.5 // Default score if scoring fails
            }
            
            scoredSegments.append((speechSeg, score))
            print("SkipSlate: Segment \(speechSeg.startTime)-\(speechSeg.endTime)s scored: \(score)")
        }
        
        // CRITICAL: Ensure we have scored segments
        guard !scoredSegments.isEmpty else {
            print("SkipSlate: AutoEdit - No valid scored segments, returning original")
            return speechSegments
        }
        
        // Sort by score (highest first)
        scoredSegments.sort { $0.score > $1.score }
        
        // CRITICAL: Much stricter quality filtering
        // Filter by quality threshold from settings, but enforce minimum of 0.5
        let threshold = max(settings.qualityThreshold, 0.5) // Minimum 0.5 quality score
        let filteredSegments: [AudioAnalysisEngine.SpeechSegment]
        
        // Filter by threshold - only keep high-quality shots
        filteredSegments = scoredSegments
            .filter { $0.score >= threshold }
            .map { $0.segment }
        
        print("SkipSlate: Filtered \(speechSegments.count) segments to \(filteredSegments.count) using quality threshold \(threshold) (minimum enforced: 0.5)")
        
        // Additional filtering: Check for faces in the filtered segments
        // Analyze frames for the filtered segments to ensure they have faces
        var finalSegments: [AudioAnalysisEngine.SpeechSegment] = []
        for seg in filteredSegments {
            // Check if this time range has faces
            let hasFaces = frameAnalyses.contains { analysis in
                analysis.timestamp >= seg.startTime && 
                analysis.timestamp <= seg.endTime && 
                analysis.hasFace
            }
            
            // Also check if it's a landscape shot
            let isLandscape = frameAnalyses.contains { analysis in
                analysis.timestamp >= seg.startTime && 
                analysis.timestamp <= seg.endTime && 
                analysis.isLandscapeShot
            }
            
            // Require faces OR landscape (no random ground-level shots)
            if hasFaces || isLandscape {
                finalSegments.append(seg)
            } else {
                print("SkipSlate: Rejected segment \(seg.startTime)-\(seg.endTime)s - no faces and not landscape")
            }
        }
        
        print("SkipSlate: Final filtered segments: \(finalSegments.count) (had faces or were landscape)")
        return finalSegments
    }
    
    /// Filter speech segments to prefer those where faces are well-framed
    /// If no well-framed faces are found, returns original segments (fallback)
    private func filterByFaceDetection(
        speechSegments: [AudioAnalysisEngine.SpeechSegment],
        asset: AVAsset
    ) async throws -> [AudioAnalysisEngine.SpeechSegment] {
        print("SkipSlate: Analyzing frames for face detection...")
        
        // Analyze frames from the video
        let frameAnalyses = try await frameAnalysis.analyzeFrames(from: asset, sampleInterval: 0.5)
        
        // Check if we have any faces at all
        let hasAnyFaces = frameAnalyses.contains { $0.hasFace }
        
        if !hasAnyFaces {
            print("SkipSlate: No faces detected in video - using all segments (may be B-roll or landscape)")
            return speechSegments
        }
        
        // Find well-framed ranges - use more lenient thresholds
        let wellFramedRanges = frameAnalysis.findWellFramedRanges(
            analyses: frameAnalyses,
            minFramingScore: 0.4, // Lowered from 0.6 to be more lenient
            minDuration: 0.3      // Lowered from 0.5 to catch shorter good moments
        )
        
        print("SkipSlate: Found \(wellFramedRanges.count) well-framed ranges")
        
        // If no well-framed ranges found, but we have faces, use segments with any face presence
        if wellFramedRanges.isEmpty {
            print("SkipSlate: No perfectly framed ranges found, but faces detected - using segments with any face presence")
            
            // Find ranges where ANY face is present (even if not perfectly centered)
            var faceRanges: [CMTimeRange] = []
            var currentRangeStart: Double?
            
            for analysis in frameAnalyses {
                if analysis.hasFace {
                    if currentRangeStart == nil {
                        currentRangeStart = analysis.timestamp
                    }
                } else {
                    if let start = currentRangeStart {
                        let duration = analysis.timestamp - start
                        if duration >= 0.3 {
                            faceRanges.append(CMTimeRange(
                                start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: duration, preferredTimescale: 600)
                            ))
                        }
                        currentRangeStart = nil
                    }
                }
            }
            
            // Close final range
            if let start = currentRangeStart, let lastAnalysis = frameAnalyses.last {
                let duration = lastAnalysis.timestamp - start
                if duration >= 0.3 {
                    faceRanges.append(CMTimeRange(
                        start: CMTime(seconds: start, preferredTimescale: 600),
                        duration: CMTime(seconds: duration, preferredTimescale: 600)
                    ))
                }
            }
            
            // Filter segments to overlap with face ranges
            var filtered: [AudioAnalysisEngine.SpeechSegment] = []
            for speechSeg in speechSegments {
                let speechRange = CMTimeRange(
                    start: CMTime(seconds: speechSeg.startTime, preferredTimescale: 600),
                    duration: CMTime(seconds: speechSeg.endTime - speechSeg.startTime, preferredTimescale: 600)
                )
                
                let overlaps = faceRanges.contains { faceRange in
                    let intersection = speechRange.intersection(faceRange)
                    return intersection.duration.seconds > 0.2
                }
                
                if overlaps {
                    filtered.append(speechSeg)
                }
            }
            
            // If still no matches, return original (fallback)
            if filtered.isEmpty {
                print("SkipSlate: No segments match face ranges - using all segments as fallback")
                return speechSegments
            }
            
            print("SkipSlate: Filtered \(speechSegments.count) segments to \(filtered.count) based on face presence")
            return filtered
        }
        
        // Filter speech segments to only include those that overlap with well-framed ranges
        var filtered: [AudioAnalysisEngine.SpeechSegment] = []
        
        for speechSeg in speechSegments {
            let speechRange = CMTimeRange(
                start: CMTime(seconds: speechSeg.startTime, preferredTimescale: 600),
                duration: CMTime(seconds: speechSeg.endTime - speechSeg.startTime, preferredTimescale: 600)
            )
            
            // Check if this speech segment overlaps with any well-framed range
            let overlaps = wellFramedRanges.contains { framedRange in
                let intersection = speechRange.intersection(framedRange)
                return intersection.duration.seconds > 0.2 // Lowered threshold
            }
            
            if overlaps {
                filtered.append(speechSeg)
            }
        }
        
        // Fallback: if filtering removed everything, return original
        if filtered.isEmpty {
            print("SkipSlate: Face detection filtered out all segments - using original segments as fallback")
            return speechSegments
        }
        
        print("SkipSlate: Filtered \(speechSegments.count) segments to \(filtered.count) based on face detection")
        return filtered
    }
    
    /// Filter out director/shooter voices (off-camera, quieter speech)
    private func filterOffCameraVoices(
        speechSegments: [AudioAnalysisEngine.SpeechSegment],
        envelope: AudioAnalysisEngine.Envelope,
        asset: AVAsset,
        clip: MediaClip
    ) async throws -> [AudioAnalysisEngine.SpeechSegment] {
        guard !speechSegments.isEmpty else { return speechSegments }
        
        // Calculate average RMS for each speech segment
        var segmentRMS: [Double: Float] = [:]
        
        for seg in speechSegments {
            let startFrame = Int(seg.startTime / envelope.frameDuration)
            let endFrame = Int(seg.endTime / envelope.frameDuration)
            let validStart = max(0, min(startFrame, envelope.rmsValues.count - 1))
            let validEnd = max(validStart, min(endFrame, envelope.rmsValues.count))
            
            if validEnd > validStart {
                let segmentValues = Array(envelope.rmsValues[validStart..<validEnd])
                let avgRMS = segmentValues.reduce(0, +) / Float(segmentValues.count)
                segmentRMS[seg.startTime] = avgRMS
            }
        }
        
        // Calculate overall average RMS
        let allRMS = segmentRMS.values
        guard let maxRMS = allRMS.max(), let minRMS = allRMS.min(), maxRMS > 0 else {
            return speechSegments
        }
        
        let avgRMS = allRMS.reduce(0, +) / Float(allRMS.count)
        
        // Filter out segments that are significantly quieter (likely off-camera voices)
        // Director/shooter voices are typically 20-30% quieter than on-camera subjects
        let quietThreshold = avgRMS * 0.7 // 30% quieter than average
        
        var filtered: [AudioAnalysisEngine.SpeechSegment] = []
        
        for seg in speechSegments {
            if let rms = segmentRMS[seg.startTime], rms >= quietThreshold {
                filtered.append(seg)
            } else {
                print("SkipSlate: Filtered out quiet segment \(seg.startTime)-\(seg.endTime)s (likely off-camera voice, RMS: \(segmentRMS[seg.startTime] ?? 0))")
            }
        }
        
        print("SkipSlate: Filtered \(speechSegments.count) segments to \(filtered.count) based on audio level (removed off-camera voices)")
        return filtered
    }
    
    private func splitLongSegments(
        _ segments: [AudioAnalysisEngine.SpeechSegment],
        maxLength: Double
    ) -> [AudioAnalysisEngine.SpeechSegment] {
        var result: [AudioAnalysisEngine.SpeechSegment] = []
        for seg in segments {
            let duration = seg.endTime - seg.startTime
            if duration > maxLength {
                var currentStart = seg.startTime
                while currentStart < seg.endTime {
                    let chunkEnd = min(currentStart + maxLength, seg.endTime)
                    result.append(AudioAnalysisEngine.SpeechSegment(
                        startTime: currentStart,
                        endTime: chunkEnd
                    ))
                    currentStart = chunkEnd
                }
            } else {
                result.append(seg)
            }
        }
        return result
    }
    
    private func createImageSegments(for project: Project) throws -> [Segment] {
        let imageClips = project.clips.filter { $0.type == .image }
        guard !imageClips.isEmpty else {
            throw AutoEditError.noUsableAudio
        }
        
        var segments: [Segment] = []
        let defaultDuration: Double = 3.0
        
        for clip in imageClips {
            let segment = Segment(
                id: UUID(),
                sourceClipID: clip.id,
                sourceStart: 0.0,
                sourceEnd: defaultDuration,
                enabled: true,
                colorIndex: clip.colorIndex // Use clip's assigned color
            )
            segments.append(segment)
        }
        
        return segments
    }
    
    // MARK: - Highlight Reel Mode
    
    private func autoEditHighlightReel(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings,
        progressCallback: ((String) -> Void)? = nil,
        allAnalyzedSegmentsCallback: (([Segment]) -> Void)? = nil
    ) async throws -> [Segment] {
        // Use the comprehensive Highlight Reel service
        return try await HighlightReelService.shared.generateHighlightReel(
            project: project,
            assetsByClipID: assetsByClipID,
            settings: settings,
            progressCallback: progressCallback,
            allAnalyzedSegmentsCallback: allAnalyzedSegmentsCallback
        )
    }
    
    private func createMashupSegments(
        videoClips: [MediaClip],
        imageClips: [MediaClip],
        targetLength: Double?
    ) throws -> [Segment] {
        var segments: [Segment] = []
        var videoIndex = 0
        var imageIndex = 0
        var currentTime: Double = 0
        
        // If we have both video and images, alternate. Otherwise use what we have.
        let hasBoth = !videoClips.isEmpty && !imageClips.isEmpty
        var useVideo = !videoClips.isEmpty // Start with video if available
        
        let segmentDuration: Double = 2.0 // 2 seconds per segment for video
        let imageDuration: Double = 3.0 // 3 seconds for images
        
        while true {
            if useVideo && !videoClips.isEmpty {
                let clip = videoClips[videoIndex % videoClips.count]
                let duration = min(segmentDuration, clip.duration)
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: clip.id,
                    sourceStart: 0.0,
                    sourceEnd: duration,
                    enabled: true,
                    colorIndex: clip.colorIndex // Use clip's assigned color
                )
                segments.append(segment)
                currentTime += duration
                videoIndex += 1
                
                if hasBoth {
                    useVideo = false // Switch to images next
                }
            } else if !imageClips.isEmpty {
                let clip = imageClips[imageIndex % imageClips.count]
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: clip.id,
                    sourceStart: 0.0,
                    sourceEnd: imageDuration,
                    enabled: true,
                    colorIndex: clip.colorIndex // Use clip's assigned color
                )
                segments.append(segment)
                currentTime += imageDuration
                imageIndex += 1
                
                if hasBoth {
                    useVideo = true // Switch to video next
                }
            } else {
                break
            }
            
            // Check target length
            if let target = targetLength, currentTime >= target {
                break
            }
            
            // If we've used all clips, break
            if videoClips.isEmpty && imageIndex >= imageClips.count {
                break
            }
            if imageClips.isEmpty && videoIndex >= videoClips.count {
                break
            }
        }
        
        print("SkipSlate: Created mashup with \(segments.count) segments (video: \(videoIndex), images: \(imageIndex))")
        return segments
    }
}
