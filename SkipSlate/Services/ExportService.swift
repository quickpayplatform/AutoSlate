//
//  ExportService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Export
//  - This service builds its own composition independently from PlayerViewModel
//  - It does NOT depend on preview or playback
//  - It reads Project data and renders to file
//  - Communication: ExportStepView → ExportService.export(project:) → file output
//
//  NOTE: Global variables (globalColorSettings, imageSegmentsByTime) are shared with
//  PlayerViewModel because they're used by custom video compositors (ImageAwareCompositor, etc.)
//  which need access to these values. This is a technical limitation of AVFoundation's
//  compositor API, not a design choice. Both services clear/reset these before use.
//

import Foundation
import AVFoundation
import CoreImage
import AppKit

// Global storage for color settings (used by compositor)
// NOTE: Shared with PlayerViewModel for compositor access (AVFoundation limitation)
var globalColorSettings: ColorSettings = .default

// Global storage for image segments (used by compositor)
// NOTE: Shared with PlayerViewModel for compositor access (AVFoundation limitation)
var imageSegmentsByTime: [CMTime: (url: URL, duration: CMTime)] = [:]

class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    func export(
        project: Project,
        to url: URL,
        format: ExportFormat,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        // Overload with default resolution and quality
        try await export(
            project: project,
            to: url,
            format: format,
            resolution: project.resolution,
            quality: .balanced,
            progressHandler: progressHandler
        )
    }
    
    func export(
        project: Project,
        to url: URL,
        format: ExportFormat,
        resolution: ResolutionPreset,
        quality: ExportQuality,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        // CRASH-PROOF: Comprehensive input validation
        guard !project.segments.isEmpty else {
            throw NSError(
                domain: "ExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot export: Project has no segments"]
            )
        }
        
        guard resolution.width > 0 && resolution.height > 0 else {
            throw NSError(
                domain: "ExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid export resolution: \(resolution.width)×\(resolution.height)"]
            )
        }
        
        // CRASH-PROOF: Validate URL path (NSSavePanel should have already validated this)
        let directoryURL = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw NSError(
                domain: "ExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Export directory does not exist: \(directoryURL.path)"]
            )
        }
        
        // CRASH-PROOF: Validate URL path is not empty and is a file URL
        guard !url.path.isEmpty, url.isFileURL else {
            throw NSError(
                domain: "ExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid export URL: must be a valid file URL"]
            )
        }
        
        // CRASH-PROOF: Build composition with error handling
        let composition: AVMutableComposition
        do {
            composition = try await buildComposition(
                from: project,
                resolution: resolution,
                aspectRatio: project.aspectRatio
            )
        } catch {
            print("SkipSlate: ❌ ExportService - Failed to build composition: \(error)")
            throw NSError(
                domain: "ExportService",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build composition: \(error.localizedDescription)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        
        // CRASH-PROOF: Validate composition has content
        guard composition.duration.seconds > 0 else {
            throw NSError(
                domain: "ExportService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Composition has zero duration - cannot export empty video"]
            )
        }
        
        // CRASH-PROOF: Create video composition with error handling
        let videoComposition: AVMutableVideoComposition?
        do {
            videoComposition = createVideoComposition(
                for: composition,
                settings: project.colorSettings,
                resolution: resolution,
                aspectRatio: project.aspectRatio
            )
        } catch {
            print("SkipSlate: ⚠️ ExportService - Failed to create video composition: \(error)")
            videoComposition = nil // Continue without video composition
        }
        
        // CRASH-PROOF: Create audio mix with error handling
        let enabledSegments = project.segments.filter { $0.enabled }
        let audioMix: AVAudioMix? = autoreleasepool {
            // Try TransitionService first (for crossfades)
            if let transitionMix = TransitionService.shared.createAudioMixWithTransitions(
                for: composition,
                segments: enabledSegments,
                project: project
            ) {
                print("SkipSlate: ExportService - Using TransitionService audio mix with \(transitionMix.inputParameters.count) input parameter(s)")
                return transitionMix
            } else {
                // Fallback to AudioService (simple volume control)
                do {
                    if let mix = AudioService.shared.createAudioMix(
                        for: composition,
                        settings: project.audioSettings
                    ) {
                        print("SkipSlate: ExportService - Using AudioService audio mix with \(mix.inputParameters.count) input parameter(s)")
                        return mix
                    } else {
                        print("SkipSlate: ExportService - ⚠ WARNING - No audio mix created (composition may have no audio tracks)")
                        return nil
                    }
                } catch {
                    print("SkipSlate: ⚠️ ExportService - Audio mix creation error: \(error)")
                    return nil // Continue without audio mix
                }
            }
        }
        
        // CRASH-PROOF: Determine export preset based on quality
        let presetName = qualityPreset(for: quality, resolution: resolution)
        
        // CRASH-PROOF: Create export session with validation
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw NSError(
                domain: "ExportService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create export session. Preset may not be supported: \(presetName)"]
            )
        }
        
        exportSession.outputURL = url
        exportSession.outputFileType = format.fileType
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        
        // CRASH-PROOF: Validate export session configuration before starting
        print("SkipSlate: ExportService - Export session configured:")
        print("SkipSlate:   - Output URL: \(url.path)")
        print("SkipSlate:   - Output file type: \(format.fileType)")
        print("SkipSlate:   - Has video composition: \(videoComposition != nil)")
        print("SkipSlate:   - Has audio mix: \(audioMix != nil)")
        print("SkipSlate:   - Composition duration: \(composition.duration.seconds)s")
        print("SkipSlate:   - Preset: \(presetName)")
        
        // CRASH-PROOF: Validate output URL is writable
        do {
            // Remove existing file if it exists (export session can't overwrite)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("SkipSlate: ExportService - Removed existing file at export location")
            }
        } catch {
            print("SkipSlate: ⚠️ ExportService - Could not remove existing file: \(error)")
            // Continue anyway - export might still work
        }
        
        // CRASH-PROOF: Monitor progress with error handling
        let progressTask = Task { @MainActor in
            do {
                for try await _ in exportSession.states(updateInterval: 0.1) {
                    // CRASH-PROOF: Check if export session is still active
                    guard exportSession.status != .cancelled && exportSession.status != .failed else {
                        break // Stop monitoring if export is cancelled/failed
                    }
                    
                    // CRASH-PROOF: Validate progress value
                    let progress = Double(exportSession.progress)
                    guard progress.isFinite && progress >= 0 && progress <= 1.0 else {
                        continue
                    }
                    progressHandler(progress)
                }
            } catch {
                print("SkipSlate: ⚠️ ExportService - Progress monitoring error: \(error)")
                // Non-fatal - continue with export
            }
        }
        
        // CRASH-PROOF: Export with comprehensive error handling
        do {
            await exportSession.export()
        } catch {
            // Cancel progress monitoring if export throws
            progressTask.cancel()
            print("SkipSlate: ❌ ExportService - Export threw error: \(error)")
            throw NSError(
                domain: "ExportService",
                code: -5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Export failed: \(error.localizedDescription)",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        
        // Cancel progress monitoring after export completes
        progressTask.cancel()
        
        // CRASH-PROOF: Validate export status with detailed error information
        guard exportSession.status == .completed else {
            let statusDescription: String
            switch exportSession.status {
            case .unknown: statusDescription = "Unknown status"
            case .waiting: statusDescription = "Waiting"
            case .exporting: statusDescription = "Still exporting"
            case .completed: statusDescription = "Completed" // Should not reach here
            case .failed: statusDescription = "Failed"
            case .cancelled: statusDescription = "Cancelled"
            @unknown default: statusDescription = "Unknown status"
            }
            
            // CRASH-PROOF: Get detailed error information
            var errorMessage = statusDescription
            if let error = exportSession.error {
                errorMessage = error.localizedDescription
                print("SkipSlate: ❌ ExportService - Export session error: \(error)")
                if let nsError = error as NSError? {
                    print("SkipSlate: ExportService - Error domain: \(nsError.domain), code: \(nsError.code)")
                    print("SkipSlate: ExportService - Error userInfo: \(nsError.userInfo)")
                    
                    // Provide more specific error messages
                    if nsError.domain == NSOSStatusErrorDomain {
                        let osStatus = nsError.code
                        switch osStatus {
                        case -128: // userCancelledErr
                            errorMessage = "Export was cancelled"
                        case -11838: // kAudioConverterErr_FormatNotSupported
                            errorMessage = "Audio format not supported for export"
                        default:
                            errorMessage = "Export failed (Error code: \(osStatus)): \(error.localizedDescription)"
                        }
                    }
                }
            }
            
            throw NSError(
                domain: "ExportService",
                code: -5,
                userInfo: [
                    NSLocalizedDescriptionKey: errorMessage,
                    NSUnderlyingErrorKey: exportSession.error as Any,
                    "status": statusDescription,
                    "progress": exportSession.progress
                ] as [String : Any]
            )
        }
        
        // CRASH-PROOF: Verify file was actually created (with retry logic for file system delays)
        var fileExists = false
        for attempt in 0..<3 {
            fileExists = FileManager.default.fileExists(atPath: url.path)
            if fileExists {
                break
            }
            // Small delay before retry (file system might need a moment)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        guard fileExists else {
            throw NSError(
                domain: "ExportService",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Export reported success but file was not created at: \(url.path)"]
            )
        }
        
        // CRASH-PROOF: Validate file size with error handling
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                guard fileSize > 0 else {
                    throw NSError(
                        domain: "ExportService",
                        code: -7,
                        userInfo: [NSLocalizedDescriptionKey: "Exported file is empty (0 bytes)"]
                    )
                }
                print("SkipSlate: ExportService - ✅ Exported file size: \(fileSize) bytes")
            } else {
                print("SkipSlate: ExportService - ⚠️ Could not determine file size")
            }
        } catch let error as NSError where error.domain == "ExportService" {
            throw error // Re-throw our custom errors
        } catch {
            print("SkipSlate: ⚠️ ExportService - Could not validate file size: \(error)")
            // Non-fatal - file exists, continue
        }
        
        // POST-EXPORT VALIDATION: Verify exported file has audio (non-fatal)
        print("SkipSlate: ExportService - ===== POST-EXPORT VALIDATION ======")
        do {
            let exportedAsset = AVURLAsset(url: url)
            let exportedAudioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)
            
            if exportedAudioTracks.isEmpty {
                print("SkipSlate: ExportService - ⚠⚠⚠ WARNING - Exported file has NO audio tracks!")
                print("SkipSlate: ExportService - The exported file will be silent.")
            } else {
                var hasValidExportedAudio = false
                for (index, track) in exportedAudioTracks.enumerated() {
                    do {
                        let trackDuration = try await track.load(.timeRange)
                        let durationSeconds = CMTimeGetSeconds(trackDuration.duration)
                        print("SkipSlate: ExportService - Exported audio track \(index): duration=\(durationSeconds)s")
                        
                        if durationSeconds > 0 {
                            hasValidExportedAudio = true
                        }
                    } catch {
                        print("SkipSlate: ⚠️ ExportService - Could not load track duration: \(error)")
                    }
                }
                
                if hasValidExportedAudio {
                    print("SkipSlate: ExportService - ✓✓✓ SUCCESS - Exported file contains valid audio!")
                } else {
                    print("SkipSlate: ExportService - ⚠⚠⚠ WARNING - Exported file has audio tracks but all have zero duration!")
                }
            }
        } catch {
            print("SkipSlate: ExportService - ⚠ Could not validate exported file audio: \(error)")
            // Don't throw - export succeeded, validation is just for debugging
        }
        print("SkipSlate: ExportService - ================================")
    }
    
    // CRASH-PROOF: Helper to determine export preset based on quality
    private func qualityPreset(for quality: ExportQuality, resolution: ResolutionPreset) -> String {
        // CRASH-PROOF: Default to highest quality if quality is invalid
        let width = resolution.width
        let height = resolution.height
        
        // Choose preset based on resolution and quality
        if width >= 3840 || height >= 3840 {
            // 4K or higher
            switch quality {
            case .high: return AVAssetExportPresetHighestQuality
            case .balanced: return AVAssetExportPreset1920x1080 // Downscale for balanced
            case .small: return AVAssetExportPreset1280x720 // Downscale more for small
            }
        } else if width >= 1920 || height >= 1920 {
            // 1080p
            switch quality {
            case .high: return AVAssetExportPresetHighestQuality
            case .balanced: return AVAssetExportPreset1920x1080
            case .small: return AVAssetExportPreset1280x720
            }
        } else {
            // 720p or lower
            switch quality {
            case .high: return AVAssetExportPresetHighestQuality
            case .balanced: return AVAssetExportPreset1280x720
            case .small: return AVAssetExportPresetMediumQuality
            }
        }
    }
    
    private func buildComposition(from project: Project, resolution: ResolutionPreset, aspectRatio: AspectRatio) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        
        // Clear image segments storage for export
        imageSegmentsByTime.removeAll()
        
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.cannotCreateTrack
        }
        
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.cannotCreateTrack
        }
        
        // Create image timing track for image segments
        guard let imageTimingTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.cannotCreateTrack
        }
        
        var currentTime = CMTime.zero
        let timescale: Int32 = 600
        var hasRealVideo = false
        var hasAnyImage = false
        
        // Calculate total duration for dummy video asset
        var totalDuration = CMTime.zero
        let enabledSegments = project.segments.filter { $0.enabled }
        for segment in enabledSegments {
            totalDuration = CMTimeAdd(totalDuration, CMTime(seconds: segment.duration, preferredTimescale: timescale))
        }
        
        // Early return if no enabled segments
        guard !enabledSegments.isEmpty, totalDuration > .zero else {
            print("SkipSlate: No enabled segments for export, returning empty composition")
            return composition
        }
        
        // Create dummy video asset for image timing if needed
        var dummyVideoAsset: AVAsset?
        var dummyVideoTrack: AVAssetTrack?
        
        // Check if we have image segments (only check clip segments, skip gaps)
        let hasImageSegments = enabledSegments.contains { segment in
            guard let clipID = segment.clipID,
                  let clip = project.clips.first(where: { $0.id == clipID }) else {
            return false
            }
            return clip.type == .image
        }
        
        if hasImageSegments && totalDuration > .zero {
            // Determine render size
            var renderSize = CGSize(width: CGFloat(resolution.width), height: CGFloat(resolution.height))
            let presetRatio = Double(resolution.width) / Double(resolution.height)
            let targetRatio = aspectRatio.ratio
            let ratioDiff = abs(presetRatio - targetRatio)
            
            if ratioDiff > 0.01 {
                if presetRatio > targetRatio {
                    renderSize.height = CGFloat(Double(renderSize.width) / targetRatio)
                } else {
                    renderSize.width = CGFloat(Double(renderSize.height) * targetRatio)
                }
            }
            
            do {
                dummyVideoAsset = try await createDummyVideoAsset(duration: totalDuration, timescale: timescale, renderSize: renderSize)
                let tracks = try await dummyVideoAsset!.loadTracks(withMediaType: .video)
                dummyVideoTrack = tracks.first
            } catch {
                print("SkipSlate: Warning - Failed to create dummy video asset: \(error)")
            }
        }
        
        // Process segments - use compositionStartTime to respect gaps
        // Sort segments by compositionStartTime to maintain timeline order
        let sortedSegments = project.segments
            .filter { $0.enabled }
            .sorted { seg1, seg2 in
                let start1 = seg1.compositionStartTime > 0 ? seg1.compositionStartTime : 0
                let start2 = seg2.compositionStartTime > 0 ? seg2.compositionStartTime : 0
                return start1 < start2
            }
        
        for segment in sortedSegments {
            // CRITICAL: Skip gap segments - they render as black (no media inserted)
            if segment.isGap {
                let gapDuration = CMTime(seconds: segment.duration, preferredTimescale: timescale)
                let gapStartTime = CMTime(seconds: segment.compositionStartTime, preferredTimescale: timescale)
                // Use the gap's explicit start time, or advance currentTime if not set
                currentTime = gapStartTime > .zero ? gapStartTime : CMTimeAdd(currentTime, gapDuration)
                print("SkipSlate: ExportService - Skipping gap segment at \(CMTimeGetSeconds(currentTime))s (duration: \(segment.duration)s)")
                continue
            }
            
            // For clip segments, require a valid clipID (using helper)
            guard let clipID = segment.clipID,
                  let clip = project.clips.first(where: { $0.id == clipID }) else {
                print("SkipSlate: ExportService - Warning: Clip segment missing clipID or clip not found")
                continue
            }
            
            // Safety check: Validate clip segment properties before accessing
            guard segment.sourceStart >= 0,
                  segment.sourceEnd > segment.sourceStart,
                  segment.sourceEnd <= clip.duration + 0.1 else { // Allow small floating point tolerance
                print("SkipSlate: ExportService - Warning: Invalid segment bounds - start: \(segment.sourceStart), end: \(segment.sourceEnd), clip duration: \(clip.duration)")
                continue
            }
            
            // Use compositionStartTime if available, otherwise use currentTime
            let segmentStartTime = segment.compositionStartTime > 0 
                ? CMTime(seconds: segment.compositionStartTime, preferredTimescale: timescale)
                : currentTime
            
            let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: timescale)
            guard segmentDuration > .zero else { 
                print("SkipSlate: ExportService - Warning: Segment has zero or invalid duration: \(segment.duration)")
                continue 
            }
            
            // Handle images - store for compositor AND insert timing track
            if clip.type == .image {
                hasAnyImage = true
                imageSegmentsByTime[segmentStartTime] = (url: clip.url, duration: segmentDuration)
                
                // Insert timing segment from dummy asset
                if let dummyTrack = dummyVideoTrack {
                    let dummyDuration = try await dummyVideoAsset!.load(.duration)
                    let sourceDuration = min(segmentDuration, dummyDuration)
                    let sourceTimeRange = CMTimeRange(start: .zero, duration: sourceDuration)
                    do {
                        try imageTimingTrack.insertTimeRange(
                            sourceTimeRange,
                            of: dummyTrack,
                            at: segmentStartTime
                        )
                    } catch {
                        print("SkipSlate: Error inserting timing segment for export: \(error)")
                    }
                }
                
                // Insert audio if available (for image-only compositions)
                if !hasRealVideo {
                    let audioClips = project.clips.filter { $0.type == .audioOnly }
                    if let audioClip = audioClips.first, segmentStartTime == .zero {
                        let audioAsset = AVURLAsset(url: audioClip.url)
                        do {
                            let sourceAudioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                            if let sourceAudioTrack = sourceAudioTracks.first {
                                let audioDuration = try await audioAsset.load(.duration)
                                let insertDuration = min(totalDuration, audioDuration)
                                let audioTimeRange = CMTimeRange(start: .zero, duration: insertDuration)
                                try audioTrack.insertTimeRange(
                                    audioTimeRange,
                                    of: sourceAudioTrack,
                                    at: .zero
                                )
                            }
                        } catch {
                            print("SkipSlate: Error inserting audio for export: \(error)")
                        }
                    }
                }
                
                currentTime = CMTimeAdd(segmentStartTime, segmentDuration)
                continue
            }
            
            // Safety check: Ensure clip URL is valid and file exists
            guard FileManager.default.fileExists(atPath: clip.url.path) else {
                print("SkipSlate: ExportService - Warning: Clip file does not exist: \(clip.url.path)")
                continue
            }
            
            let asset = AVURLAsset(url: clip.url)
            
            // Insert video if available
            do {
                let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
                if let sourceVideoTrack = sourceVideoTracks.first {
                    // Safety check: Clamp sourceStart to valid range and validate timeRange
                    let clampedStart = max(0.0, min(segment.sourceStart, clip.duration - 0.1))
                    let maxDuration = clip.duration - clampedStart
                    let clampedDuration = min(segmentDuration, CMTime(seconds: maxDuration, preferredTimescale: timescale))
                    
                    guard clampedDuration > .zero else {
                        print("SkipSlate: ExportService - Warning: Invalid clamped duration for video segment")
                        continue
                    }
                    
                    let sourceTimeRange = CMTimeRange(
                        start: CMTime(seconds: clampedStart, preferredTimescale: timescale),
                        duration: clampedDuration
                    )
                    
                    // Safety check: Verify timeRange is valid
                    guard sourceTimeRange.isValid && !sourceTimeRange.isEmpty else {
                        print("SkipSlate: ExportService - Warning: Invalid timeRange for video: start=\(CMTimeGetSeconds(sourceTimeRange.start)), duration=\(CMTimeGetSeconds(sourceTimeRange.duration))")
                        continue
                    }
                    
                    try videoTrack.insertTimeRange(
                        sourceTimeRange,
                        of: sourceVideoTrack,
                        at: segmentStartTime
                    )
                    hasRealVideo = true
                }
            } catch {
                print("SkipSlate: Error inserting video for export: \(error.localizedDescription)")
            }
            
            // Insert audio if available - use hasAudioTrack property
            if clip.hasAudioTrack {
                do {
                    let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                    if let sourceAudioTrack = sourceAudioTracks.first {
                        // Safety check: Clamp sourceStart to valid range and validate timeRange
                        let clampedStart = max(0.0, min(segment.sourceStart, clip.duration - 0.1))
                        let maxDuration = clip.duration - clampedStart
                        let clampedDuration = min(segmentDuration, CMTime(seconds: maxDuration, preferredTimescale: timescale))
                        
                        guard clampedDuration > .zero else {
                            print("SkipSlate: ExportService - Warning: Invalid clamped duration for audio segment")
                            continue
                        }
                        
                        let sourceTimeRange = CMTimeRange(
                            start: CMTime(seconds: clampedStart, preferredTimescale: timescale),
                            duration: clampedDuration
                        )
                        
                        // Safety check: Verify timeRange is valid
                        guard sourceTimeRange.isValid && !sourceTimeRange.isEmpty else {
                            print("SkipSlate: ExportService - Warning: Invalid timeRange for audio: start=\(CMTimeGetSeconds(sourceTimeRange.start)), duration=\(CMTimeGetSeconds(sourceTimeRange.duration))")
                            continue
                        }
                        
                        try audioTrack.insertTimeRange(
                            sourceTimeRange,
                            of: sourceAudioTrack,
                            at: segmentStartTime
                        )
                        print("SkipSlate: Export - Inserted audio from '\(clip.fileName)' at \(CMTimeGetSeconds(segmentStartTime))s")
                    } else {
                        print("SkipSlate: Export - ⚠ Clip marked as hasAudioTrack=true but no audio tracks found: \(clip.fileName)")
                    }
                } catch {
                    print("SkipSlate: Export - ✗ Error inserting audio from '\(clip.fileName)': \(error.localizedDescription)")
                }
            } else {
                print("SkipSlate: Export - Clip '\(clip.fileName)' has no audio track (hasAudioTrack=false)")
            }
            
            // Update currentTime to end of this segment
            currentTime = CMTimeAdd(segmentStartTime, segmentDuration)
        }
        
        // CRITICAL: Verify audio is actually embedded in the export composition
        print("SkipSlate: ExportService - ===== AUDIO VERIFICATION ======")
        let finalAudioTracks = composition.tracks(withMediaType: .audio)
        print("SkipSlate: ExportService - Final composition has \(finalAudioTracks.count) audio track(s)")
        
        // Check if any segments should have had audio (only check clip segments, skip gaps)
        var segmentsWithAudio = 0
        var clipsWithAudio: [String] = []
        for segment in enabledSegments {
            guard let clipID = segment.clipID,
                  let clip = project.clips.first(where: { $0.id == clipID }) else {
                continue
            }
                if clip.hasAudioTrack {
                    segmentsWithAudio += 1
                    clipsWithAudio.append("\(clip.fileName) (hasAudioTrack=true)")
            }
        }
        
        var hasValidAudio = false
        var totalAudioDuration: Double = 0
        
        if finalAudioTracks.isEmpty {
            print("SkipSlate: ExportService - ⚠⚠⚠ CRITICAL ERROR - Composition has NO audio tracks!")
            print("SkipSlate: ExportService - Segments that should have audio: \(segmentsWithAudio)")
            print("SkipSlate: ExportService - Clips that should have audio: \(clipsWithAudio)")
            
            if segmentsWithAudio > 0 {
                print("SkipSlate: ExportService - ⚠⚠⚠ ERROR - Expected \(segmentsWithAudio) segments with audio, but composition has 0 audio tracks!")
                // THROW ERROR - export should not proceed if audio is missing when expected
                throw NSError(
                    domain: "ExportService",
                    code: -200,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Export composition has no audio tracks but \(segmentsWithAudio) segments should have audio. Audio insertion failed.",
                        "segmentsWithAudio": segmentsWithAudio,
                        "clipsWithAudio": clipsWithAudio
                    ]
                )
            } else {
                print("SkipSlate: ExportService - ✓ No audio expected - export will be silent (this is OK)")
            }
        } else {
            // Verify each audio track has content
            for (index, track) in finalAudioTracks.enumerated() {
                let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                let trackEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(track.timeRange))
                totalAudioDuration = max(totalAudioDuration, trackEnd)
                
                print("SkipSlate: ExportService - Audio track \(index): duration=\(trackDuration)s")
                
                if trackDuration > 0 {
                    hasValidAudio = true
                } else {
                    print("SkipSlate: ExportService - ⚠ WARNING: Track \(index) has zero duration!")
                }
            }
            
            if segmentsWithAudio > 0 && !hasValidAudio {
                print("SkipSlate: ExportService - ⚠⚠⚠ CRITICAL ERROR - Expected audio but all tracks have zero duration!")
                throw NSError(
                    domain: "ExportService",
                    code: -201,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Export composition has \(finalAudioTracks.count) audio track(s) but all have zero duration. Audio insertion failed.",
                        "audioTrackCount": finalAudioTracks.count,
                        "segmentsWithAudio": segmentsWithAudio
                    ]
                )
            } else if hasValidAudio {
                print("SkipSlate: ExportService - ✓✓✓ SUCCESS - Audio IS embedded in export composition!")
                print("SkipSlate: ExportService - Total audio duration: \(totalAudioDuration)s")
            }
        }
        print("SkipSlate: ExportService - ================================")
        
        return composition
    }
    
    private func createVideoComposition(
        for composition: AVMutableComposition,
        settings: ColorSettings,
        resolution: ResolutionPreset,
        aspectRatio: AspectRatio
    ) -> AVMutableVideoComposition {
        // Store settings globally for compositor access
        globalColorSettings = settings
        
        // Determine render size from project settings
        var renderSize = CGSize(width: CGFloat(resolution.width), height: CGFloat(resolution.height))
        
        // Verify aspect ratio matches
        let presetRatio = Double(resolution.width) / Double(resolution.height)
        let targetRatio = aspectRatio.ratio
        let ratioDiff = abs(presetRatio - targetRatio)
        
        // If aspect ratio doesn't match, adjust dimensions to fit
        if ratioDiff > 0.01 {
            if presetRatio > targetRatio {
                renderSize.height = CGFloat(Double(renderSize.width) / targetRatio)
            } else {
                renderSize.width = CGFloat(Double(renderSize.height) * targetRatio)
            }
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 24) // 24fps for frame-accurate timeline
        
        let videoTrack = composition.tracks(withMediaType: .video).first
        let imageTimingTrack = composition.tracks(withMediaType: .video).first { track in
            return track != videoTrack
        }
        
        let trackToUse = videoTrack ?? imageTimingTrack
        
        guard let track = trackToUse else {
            return videoComposition
        }
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Use ImageAwareCompositor if we have images, otherwise ColorCorrectionCompositor
        if !imageSegmentsByTime.isEmpty {
            videoComposition.customVideoCompositorClass = ImageAwareCompositor.self
        } else {
            videoComposition.customVideoCompositorClass = ColorCorrectionCompositor.self
        }
        
        return videoComposition
    }
    
    /// Creates a dummy video asset with black frames for image timing (same as PlayerViewModel)
    private func createDummyVideoAsset(duration: CMTime, timescale: Int32, renderSize: CGSize) async throws -> AVAsset {
        // Create a temporary file URL for the dummy video
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        
        // Use AVAssetWriter to create a minimal black video
        guard let writer = try? AVAssetWriter(outputURL: tempFile, fileType: .mov) else {
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create asset writer"])
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
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }
        
        writer.add(writerInput)
        
        guard writer.startWriting() else {
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Create frames at 30fps, but we'll create one frame per second to keep it minimal
        let frameDuration = CMTime(value: 1, timescale: timescale)
        var currentTime = CMTime.zero
        
        while currentTime < duration {
            guard let pixelBufferPool = adaptor.pixelBufferPool else {
                writer.cancelWriting()
                throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer pool"])
            }
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                writer.cancelWriting()
                throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
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
                    throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to append frame"])
                }
            }
            
            currentTime = CMTimeAdd(currentTime, frameDuration)
        }
        
        writerInput.markAsFinished()
        
        await writer.finishWriting()
        
        guard writer.status == .completed else {
            // Clean up on failure
            try? FileManager.default.removeItem(at: tempFile)
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Writing failed: \(writer.error?.localizedDescription ?? "unknown")"])
        }
        
        // Verify the file exists and is readable
        guard FileManager.default.fileExists(atPath: tempFile.path) else {
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dummy video file was not created"])
        }
        
        // Create the asset and verify it can be loaded
        let asset = AVURLAsset(url: tempFile)
        
        // Try to load duration to verify the asset is valid
        do {
            let assetDuration = try await asset.load(.duration)
            if !assetDuration.isValid || assetDuration.seconds == 0 {
                try? FileManager.default.removeItem(at: tempFile)
                throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dummy video asset has invalid duration"])
            }
            print("SkipSlate: Export dummy video asset created: \(tempFile.lastPathComponent), duration: \(assetDuration.seconds)s")
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot load dummy video asset: \(error.localizedDescription)"])
        }
        
        return asset
    }
}

