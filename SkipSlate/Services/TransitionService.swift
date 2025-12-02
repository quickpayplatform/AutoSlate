//
//  TransitionService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation

class TransitionService {
    static let shared = TransitionService()
    
    // Default transition duration: 0.2 seconds
    static let defaultTransitionDuration = CMTime(seconds: 0.2, preferredTimescale: 600)
    
    /// Get transition duration from project settings or use default
    private func transitionDuration(for project: Project) -> CMTime {
        if let settings = project.autoEditSettings {
            return CMTime(seconds: settings.transitionDuration, preferredTimescale: 600)
        }
        return Self.defaultTransitionDuration
    }
    
    private init() {}
    
    /// Creates an audio mix with crossfades at segment boundaries
    /// Music tracks (from audio-only clips) are kept at constant full volume with no transitions
    func createAudioMixWithTransitions(
        for composition: AVMutableComposition,
        segments: [Segment],
        project: Project? = nil
    ) -> AVAudioMix? {
        let audioTracks = composition.tracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            print("SkipSlate: TransitionService - No audio tracks found in composition")
            return nil
        }
        
        print("SkipSlate: TransitionService - Found \(audioTracks.count) audio track(s), creating audio mix")
        
        // Identify music tracks (from audio-only clips) - these should NOT have transitions
        var musicTrackIDs: Set<CMPersistentTrackID> = []
        if let project = project {
            let audioOnlyClips = project.clips.filter { $0.type == .audioOnly }
            // For Highlight Reel, Music Video, Dance Video, the first audio-only clip is the music
            if project.type == .highlightReel || project.type == .musicVideo || project.type == .danceVideo {
                if let musicClip = audioOnlyClips.first {
                    // Find the audio track that contains this music clip
                    // We'll identify it by checking if it spans the full composition duration
                    // (music tracks are inserted for full duration, video audio is per-segment)
                    for track in audioTracks {
                        let trackDuration = CMTimeGetSeconds(track.timeRange.duration)
                        let compositionDuration = CMTimeGetSeconds(composition.duration)
                        // Music track should span close to full composition duration
                        if abs(trackDuration - compositionDuration) < 1.0 {
                            musicTrackIDs.insert(track.trackID)
                            print("SkipSlate: TransitionService - Identified music track: ID \(track.trackID) (duration: \(trackDuration)s, composition: \(compositionDuration)s)")
                        }
                    }
                }
            }
        }
        
        let audioMix = AVMutableAudioMix()
        var inputParametersList: [AVMutableAudioMixInputParameters] = []
        
