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
        // Get all video tracks from composition
        let allVideoTracks = composition.tracks(withMediaType: .video)
        
        // CRITICAL FIX: Build mapping from timeline tracks to composition tracks
        // Composition tracks are created in the same order as timeline tracks
        let videoTimelineTracks = project.tracks.filter { $0.kind == .video }
        var timelineTrackToCompositionTrack: [UUID: AVMutableCompositionTrack] = [:]
        
        // Map timeline tracks to composition tracks by order (excluding image timing track at the end)
        // Composition tracks are created: video tracks first (in timeline order), then imageTimingTrack
        // So we match by index, skipping the last track if there are more composition tracks than timeline tracks
        let compositionVideoTracksCount = min(allVideoTracks.count, videoTimelineTracks.count)
        for i in 0..<compositionVideoTracksCount {
            let timelineTrack = videoTimelineTracks[i]
            let compositionTrack = allVideoTracks[i]
            timelineTrackToCompositionTrack[timelineTrack.id] = compositionTrack
            print("SkipSlate: TransitionService - Mapped timeline track \(timelineTrack.name) (index: \(timelineTrack.index)) to composition track ID: \(compositionTrack.trackID)")
        }
        
        // Build mapping from segment ID to timeline track
        var segmentToTimelineTrack: [UUID: TimelineTrack] = [:]
        for track in videoTimelineTracks {
            for segmentID in track.segments {
                segmentToTimelineTrack[segmentID] = track
            }
        }
        
        // Get the "main" video track for render size calculation (fallback for track properties)
        let videoTrack = allVideoTracks.first { track in
            // Prefer tracks that have time ranges (actual content)
            return track.timeRange.duration > .zero
        } ?? allVideoTracks.first
        
        if let track = videoTrack {
            print("SkipSlate: TransitionService - Main video track ID: \(track.trackID), duration: \(CMTimeGetSeconds(track.timeRange.duration))s, naturalSize: \(track.naturalSize)")
        }
        print("SkipSlate: TransitionService - Found \(allVideoTracks.count) composition tracks, \(videoTimelineTracks.count) timeline tracks, \(timelineTrackToCompositionTrack.count) mapped")
        
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
        
        // NOTE: Hidden overlay video stacking REMOVED - preview only shows what's in timeline segments
        // If users want layered videos, they should manually add V2 tracks with segments
        
        // For image-only compositions, use the image timing track
        let imageTimingTrack = allVideoTracksForFallback.first { track in
            // Check if this is the image timing track (has segments but might be different from main video track)
            return track != videoTrack
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
        } else if !timelineTrackToCompositionTrack.isEmpty || trackToUse != nil {
            // MULTI-TRACK AWARE: Create per-segment instructions that include ALL active tracks
            // This ensures segments on V2 are rendered on top of V1, etc.
            
            // Check if fade-to-black is enabled to handle last segment properly
            let fadeToBlackEnabled = project.autoEditSettings?.enableFadeToBlack ?? false
            let fadeDuration = fadeToBlackEnabled ? CMTime(seconds: project.autoEditSettings?.fadeToBlackDuration ?? 2.0, preferredTimescale: 600) : .zero
            let fadeStart = fadeToBlackEnabled && compositionDuration.seconds > fadeDuration.seconds 
                ? CMTimeSubtract(compositionDuration, fadeDuration) 
                : compositionDuration
            
            // Group video segments by their composition start time to find overlapping segments
            // Also track which composition track each segment uses
            struct SegmentWithTrack {
                let segment: Segment
                let compositionTrack: AVMutableCompositionTrack
                let timelineTrackIndex: Int
            }
            
            var segmentsWithTracks: [SegmentWithTrack] = []
            for segment in segments {
                // Skip non-video segments
                guard segment.kind == .clip else { continue }
                
                // Find which timeline track this segment belongs to
                if let timelineTrack = segmentToTimelineTrack[segment.id],
                   let compositionTrack = timelineTrackToCompositionTrack[timelineTrack.id] {
                    segmentsWithTracks.append(SegmentWithTrack(
                        segment: segment,
                        compositionTrack: compositionTrack,
                        timelineTrackIndex: timelineTrack.index
                    ))
                } else if let fallbackTrack = trackToUse {
                    // Fallback: use the main track if no mapping found
                    segmentsWithTracks.append(SegmentWithTrack(
                        segment: segment,
                        compositionTrack: fallbackTrack,
                        timelineTrackIndex: 0
                    ))
                }
            }
            
            print("SkipSlate: TransitionService - Processing \(segmentsWithTracks.count) video segments for multi-track composition")
            
            // Build time-based instruction map
            // For each unique time range, collect all active segments and create one instruction with all layer instructions
            // Sort segments by their composition start time
            segmentsWithTracks.sort { $0.segment.compositionStartTime < $1.segment.compositionStartTime }
            
            // Create instructions based on time ranges where segment combinations change
            var timeEvents: [(time: Double, isStart: Bool, segmentIndex: Int)] = []
            for (index, swt) in segmentsWithTracks.enumerated() {
                let startTime = swt.segment.compositionStartTime >= 0 ? swt.segment.compositionStartTime : 0
                let endTime = startTime + swt.segment.duration
                timeEvents.append((time: startTime, isStart: true, segmentIndex: index))
                timeEvents.append((time: endTime, isStart: false, segmentIndex: index))
            }
            timeEvents.sort { $0.time < $1.time }
            
            // Process time events to create instructions for each unique time range
            var activeSegmentIndices = Set<Int>()
            var lastTime: Double = 0
            
            for (eventIndex, event) in timeEvents.enumerated() {
                // Skip duplicate times (handled by next event)
                if eventIndex > 0 && event.time == timeEvents[eventIndex - 1].time {
                    if event.isStart {
                        activeSegmentIndices.insert(event.segmentIndex)
                    } else {
                        activeSegmentIndices.remove(event.segmentIndex)
                    }
                    continue
                }
                
                // Create instruction for time range [lastTime, event.time) - both for active segments AND gaps
                if lastTime < event.time {
                    let timeRange = CMTimeRange(
                        start: CMTime(seconds: lastTime, preferredTimescale: 600),
                        duration: CMTime(seconds: event.time - lastTime, preferredTimescale: 600)
                    )
                    
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = timeRange
                    
                    if !activeSegmentIndices.isEmpty {
                        // Create layer instructions for all active segments
                        // CRITICAL: AVFoundation renders layer instructions with FIRST = TOP (foreground), LAST = BOTTOM (background)
                        // So we need HIGHER track indices FIRST (V2 on top/foreground) and LOWER indices LAST (V1 at bottom/background)
                        // V1 = base/background layer, V2+ = overlay/foreground layers
                        let activeSegments = activeSegmentIndices.map { segmentsWithTracks[$0] }
                            .sorted { $0.timelineTrackIndex > $1.timelineTrackIndex } // V2 first (top/foreground), V1 last (bottom/background)
                        
                        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
                        
                        for swt in activeSegments {
                            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: swt.compositionTrack)
                            let segment = swt.segment
                            let currentTime = CMTime(seconds: lastTime, preferredTimescale: 600)
                            let segmentEnd = CMTime(seconds: event.time, preferredTimescale: 600)
                            
                            // Check if this segment has transform effects
                            let hasTransformEffects = segment.effects.scale != 1.0 || 
                                                     segment.effects.positionX != 0.0 || 
                                                     segment.effects.positionY != 0.0 || 
                                                     segment.effects.rotation != 0.0 || 
                                                     segment.transform.scaleToFillFrame ||
                                                     segment.effects.compositionMode != .fit ||
                                                     segment.effects.compositionAnchor != .center
                            
                            if hasTransformEffects {
                                let finalTransform = calculateCompleteTransform(
                                    for: segment,
                                    track: swt.compositionTrack,
                                    project: project
                                )
                                layerInstruction.setTransform(finalTransform, at: currentTime)
                            }
                            
                            // Handle opacity - full opacity for all segments
                            let isInFadeRange = fadeToBlackEnabled && fadeStart.seconds <= event.time
                            if isInFadeRange {
                                // Apply fade to black
                                if fadeStart.seconds > lastTime {
                                    layerInstruction.setOpacity(1.0, at: currentTime)
                                    layerInstruction.setOpacityRamp(
                                        fromStartOpacity: 1.0,
                                        toEndOpacity: 0.0,
                                        timeRange: CMTimeRange(start: fadeStart, end: segmentEnd)
                                    )
                                } else {
                                    let fadeProgress = (lastTime - fadeStart.seconds) / fadeDuration.seconds
                                    let startOpacity = max(0, 1.0 - Float(fadeProgress))
                                    let endProgress = (event.time - fadeStart.seconds) / fadeDuration.seconds
                                    let endOpacity = max(0, 1.0 - Float(endProgress))
                                    layerInstruction.setOpacityRamp(
                                        fromStartOpacity: startOpacity,
                                        toEndOpacity: endOpacity,
                                        timeRange: timeRange
                                    )
                                }
                            } else {
                                layerInstruction.setOpacity(1.0, at: currentTime)
                            }
                            
                            layerInstructions.append(layerInstruction)
                        }
                        
                        instruction.layerInstructions = layerInstructions
                        
                        if instructions.count <= 3 || eventIndex == timeEvents.count - 1 {
                            let trackDesc = activeSegments.map { "V\($0.timelineTrackIndex)" }.joined(separator: "+")
                            print("SkipSlate: TransitionService - Instruction \(instructions.count + 1): time=\(lastTime)-\(event.time)s, tracks=[\(trackDesc)]")
                        }
                    } else {
                        // GAP: No active segments - empty layer instructions = black screen
                        instruction.layerInstructions = []
                        print("SkipSlate: TransitionService - Gap instruction: time=\(lastTime)-\(event.time)s (no active segments)")
                    }
                    
                    instructions.append(instruction)
                }
                
                // Update active segments
                if event.isStart {
                    activeSegmentIndices.insert(event.segmentIndex)
                } else {
                    activeSegmentIndices.remove(event.segmentIndex)
                }
                lastTime = event.time
            }
            
            // CRITICAL: Ensure instructions cover the ENTIRE composition duration
            // AVFoundation requires video composition instructions to cover the full duration
            // Add a final instruction if the last segment ends before composition duration
            let compositionDurationSeconds = compositionDuration.seconds
            if lastTime < compositionDurationSeconds {
                let gapTimeRange = CMTimeRange(
                    start: CMTime(seconds: lastTime, preferredTimescale: 600),
                    duration: CMTime(seconds: compositionDurationSeconds - lastTime, preferredTimescale: 600)
                )
                let gapInstruction = AVMutableVideoCompositionInstruction()
                gapInstruction.timeRange = gapTimeRange
                // Empty layer instructions = black screen for gaps beyond content
                gapInstruction.layerInstructions = []
                instructions.append(gapInstruction)
                print("SkipSlate: TransitionService - Added gap instruction: time=\(lastTime)-\(compositionDurationSeconds)s (end padding)")
            }
            
            // Also check for gaps at the beginning (if first segment doesn't start at 0)
            if let firstInstruction = instructions.first,
               firstInstruction.timeRange.start.seconds > 0 {
                let gapTimeRange = CMTimeRange(
                    start: .zero,
                    duration: firstInstruction.timeRange.start
                )
                let gapInstruction = AVMutableVideoCompositionInstruction()
                gapInstruction.timeRange = gapTimeRange
                gapInstruction.layerInstructions = []
                instructions.insert(gapInstruction, at: 0)
                print("SkipSlate: TransitionService - Added gap instruction: time=0.0-\(firstInstruction.timeRange.start.seconds)s (start padding)")
            }
            
            print("SkipSlate: TransitionService - Created \(instructions.count) multi-track instructions (covering full duration: \(compositionDurationSeconds)s)")
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
    
    /// Calculate complete transform for a segment, combining all transform effects
    /// - Parameters:
    ///   - segment: The segment with transform settings
    ///   - track: The video track (for preferredTransform and natural size)
    ///   - project: The project (for resolution)
    /// - Returns: Complete CGAffineTransform combining all effects
    func calculateCompleteTransform(
        for segment: Segment,
        track: AVAssetTrack,
        project: Project
    ) -> CGAffineTransform {
        print("SkipSlate: [Transform DEBUG] calculateCompleteTransform – start for segment id=\(segment.id)")
        
        let projectSize = CGSize(width: project.resolution.width, height: project.resolution.height)
        let projWidth = projectSize.width
        let projHeight = projectSize.height
        
        // CRITICAL: Use oriented source size (respect preferredTransform)
        // Apply preferredTransform to naturalSize to get the oriented dimensions
        let orientedSize = track.naturalSize.applying(track.preferredTransform)
        let srcWidth = abs(orientedSize.width)
        let srcHeight = abs(orientedSize.height)
        
        // Validate sizes
        guard srcWidth > 0, srcHeight > 0, projWidth > 0, projHeight > 0 else {
            print("SkipSlate: ⚠️ Invalid sizes for transform - oriented source: \(orientedSize), project: \(projectSize)")
            return track.preferredTransform // Return preferredTransform only
        }
        
        let centerX = projWidth / 2.0
        let centerY = projHeight / 2.0
        
        // CRITICAL: Build transforms in correct order
        // Transform concatenation: A.concatenating(B) means B is applied first, then A
        // Visual order: Composition Mode -> Scale to Fill -> Manual Scale -> Rotation -> Position -> preferredTransform
        // Build order (reverse): Start with identity, then add each transform
        
        var transform = CGAffineTransform.identity
        
        // Step 0: Apply Composition Mode (Fit, Fill, Letterbox)
        // This is the base transform that determines how the video fits in the frame
        let compositionTransform = calculateCompositionModeTransform(
            sourceSize: CGSize(width: srcWidth, height: srcHeight),
            projectSize: projectSize,
            mode: segment.effects.compositionMode,
            anchor: segment.effects.compositionAnchor
        )
        transform = transform.concatenating(compositionTransform)
        print("SkipSlate: [Transform DEBUG] Applied compositionMode: \(segment.effects.compositionMode), anchor: \(segment.effects.compositionAnchor)")
        
        // Step 1: Scale to Fill Frame (if enabled) - overrides composition mode
        if segment.transform.scaleToFillFrame {
            // Reset and apply scale-to-fill
            transform = CGAffineTransform.identity
            let scaleX = projWidth / srcWidth
            let scaleY = projHeight / srcHeight
            let scale = max(scaleX, scaleY) // Use larger scale to ensure full coverage
            
            let scaledWidth = srcWidth * scale
            let scaledHeight = srcHeight * scale
            let tx = (projWidth - scaledWidth) / 2.0
            let ty = (projHeight - scaledHeight) / 2.0
            
            var t = CGAffineTransform.identity
            t = t.scaledBy(x: scale, y: scale)
            t = t.translatedBy(x: tx / scale, y: ty / scale)
            transform = transform.concatenating(t)
        }
        
        // Step 2: Manual scale around project center
        if segment.effects.scale != 1.0 {
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: centerX, y: centerY)
            t = t.scaledBy(x: segment.effects.scale, y: segment.effects.scale)
            t = t.translatedBy(x: -centerX, y: -centerY)
            transform = transform.concatenating(t)
        }
        
        // Step 3: Rotation around project center
        if segment.effects.rotation != 0.0 {
            let radians = segment.effects.rotation * .pi / 180.0
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: centerX, y: centerY)
            t = t.rotated(by: radians)
            t = t.translatedBy(x: -centerX, y: -centerY)
            transform = transform.concatenating(t)
        }
        
        // Step 4: Position offset (percent of project size)
        if segment.effects.positionX != 0.0 || segment.effects.positionY != 0.0 {
            let tx = (segment.effects.positionX / 100.0) * projWidth
            let ty = (segment.effects.positionY / 100.0) * projHeight
            let t = CGAffineTransform(translationX: tx, y: ty)
            transform = transform.concatenating(t)
        }
        
        // Step 5: Finally, apply preferredTransform (orients the raw media)
        transform = transform.concatenating(track.preferredTransform)
        
        print("SkipSlate: [Transform DEBUG] calculateCompleteTransform – end for segment id=\(segment.id), result transform=\(transform)")
        
        return transform
    }
    
    /// Calculate transform for composition mode (Fit, Fill, Letterbox)
    /// - Parameters:
    ///   - sourceSize: Natural size of the source video
    ///   - projectSize: Target project frame size
    ///   - mode: Composition mode
    ///   - anchor: Anchor position for alignment
    /// - Returns: CGAffineTransform for the composition mode
    private func calculateCompositionModeTransform(
        sourceSize: CGSize,
        projectSize: CGSize,
        mode: CompositionMode,
        anchor: CompositionAnchor
    ) -> CGAffineTransform {
        let srcWidth = sourceSize.width
        let srcHeight = sourceSize.height
        let projWidth = projectSize.width
        let projHeight = projectSize.height
        
        guard srcWidth > 0, srcHeight > 0, projWidth > 0, projHeight > 0 else {
            return .identity
        }
        
        // Calculate scale factors
        let scaleToFit = min(projWidth / srcWidth, projHeight / srcHeight)
        let scaleToFill = max(projWidth / srcWidth, projHeight / srcHeight)
        
        // Determine scale based on mode
        let scale: CGFloat
        switch mode {
        case .fit, .fitWithLetterbox:
            scale = scaleToFit
        case .fill:
            scale = scaleToFill
        }
        
        // Calculate scaled dimensions
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale
        
        // Calculate translation based on anchor
        var tx: CGFloat = 0
        var ty: CGFloat = 0
        
        switch anchor {
        case .center:
            tx = (projWidth - scaledWidth) / 2.0
            ty = (projHeight - scaledHeight) / 2.0
        case .top:
            tx = (projWidth - scaledWidth) / 2.0
            ty = 0
        case .bottom:
            tx = (projWidth - scaledWidth) / 2.0
            ty = projHeight - scaledHeight
        case .left:
            tx = 0
            ty = (projHeight - scaledHeight) / 2.0
        case .right:
            tx = projWidth - scaledWidth
            ty = (projHeight - scaledHeight) / 2.0
        case .topLeft:
            tx = 0
            ty = 0
        case .topRight:
            tx = projWidth - scaledWidth
            ty = 0
        case .bottomLeft:
            tx = 0
            ty = projHeight - scaledHeight
        case .bottomRight:
            tx = projWidth - scaledWidth
            ty = projHeight - scaledHeight
        }
        
        // Build transform
        var t = CGAffineTransform.identity
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: tx / scale, y: ty / scale)
        
        print("SkipSlate: [Composition DEBUG] mode=\(mode), anchor=\(anchor), scale=\(scale), translation=(\(tx), \(ty))")
        
        return t
    }
    
    /// Calculate transform to scale and center-crop video to fill project frame
    /// - Parameters:
    ///   - sourceSize: Natural size of the source video (after preferredTransform)
    ///   - projectSize: Target project frame size
    /// - Returns: CGAffineTransform that scales and centers the video to fill the frame
    /// - Note: This returns a transform relative to identity, not including preferredTransform
    private func transformForScaleToFill(sourceSize: CGSize, projectSize: CGSize) -> CGAffineTransform {
        // Use absolute sizes
        let srcWidth = abs(sourceSize.width)
        let srcHeight = abs(sourceSize.height)
        let projWidth = projectSize.width
        let projHeight = projectSize.height
        
        // STEP 1.3: Debug logging for scale-to-fill calculation
        print("SkipSlate: [Transform DEBUG] transformForScaleToFill - sourceSize: \(sourceSize) (abs: \(srcWidth)x\(srcHeight)), projectSize: \(projectSize) (abs: \(projWidth)x\(projHeight))")
        
        guard srcWidth > 0, srcHeight > 0, projWidth > 0, projHeight > 0 else {
            print("SkipSlate: ⚠️ Invalid sizes for Scale to Fill - source: \(sourceSize), project: \(projectSize)")
            return .identity
        }
        
        // Calculate scale factor to fill frame (scale to cover, not fit)
        let scaleX = projWidth / srcWidth
        let scaleY = projHeight / srcHeight
        let scale = max(scaleX, scaleY)  // Use larger scale to ensure full coverage
        
        print("SkipSlate: [Transform DEBUG] transformForScaleToFill - scaleX=\(scaleX), scaleY=\(scaleY), final scale=\(scale)")
        
        // Calculate scaled dimensions
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale
        
        // Center the scaled image in the project frame
        // Translation is applied in the scaled coordinate space
        let tx = (projWidth - scaledWidth) / 2.0
        let ty = (projHeight - scaledHeight) / 2.0
        
        print("SkipSlate: [Transform DEBUG] transformForScaleToFill - scaledSize: \(scaledWidth)x\(scaledHeight), translation: (\(tx), \(ty))")
        
        // Build transform: scale first, then translate
        var t = CGAffineTransform.identity
        t = t.scaledBy(x: scale, y: scale)
        t = t.translatedBy(x: tx / scale, y: ty / scale)
        
        print("SkipSlate: [Transform DEBUG] transformForScaleToFill - result transform: \(t)")
        
        return t
    }
}