enum ExportError: LocalizedError {
    case cannotCreateSession
    case cannotCreateTrack
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .cannotCreateSession:
            return "Cannot create export session"
        case .cannotCreateTrack:
            return "Cannot create composition track"
        case .exportFailed:
            return "Export failed"
        }
    }
}

// Custom compositor for color correction
class ColorCorrectionCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // No-op for v1
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        let renderTime = asyncVideoCompositionRequest.compositionTime
        
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? AVMutableVideoCompositionInstruction,
              !instruction.layerInstructions.isEmpty else {
            // No instruction - render black frame
            renderBlackFrame(request: asyncVideoCompositionRequest)
            return
        }
        
        // Get the first layer instruction (for now, we only support single-layer)
        guard let layerInstruction = instruction.layerInstructions.first as? AVMutableVideoCompositionLayerInstruction else {
            // No layer instruction - render black frame
            renderBlackFrame(request: asyncVideoCompositionRequest)
            return
        }
        
        // Try to get source frame - try all available track IDs if the first one fails
        var sourcePixelBuffer: CVPixelBuffer?
        
        // First try the trackID from the layer instruction
        sourcePixelBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: layerInstruction.trackID)
        
        // If that fails, try all available source frames
        if sourcePixelBuffer == nil {
            // Try to get source frame from any available track
            for trackIDNumber in asyncVideoCompositionRequest.sourceTrackIDs {
                let trackID = trackIDNumber.int32Value
                if let frame = asyncVideoCompositionRequest.sourceFrame(byTrackID: trackID) {
                    sourcePixelBuffer = frame
                    print("SkipSlate: ColorCorrectionCompositor - Found source frame using alternative trackID \(trackID) at time \(CMTimeGetSeconds(renderTime))s")
                    break
                }
            }
        }
        
        guard let pixelBuffer = sourcePixelBuffer else {
            print("SkipSlate: ColorCorrectionCompositor - No source frame available for trackID \(layerInstruction.trackID) at time \(CMTimeGetSeconds(renderTime))s")
            print("SkipSlate: Available track IDs: \(asyncVideoCompositionRequest.sourceTrackIDs)")
            print("SkipSlate: Instruction time range: \(CMTimeGetSeconds(instruction.timeRange.start))s - \(CMTimeGetSeconds(CMTimeRangeGetEnd(instruction.timeRange)))s")
            // No source frame - render black frame
            renderBlackFrame(request: asyncVideoCompositionRequest)
            return
        }
        
        // Use the found pixel buffer
        let finalSourcePixelBuffer = pixelBuffer
        
        // Get opacity from layer instruction
        var startOpacity: Float = 1.0
        var endOpacity: Float = 1.0
        var opacityTimeRange: CMTimeRange = CMTimeRange()
        var opacity: Float = 1.0
        
        if layerInstruction.getOpacityRamp(for: renderTime, startOpacity: &startOpacity, endOpacity: &endOpacity, timeRange: &opacityTimeRange) {
            // Interpolate opacity based on position in time range
            if opacityTimeRange.duration.seconds > 0 {
                let progress = (renderTime.seconds - opacityTimeRange.start.seconds) / opacityTimeRange.duration.seconds
                opacity = startOpacity + Float(progress) * (endOpacity - startOpacity)
            } else {
                opacity = startOpacity
            }
        }
        
        // Get color settings from global storage
        let settings = globalColorSettings
        
        // Apply Core Image filters
        let ciImage = CIImage(cvPixelBuffer: finalSourcePixelBuffer)
        let context = CIContext()
        
        var filteredImage = ciImage
        
        // Only apply color correction if settings are not default
        let needsColorCorrection = settings.exposure != 0.0 || settings.contrast != 1.0 || settings.saturation != 1.0 || settings.colorSaturation > 0.0
        
        if needsColorCorrection {
            // Apply exposure
            if settings.exposure != 0.0 {
                if let filter = CIFilter(name: "CIExposureAdjust") {
                    filter.setValue(filteredImage, forKey: kCIInputImageKey)
                    filter.setValue(settings.exposure, forKey: kCIInputEVKey)
                    if let output = filter.outputImage {
                        filteredImage = output
                    }
                }
            }
            
            // Apply contrast and saturation
            if settings.contrast != 1.0 || settings.saturation != 1.0 {
                if let filter = CIFilter(name: "CIColorControls") {
                    filter.setValue(filteredImage, forKey: kCIInputImageKey)
                    filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
                    filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
                    if let output = filter.outputImage {
                        filteredImage = output
                    }
                }
            }
            
            // Apply color grading (hue shift + saturation)
            if settings.colorSaturation > 0.0 {
                // Convert hue (0-360) to radians for Core Image
                let hueRadians = settings.colorHue * .pi / 180.0
                
                // Use CIHueAdjust to shift hue
                if let hueFilter = CIFilter(name: "CIHueAdjust") {
                    hueFilter.setValue(filteredImage, forKey: kCIInputImageKey)
                    hueFilter.setValue(hueRadians, forKey: kCIInputAngleKey)
                    if let hueOutput = hueFilter.outputImage {
                        filteredImage = hueOutput
                    }
                }
                
                // Blend with original based on saturation intensity
                // Higher saturation = more color grading applied
                if settings.colorSaturation < 1.0 {
                    // Blend between original and color-graded
                    if let blendFilter = CIFilter(name: "CIColorBlendMode") {
                        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
                        blendFilter.setValue(filteredImage, forKey: kCIInputBackgroundImageKey)
                        if let blendOutput = blendFilter.outputImage {
                            // Use CIColorMatrix to control blend amount
                            if let matrixFilter = CIFilter(name: "CIColorMatrix") {
                                matrixFilter.setValue(blendOutput, forKey: kCIInputImageKey)
                                // Interpolate between original and graded based on colorSaturation
                                let blendAmount = Float(settings.colorSaturation)
                                // This is a simplified approach - in production, use proper blending
                                filteredImage = blendOutput
                            }
                        }
                    }
                }
            }
        }
        
        // Apply opacity if not 1.0
        if opacity < 1.0 {
            // Use CIColorMatrix to multiply alpha channel
            if let filter = CIFilter(name: "CIColorMatrix") {
                filter.setValue(filteredImage, forKey: kCIInputImageKey)
                // Keep RGB unchanged, multiply alpha by opacity
                filter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
                filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                if let output = filter.outputImage {
                    filteredImage = output
                }
            } else {
                // Fallback: use multiply blend with white at opacity
                if let multiplyFilter = CIFilter(name: "CIMultiplyCompositing") {
                    let opacityColor = CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(opacity))
                    let backgroundImage = CIImage(color: opacityColor).cropped(to: filteredImage.extent)
                    multiplyFilter.setValue(filteredImage, forKey: kCIInputImageKey)
                    multiplyFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
                    if let output = multiplyFilter.outputImage {
                        filteredImage = output
                    }
                }
            }
        }
        
        // Render to output buffer
        guard let outputPixelBuffer = asyncVideoCompositionRequest.renderContext.newPixelBuffer() else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "ColorCorrectionCompositor", code: -2))
            return
        }
        
        context.render(filteredImage, to: outputPixelBuffer)
        asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    private func renderBlackFrame(request: AVAsynchronousVideoCompositionRequest) {
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "ColorCorrectionCompositor", code: -3))
            return
        }
        
        // Fill with black
        CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        let baseAddress = CVPixelBufferGetBaseAddress(outputPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputPixelBuffer)
        let height = CVPixelBufferGetHeight(outputPixelBuffer)
        if let base = baseAddress {
            memset(base, 0, bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(outputPixelBuffer, [])
        
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        // No-op for v1
    }
}