        // Create input parameters for each audio track
        for audioTrack in audioTracks {
            let inputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
            let isMusicTrack = musicTrackIDs.contains(audioTrack.trackID)
            
            // CRITICAL: Set default volume to 1.0 for the entire track
            let compositionDuration = composition.duration
            if compositionDuration.isValid && compositionDuration > .zero {
                // Set volume at start and end to maintain 1.0 throughout
                inputParameters.setVolume(1.0, at: .zero)
                inputParameters.setVolume(1.0, at: compositionDuration)
                
                if isMusicTrack {
                    print("SkipSlate: TransitionService - Set constant volume 1.0 for MUSIC track ID \(audioTrack.trackID) (NO transitions)")
                } else {
                    print("SkipSlate: TransitionService - Set base volume 1.0 for track ID \(audioTrack.trackID)")
                }
            } else {
                inputParameters.setVolume(1.0, at: .zero)
                if isMusicTrack {
                    print("SkipSlate: TransitionService - Set constant volume 1.0 for MUSIC track ID \(audioTrack.trackID) (NO transitions, fallback)")
                } else {
                    print("SkipSlate: TransitionService - Set base volume 1.0 for track ID \(audioTrack.trackID) (fallback)")
                }
            }
            
            // CRITICAL: Music tracks should play continuously, but fade out at the end
            if isMusicTrack {
                // Music plays at full volume throughout, but fade out in the last 2 seconds
                let compositionDuration = composition.duration
                if compositionDuration.isValid && compositionDuration.seconds > 2.0 {
                    let fadeOutStart = CMTimeSubtract(compositionDuration, CMTime(seconds: 2.0, preferredTimescale: 600))
                    inputParameters.setVolumeRamp(
                        fromStartVolume: 1.0,
                        toEndVolume: 0.0,
                        timeRange: CMTimeRange(start: fadeOutStart, end: compositionDuration)
                    )
                    print("SkipSlate: TransitionService - Added fade-out to music track (last 2 seconds)")
                }
                print("SkipSlate: TransitionService - Music track plays continuously with fade-out at end")
                inputParametersList.append(inputParameters)
                continue
            }
            
            // Apply transitions only to video audio tracks
            var currentTime = CMTime.zero
            let transitionDuration = TransitionService.defaultTransitionDuration
            
            for (index, segment) in segments.enumerated() {
                let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
                let segmentEnd = CMTimeAdd(currentTime, segmentDuration)
                
                // Only apply transitions if segment is long enough (at least 2x transition duration)
                let minDurationForTransition = transitionDuration.seconds * 2
                let canHaveTransition = segmentDuration.seconds >= minDurationForTransition
                
                if canHaveTransition {
                    // Apply fade-in at the start (except for first segment)
                    if index > 0 {
                        let fadeInEnd = CMTimeAdd(currentTime, transitionDuration)
                        inputParameters.setVolumeRamp(
                            fromStartVolume: 0.0,
                            toEndVolume: 1.0,
                            timeRange: CMTimeRange(start: currentTime, end: fadeInEnd)
                        )
                        print("SkipSlate: TransitionService - Added fade-in at \(CMTimeGetSeconds(currentTime))s")
                    }
                    
                    // Apply fade-out at the end (except for last segment)
                    if index < segments.count - 1 {
                        let fadeOutStart = CMTimeSubtract(segmentEnd, transitionDuration)
                        // Ensure fade-out doesn't overlap with fade-in
                        let fadeInEnd = index > 0 ? CMTimeAdd(currentTime, transitionDuration) : currentTime
                        if fadeOutStart > fadeInEnd {
                            inputParameters.setVolumeRamp(
                                fromStartVolume: 1.0,
                                toEndVolume: 0.0,
                                timeRange: CMTimeRange(start: fadeOutStart, end: segmentEnd)
                            )
                            print("SkipSlate: TransitionService - Added fade-out at \(CMTimeGetSeconds(fadeOutStart))s")
                        }
                    }
                }
                
                currentTime = segmentEnd
            }
            
            inputParametersList.append(inputParameters)
        }
        