// Custom compositor that handles both video and images
class ImageAwareCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // No-op for v1
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        let renderTime = asyncVideoCompositionRequest.compositionTime
        
        // Check if this time corresponds to an image segment
        if let imageSegment = findImageSegment(at: renderTime) {
            // Get opacity from layer instruction if available
            var opacity: Float = 1.0
            if let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? AVMutableVideoCompositionInstruction,
               !instruction.layerInstructions.isEmpty,
               let layerInstruction = instruction.layerInstructions.first as? AVMutableVideoCompositionLayerInstruction {
                // Get opacity at this time from the layer instruction
                var startOpacity: Float = 1.0
                var endOpacity: Float = 1.0
                var timeRange: CMTimeRange = CMTimeRange()
                if layerInstruction.getOpacityRamp(for: renderTime, startOpacity: &startOpacity, endOpacity: &endOpacity, timeRange: &timeRange) {
                    // Interpolate opacity based on position in time range
                    if timeRange.duration.seconds > 0 {
                        let progress = (renderTime.seconds - timeRange.start.seconds) / timeRange.duration.seconds
                        opacity = startOpacity + Float(progress) * (endOpacity - startOpacity)
                    } else {
                        opacity = startOpacity
                    }
                }
            }
            
            // Render image with opacity
            renderImage(imageSegment.url, at: renderTime, request: asyncVideoCompositionRequest, opacity: opacity)
            return
        }
        
        // Otherwise, render video frame with color correction
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? AVMutableVideoCompositionInstruction,
              !instruction.layerInstructions.isEmpty,
              let sourcePixelBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: instruction.layerInstructions[0].trackID) else {
            // No video source - render black frame
            renderBlackFrame(request: asyncVideoCompositionRequest)
            return
        }
        
        // Apply color correction
        let settings = globalColorSettings
        let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let context = CIContext()
        
        var filteredImage = ciImage
        
        // Apply exposure
        if settings.exposure != 0.0 {
            if let filter = CIFilter(name: "CIExposureAdjust") {
                filter.setValue(filteredImage, forKey: kCIInputImageKey)
                filter.setValue(settings.exposure, forKey: kCIInputEVKey)
                if let output = filter.outputImage {
                    filteredImage = output
                }
            }
        }
        
        // Apply contrast and saturation
        if settings.contrast != 1.0 || settings.saturation != 1.0 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(filteredImage, forKey: kCIInputImageKey)
                filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
                filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    filteredImage = output
                }
            }
        }
        
        guard let outputPixelBuffer = asyncVideoCompositionRequest.renderContext.newPixelBuffer() else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "ImageAwareCompositor", code: -2))
            return
        }
        
        context.render(filteredImage, to: outputPixelBuffer)
        asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    private func findImageSegment(at time: CMTime) -> (url: URL, duration: CMTime)? {
        for (startTime, segment) in imageSegmentsByTime {
            let endTime = CMTimeAdd(startTime, segment.duration)
            if CMTimeCompare(time, startTime) >= 0 && CMTimeCompare(time, endTime) < 0 {
                return segment
            }
        }
        return nil
    }
    
    private func renderImage(_ imageURL: URL, at time: CMTime, request: AVAsynchronousVideoCompositionRequest, opacity: Float = 1.0) {
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            renderBlackFrame(request: request)
            return
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let renderSize = request.renderContext.size
        
        // Scale image to fill render size (modern crop-to-fill style)
        let imageAspect = ciImage.extent.width / ciImage.extent.height
        let renderAspect = renderSize.width / renderSize.height
        
        var scale: CGFloat
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        
        if imageAspect > renderAspect {
            // Image is wider - scale to height and crop sides
            scale = renderSize.height / ciImage.extent.height
            let scaledWidth = ciImage.extent.width * scale
            xOffset = (renderSize.width - scaledWidth) / 2
        } else {
            // Image is taller - scale to width and crop top/bottom
            scale = renderSize.width / ciImage.extent.width
            let scaledHeight = ciImage.extent.height * scale
            yOffset = (renderSize.height - scaledHeight) / 2
        }
        
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
        
        // Apply color correction
        let settings = globalColorSettings
        var filteredImage = centeredImage
        
        if settings.exposure != 0.0 {
            if let filter = CIFilter(name: "CIExposureAdjust") {
                filter.setValue(filteredImage, forKey: kCIInputImageKey)
                filter.setValue(settings.exposure, forKey: kCIInputEVKey)
                if let output = filter.outputImage {
                    filteredImage = output
                }
            }
        }
        
        if settings.contrast != 1.0 || settings.saturation != 1.0 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(filteredImage, forKey: kCIInputImageKey)
                filter.setValue(settings.contrast, forKey: kCIInputContrastKey)
                filter.setValue(settings.saturation, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    filteredImage = output
                }
            }
        }
        
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "ImageAwareCompositor", code: -2))
            return
        }
        
        context.render(filteredImage, to: outputPixelBuffer, bounds: CGRect(origin: .zero, size: renderSize), colorSpace: nil)
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    private func renderBlackFrame(request: AVAsynchronousVideoCompositionRequest) {
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "ImageAwareCompositor", code: -2))
            return
        }
        
        CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputPixelBuffer, []) }
        
        let width = CVPixelBufferGetWidth(outputPixelBuffer)
        let height = CVPixelBufferGetHeight(outputPixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(outputPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputPixelBuffer)
        
        if let base = baseAddress {
            memset(base, 0, height * bytesPerRow)
        }
        
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    func cancelAllPendingVideoCompositionRequests() {
        // No-op for v1
    }
}