        audioMix.inputParameters = inputParametersList
        print("SkipSlate: TransitionService - Created audio mix with \(inputParametersList.count) input parameter(s)")
        return audioMix
    }
    
    /// Creates video composition instructions with cross-dissolve transitions
    /// CRITICAL: If resolution/aspectRatio are provided, use them; otherwise use project settings
    /// This ensures export can use different resolution while maintaining the same framing/scaling as preview
    func createVideoCompositionWithTransitions(
        for composition: AVMutableComposition,
        segments: [Segment],
        project: Project,
        resolution: ResolutionPreset? = nil,
        aspectRatio: AspectRatio? = nil
    ) -> AVMutableVideoComposition? {
        // Get all video tracks - we need to find the one with actual video content
        // The first track is usually the main video track, but we should verify
        let allVideoTracks = composition.tracks(withMediaType: .video)
        let videoTrack = allVideoTracks.first { track in
            // Prefer tracks that have time ranges (actual content)
            return track.timeRange.duration > .zero
        } ?? allVideoTracks.first
        
        if let track = videoTrack {
            print("SkipSlate: TransitionService - Selected main video track ID: \(track.trackID), duration: \(CMTimeGetSeconds(track.timeRange.duration))s, naturalSize: \(track.naturalSize)")
        }
        
        // Determine render size - use provided resolution or fall back to project settings
        let effectiveResolution = resolution ?? project.resolution
        let effectiveAspectRatio = aspectRatio ?? project.aspectRatio
        var renderSize = CGSize(width: effectiveResolution.width, height: effectiveResolution.height)
        
        // Verify aspect ratio matches
        let presetRatio = Double(effectiveResolution.width) / Double(effectiveResolution.height)
        let targetRatio = effectiveAspectRatio.ratio
        let ratioDiff = abs(presetRatio - targetRatio)
        
        // If aspect ratio doesn't match, adjust dimensions to fit
        if ratioDiff > 0.01 {
            // Adjust to match aspect ratio while maintaining resolution quality
            if presetRatio > targetRatio {
                // Preset is wider - adjust height
                renderSize.height = CGFloat(Double(renderSize.width) / targetRatio)
            } else {
                // Preset is taller - adjust width
                renderSize.width = CGFloat(Double(renderSize.height) * targetRatio)
            }
        }
        
        // Fallback: if no project resolution, use track natural size
        if renderSize.width == 0 || renderSize.height == 0 {
            if let track = videoTrack {
                let naturalSize = track.naturalSize
                if naturalSize.width > 0 && naturalSize.height > 0 {
                    renderSize = naturalSize
                }
            }
            // Final fallback
            if renderSize.width == 0 || renderSize.height == 0 {
                renderSize = CGSize(width: 1920, height: 1080)
            }
        }
        
        // Calculate total duration from segments if composition duration is 0
        var compositionDuration = composition.duration
        if compositionDuration.seconds == 0 && !segments.isEmpty {
            var totalDuration = CMTime.zero
            for segment in segments {
                totalDuration = CMTimeAdd(totalDuration, CMTime(seconds: segment.duration, preferredTimescale: 600))
            }
            compositionDuration = totalDuration
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 24) // 24fps for frame-accurate timeline
        
        var instructions: [AVMutableVideoCompositionInstruction] = []
        let transitionDuration = TransitionService.defaultTransitionDuration
        
        // Get all video tracks for logging and fallback
        let allVideoTracksForFallback = composition.tracks(withMediaType: .video)
        print("SkipSlate: TransitionService - Found \(allVideoTracksForFallback.count) video tracks in composition")
        
        // CRITICAL: For highlight reels, detect overlay track for video stacking
        var overlayTrack: AVCompositionTrack?
        if project.type == .highlightReel {
            // Find overlay track (should be the last video track, or one that's not the main track)
            let mainTrackID = videoTrack?.trackID
            overlayTrack = allVideoTracksForFallback.first { track in
                track.trackID != mainTrackID && track.timeRange.duration > .zero
            }
            if let overlay = overlayTrack {
                print("SkipSlate: TransitionService - Found overlay track (ID: \(overlay.trackID)) for highlight reel video stacking")
            }
        }
        
        // For image-only compositions, use the image timing track
        let imageTimingTrack = allVideoTracksForFallback.first { track in
            // Check if this is the image timing track (has segments but might be different from main video track)
            return track != videoTrack && track != overlayTrack
        }
        
        // Prefer the main video track, but fall back to image timing track or first available track
        let trackToUse = videoTrack ?? imageTimingTrack ?? allVideoTracksForFallback.first
        
        if let track = trackToUse {
            print("SkipSlate: TransitionService - Using video track ID: \(track.trackID), naturalSize: \(track.naturalSize)")
        } else {
            print("SkipSlate: TransitionService - WARNING: No video track found!")
        }
        
        // For image-only compositions, create instructions using the image timing track
        if !imageSegmentsByTime.isEmpty && videoTrack == nil, let track = imageTimingTrack {
            // Create one instruction per image segment with transitions
            var currentTime = CMTime.zero
            
            for (index, segment) in segments.enumerated() {
                let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
                let segmentEnd = CMTimeAdd(currentTime, segmentDuration)
                
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: currentTime, duration: segmentDuration)
                
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                
                // Apply modern transitions for image segments - crossfade with zoom
                let minDurationForTransition = transitionDuration.seconds * 2
                let canHaveTransition = segmentDuration.seconds >= minDurationForTransition
                
                if canHaveTransition {
                    // Modern crossfade transitions with zoom effects
                    if index > 0 {
                        // Fade in with subtle zoom in
                        let fadeInEnd = CMTimeAdd(currentTime, transitionDuration)
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 0.0,
                            toEndOpacity: 1.0,
                            timeRange: CMTimeRange(start: currentTime, end: fadeInEnd)
                        )
                        
                        // Subtle zoom-in effect (1.05 to 1.0)
                        let scaleStart = CGAffineTransform(scaleX: 1.05, y: 1.05)
                        let scaleEnd = CGAffineTransform(scaleX: 1.0, y: 1.0)
                        layerInstruction.setTransformRamp(
                            fromStart: scaleStart,
                            toEnd: scaleEnd,
                            timeRange: CMTimeRange(start: currentTime, end: fadeInEnd)
                        )
                    }
                    
                    if index < segments.count - 1 {
                        // Fade out with subtle zoom out
                        let fadeOutStart = CMTimeSubtract(segmentEnd, transitionDuration)
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 1.0,
                            toEndOpacity: 0.0,
                            timeRange: CMTimeRange(start: fadeOutStart, end: segmentEnd)
                        )
                        
                        // Subtle zoom-out effect (1.0 to 0.95)
                        let scaleStart = CGAffineTransform(scaleX: 1.0, y: 1.0)
                        let scaleEnd = CGAffineTransform(scaleX: 0.95, y: 0.95)
                        layerInstruction.setTransformRamp(
                            fromStart: scaleStart,
                            toEnd: scaleEnd,
                            timeRange: CMTimeRange(start: fadeOutStart, end: segmentEnd)
                        )
                    }
                }
                
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
                
                currentTime = segmentEnd
            }
        } else if let track = trackToUse {
            // Create per-segment instructions for proper video rendering
            // This ensures each segment is properly rendered
            var currentTime = CMTime.zero
            
            // Check if fade-to-black is enabled to handle last segment properly
            let fadeToBlackEnabled = project.autoEditSettings?.enableFadeToBlack ?? false
            let fadeDuration = fadeToBlackEnabled ? CMTime(seconds: project.autoEditSettings?.fadeToBlackDuration ?? 2.0, preferredTimescale: 600) : .zero
            let fadeStart = fadeToBlackEnabled && compositionDuration.seconds > fadeDuration.seconds 
                ? CMTimeSubtract(compositionDuration, fadeDuration) 
                : compositionDuration
            
            print("SkipSlate: TransitionService - Creating instructions for track ID: \(track.trackID), naturalSize: \(track.naturalSize)")
            
            for (index, segment) in segments.enumerated() {
                let segmentDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
                guard segmentDuration > .zero else { continue }
                
                let segmentEnd = CMTimeAdd(currentTime, segmentDuration)
                let segmentTimeRange = CMTimeRange(start: currentTime, duration: segmentDuration)
                let isLastSegment = (index == segments.count - 1)
                
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = segmentTimeRange
                
                // Create layer instructions - main track first
                var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
                
                // Main video track layer
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                
                // Apply Scale to Fill Frame transform if enabled for this segment
                if segment.transform.scaleToFillFrame {
                    // Use the track's natural size (already has preferredTransform applied)
                    let sourceSize = track.naturalSize
                    let projectSize = CGSize(width: project.resolution.width, height: project.resolution.height)
                    
                    // Calculate scale to fill transform
                    let scaleTransform = transformForScaleToFill(
                        sourceSize: sourceSize,
                        projectSize: projectSize
                    )
                    
                    // Apply transform at segment start time
                    // The track already has preferredTransform baked in, so we just apply our scale transform
                    layerInstruction.setTransform(scaleTransform, at: currentTime)
                    
                    print("SkipSlate: TransitionService - Applied Scale to Fill Frame transform for segment \(index) (source: \(sourceSize), project: \(projectSize))")
                }
                // If scaleToFillFrame is false, don't set transform - let AVFoundation use track's preferredTransform
                
                // CRITICAL: Handle opacity carefully to avoid overlapping ramps
                if isLastSegment && fadeToBlackEnabled && fadeStart < segmentEnd {
                    // Last segment with fade-to-black - set up opacity properly
                    // If fade starts within this segment, we need a combined ramp
                    if fadeStart > currentTime {
                        // Fade starts within this segment - set constant opacity until fade, then fade out
                        layerInstruction.setOpacity(1.0, at: currentTime)
                        layerInstruction.setOpacity(1.0, at: fadeStart)
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 1.0,
                            toEndOpacity: 0.0,
                            timeRange: CMTimeRange(start: fadeStart, end: segmentEnd)
                        )
                        print("SkipSlate: TransitionService - Last segment with fade-to-black: constant 1.0 until \(CMTimeGetSeconds(fadeStart))s, then fade to 0.0")
                    } else {
                        // Fade starts before this segment (shouldn't happen, but handle it)
                        layerInstruction.setOpacityRamp(
                            fromStartOpacity: 1.0,
                            toEndOpacity: 0.0,
                            timeRange: segmentTimeRange
                        )
                    }
                } else {
                    // Regular segment - set constant opacity (no ramp needed, just set at start)
                    layerInstruction.setOpacity(1.0, at: currentTime)
                    if !isLastSegment {
                        layerInstruction.setOpacity(1.0, at: segmentEnd)
                    }
                }
                
                layerInstructions.append(layerInstruction)
                
                // CRITICAL: For highlight reels, add overlay track layer if it has content at this time
                if project.type == .highlightReel, let overlay = overlayTrack {
                    // Check if overlay track has content at this time range
                    let overlayTimeRange = overlay.timeRange
                    let overlayStart = overlayTimeRange.start
                    let overlayEnd = CMTimeRangeGetEnd(overlayTimeRange)
                    let intersection = overlayTimeRange.intersection(segmentTimeRange)
                    let hasOverlayContent = (CMTimeCompare(currentTime, overlayStart) >= 0 && CMTimeCompare(currentTime, overlayEnd) < 0) ||
                                            intersection.duration > .zero
                    
                    if hasOverlayContent {
                        let overlayLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: overlay)
                        // Overlay should be fully opaque (it fills black space)
                        overlayLayerInstruction.setOpacity(1.0, at: currentTime)
                        if !isLastSegment {
                            overlayLayerInstruction.setOpacity(1.0, at: segmentEnd)
                        }
                        layerInstructions.append(overlayLayerInstruction)
                        print("SkipSlate: TransitionService - Added overlay layer for highlight reel video stacking at \(CMTimeGetSeconds(currentTime))s")
                    }
                }
                
                instruction.layerInstructions = layerInstructions
                instructions.append(instruction)
                
                if index < 3 || index == segments.count - 1 {
                    print("SkipSlate: TransitionService - Instruction \(index + 1)/\(segments.count): timeRange=\(CMTimeGetSeconds(segmentTimeRange.start))-\(CMTimeGetSeconds(CMTimeRangeGetEnd(segmentTimeRange)))s, trackID=\(track.trackID)")
                }
                
                currentTime = segmentEnd
            }
            
            print("SkipSlate: TransitionService - Created video composition with \(instructions.count) instructions for trackID: \(track.trackID)")
        } else {
            // No video track and no images - create empty instruction
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
            instruction.layerInstructions = []
            instructions.append(instruction)
        }
        
        videoComposition.instructions = instructions
        
        // Use appropriate compositor
        // Only use custom compositor if we have images OR if we need color correction
        let needsColorCorrection = project.colorSettings.exposure != 0.0 || 
                                   project.colorSettings.contrast != 1.0 || 
                                   project.colorSettings.saturation != 1.0
        
        if !imageSegmentsByTime.isEmpty {
            videoComposition.customVideoCompositorClass = ImageAwareCompositor.self
        } else if needsColorCorrection {
            // Only use custom compositor if color correction is needed
            videoComposition.customVideoCompositorClass = ColorCorrectionCompositor.self
        } else {
            // No custom compositor - let AVFoundation handle it natively
            // This is more reliable for video-only compositions without color correction
            videoComposition.customVideoCompositorClass = nil
        }
        
        return videoComposition
    }
    
    // MARK: - Transform Calculations
    
    /// Calculate transform to scale and center-crop video to fill project frame
    /// - Parameters:
    ///   - sourceSize: Natural size of the source video (after preferredTransform)
    ///   - projectSize: Target project frame size
    /// - Returns: CGAffineTransform that scales and centers the video to fill the frame
    func transformForScaleToFill(sourceSize: CGSize, projectSize: CGSize) -> CGAffineTransform {
        // Use absolute sizes
        let srcWidth = abs(sourceSize.width)
        let srcHeight = abs(sourceSize.height)
        let projWidth = projectSize.width
        let projHeight = projectSize.height
        
        guard srcWidth > 0, srcHeight > 0, projWidth > 0, projHeight > 0 else {
            print("SkipSlate: ⚠️ Invalid sizes for Scale to Fill - source: \(sourceSize), project: \(projectSize)")
            return .identity
        }
        
        // Calculate scale factor to fill frame (scale to cover, not fit)
        let scaleX = projWidth / srcWidth
        let scaleY = projHeight / srcHeight
        let scale = max(scaleX, scaleY)  // Use larger scale to ensure full coverage
        
        // Calculate scaled dimensions
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale
        
        // Center the scaled image in the project frame
        // Translation is applied in the scaled coordinate space
        let tx = (projWidth - scaledWidth) / 2.0
        let ty = (projHeight - scaledHeight) / 2.0
        
        // Build transform: scale first, then translate
        var t = CGAffineTransform.identity
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: tx / scale, y: ty / scale)
        
        return t
    }
}

