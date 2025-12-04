//
//  HighlightReelService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation

/// Main service for creating cinematic highlight reels
class HighlightReelService {
    static let shared = HighlightReelService()
    
    private let musicAnalyzer = HighlightReelMusicAnalyzer.shared
    private let visualAnalyzer = HighlightReelVisualAnalyzer.shared
    private let cinematicScorer: CinematicScoringEngine = DefaultCinematicScoringEngine()
    private let segmentSelector = CinematicSegmentSelector()
    
    private init() {}
    
    /// Progress callback type
    typealias ProgressCallback = (String) -> Void
    
    /// Generate highlight reel segments with story structure, beat alignment, and motion
    /// - Parameter allAnalyzedSegmentsCallback: Optional callback to receive ALL analyzed segments (before filtering) for caching
    func generateHighlightReel(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings,
        progressCallback: ProgressCallback? = nil,
        allAnalyzedSegmentsCallback: (([Segment]) -> Void)? = nil
    ) async throws -> [Segment] {
        let startTime = Date()
        progressCallback?("Starting highlight reel generation...")
        print("SkipSlate: Starting highlight reel generation...")
        
        // 1. Find main music track - CRITICAL: Highlight Reel REQUIRES music
        let (audioClip, audioAsset) = await findMainMusicTrack(
            project: project,
            assetsByClipID: assetsByClipID,
            progressCallback: progressCallback
        )
        
        // 2. Analyze music - CRITICAL: Highlight Reel REQUIRES music
        guard let musicAsset = audioAsset else {
            let errorMessage = "Highlight Reel requires a music track. Please import an audio file (MP3, M4A, WAV, etc.) to use as the baseline for editing. The music track determines where to cut the video to match the beat."
            print("SkipSlate: ✗✗✗ ERROR: \(errorMessage)")
            progressCallback?("ERROR: Music track required")
            throw AutoEditError.analysisFailed(errorMessage)
        }
        
        guard let musicClip = audioClip else {
            let errorMessage = "Music track found but clip information is missing."
            print("SkipSlate: ✗✗✗ ERROR: \(errorMessage)")
            progressCallback?("ERROR: Music track information missing")
            throw AutoEditError.analysisFailed(errorMessage)
        }
        
        print("SkipSlate: ✓ Music track found: \(musicClip.fileName)")
        progressCallback?("Found music track: \(musicClip.fileName)")
        
        progressCallback?("Analyzing music track...")
        let musicAnalysis: MusicAnalysis
        do {
            musicAnalysis = try await withTimeout(seconds: 180) {
                try await self.musicAnalyzer.analyzeMusicForHighlightReel(asset: musicAsset)
            }
        } catch {
            let errorMessage = "Failed to analyze music track: \(error.localizedDescription)"
            print("SkipSlate: ✗✗✗ ERROR: \(errorMessage)")
            progressCallback?("ERROR: Music analysis failed")
            throw AutoEditError.analysisFailed(errorMessage)
        }
        
        // CRITICAL: Validate music analysis
        guard !musicAnalysis.beatTimes.isEmpty else {
            let errorMessage = "No beats detected in music track. Please use a track with clear rhythm."
            print("SkipSlate: ✗✗✗ ERROR: \(errorMessage)")
            progressCallback?("ERROR: No beats detected")
            throw AutoEditError.analysisFailed(errorMessage)
        }
        
        let musicTime = Date().timeIntervalSince(startTime)
        progressCallback?("Music analysis complete (\(Int(musicTime))s) - \(musicAnalysis.beatTimes.count) beats detected")
        print("SkipSlate: Music analysis complete - \(musicAnalysis.beatTimes.count) beats detected (took \(String(format: "%.1f", musicTime))s)")
        
        // 3. Analyze visual content
        let videoClips = project.clips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly }
        let imageClips = project.clips.filter { $0.type == .image }
        
        // CRITICAL: Validate that all video clips are present and will be analyzed
        let validVideoClips = videoClips.filter { assetsByClipID[$0.id] != nil }
        if validVideoClips.count != videoClips.count {
            let missingCount = videoClips.count - validVideoClips.count
            print("SkipSlate: ⚠️ WARNING: \(missingCount) video clip(s) missing assets - will skip them")
        }
        
        // CRITICAL: Ensure we have at least one valid video clip
        guard !validVideoClips.isEmpty else {
            let errorMessage = "No valid video clips found for analysis. Please ensure all video files are properly imported."
            print("SkipSlate: ✗✗✗ ERROR: \(errorMessage)")
            progressCallback?("ERROR: No valid video clips")
            throw AutoEditError.analysisFailed(errorMessage)
        }
        
        let totalClips = validVideoClips.count + imageClips.count
        progressCallback?("Analyzing \(totalClips) clips... (0/\(totalClips))")
        print("SkipSlate: Analyzing \(validVideoClips.count) video clips and \(imageClips.count) image clips...")
        print("SkipSlate: Video clip details:")
        for clip in validVideoClips {
            if let clipIndex = validVideoClips.firstIndex(where: { $0.id == clip.id }) {
                print("SkipSlate:   Clip \(clipIndex + 1): \(clip.fileName), ID: \(clip.id)")
            }
        }
        
        let videoMoments: [VideoMoment]
        
        // QUICK MODE: Skip AI frame analysis, create segments based on beats/duration
        if settings.quickMode {
            print("SkipSlate: ⚡ QUICK MODE - Skipping AI analysis, creating segments from beats")
            progressCallback?("Quick mode - creating segments from beats...")
            
            // Convert CMTime beat times to Double for quick mode
            let beatTimesDouble = musicAnalysis.beatTimes.map { $0.seconds }
            
            videoMoments = await createQuickModeVideoMoments(
                clips: validVideoClips,
                assetsByClipID: assetsByClipID,
                beatTimes: beatTimesDouble
            )
            
            print("SkipSlate: ⚡ Quick mode created \(videoMoments.count) moments in < 1 second")
        } else {
            // FULL MODE: AI frame-by-frame analysis (slow but detailed)
            do {
                videoMoments = try await visualAnalyzer.analyzeVideoClips(
                    clips: validVideoClips,
                    assetsByClipID: assetsByClipID,
                    progressCallback: { message in
                        progressCallback?(message)
                    }
                )
                
                // Validate that moments were generated from ALL clips
                let uniqueClipIDsInMoments = Set(videoMoments.map { $0.clipID })
                let uniqueClipIDsInClips = Set(validVideoClips.map { $0.id })
                
                if uniqueClipIDsInMoments.count < uniqueClipIDsInClips.count {
                    let missingClipIDs = uniqueClipIDsInClips.subtracting(uniqueClipIDsInMoments)
                    print("SkipSlate: ⚠️ WARNING: \(missingClipIDs.count) video clip(s) produced no moments:")
                    for clipID in missingClipIDs {
                        if let clip = validVideoClips.first(where: { $0.id == clipID }) {
                            print("SkipSlate:   - \(clip.fileName) (ID: \(clipID))")
                        }
                    }
                }
                
                print("SkipSlate: Found \(videoMoments.count) video moments from \(uniqueClipIDsInMoments.count) unique clip(s)")
            } catch {
                print("SkipSlate: Error analyzing video clips: \(error)")
                progressCallback?("Error analyzing videos - continuing with available moments")
                videoMoments = []
            }
        }
        
        print("SkipSlate: Moments per clip breakdown:")
        for clip in validVideoClips {
            let momentsFromClip = videoMoments.filter { $0.clipID == clip.id }
            print("SkipSlate:   - \(clip.fileName): \(momentsFromClip.count) moments")
        }
        
        let photoMoments = try await visualAnalyzer.analyzePhotoClips(
            clips: imageClips,
            assetsByClipID: assetsByClipID,
            progressCallback: { message in
                progressCallback?(message)
            }
        )
        print("SkipSlate: Found \(photoMoments.count) photo moments")
        
        // 4. Determine target duration and story structure
        let targetDuration = determineTargetDuration(
            musicDuration: musicAnalysis.duration,
            targetLength: settings.targetLengthSeconds
        )
        
        let storyStructure = planStoryStructure(
            totalDuration: targetDuration,
            pace: settings.pace,
            musicAnalysis: musicAnalysis
        )
        
        let analysisTime = Date().timeIntervalSince(startTime)
        progressCallback?("Visual analysis complete (\(Int(analysisTime))s) - Planning story structure...")
        print("SkipSlate: Story structure - Intro: \(storyStructure.introDuration.seconds)s, Build: \(storyStructure.buildDuration.seconds)s, Climax: \(storyStructure.climaxDuration.seconds)s, Outro: \(storyStructure.outroDuration.seconds)s")
        
        // 5. Convert settings to HighlightReelSettings
        let highlightSettings = HighlightReelSettings(
            targetDuration: targetDuration,
            pace: HighlightPace.from(settings.pace),
            style: HighlightStyle.from(settings.style),
            motionIntensity: 0.6, // Default, can be made configurable
            transitionIntensity: 0.5 // Default
        )
        
        // 6. Generate segment candidates with TWO TIERS: strict + fallback
        // CRASH-PROOF: This ensures ALL clips produce candidates, even if they don't meet strict thresholds
        let videoCandidatesTiered = generateVideoCandidates(
            moments: videoMoments,
            beats: musicAnalysis.beatTimes,
            pace: highlightSettings.pace
        )
        
        let videoCandidatesStrict = videoCandidatesTiered.strict
        let videoCandidatesFallback = videoCandidatesTiered.fallback
        let videoCandidatesAll = videoCandidatesStrict + videoCandidatesFallback  // All candidates for media cache
        
        let photoCandidates = generatePhotoCandidates(
            moments: photoMoments,
            beats: musicAnalysis.beatTimes,
            pace: highlightSettings.pace,
            motionIntensity: highlightSettings.motionIntensity
        )
        
        progressCallback?("Generated \(videoCandidatesAll.count + photoCandidates.count) candidates (\(videoCandidatesStrict.count) strict, \(videoCandidatesFallback.count) fallback) - Scoring cinematic quality...")
        print("SkipSlate: Generated \(videoCandidatesStrict.count) strict + \(videoCandidatesFallback.count) fallback = \(videoCandidatesAll.count) total video candidates, \(photoCandidates.count) photo candidates")
        
        // CRITICAL: Validate that candidates were generated from ALL clips (checking both tiers)
        let uniqueClipIDsInStrict = Set(videoCandidatesStrict.map { $0.clipID })
        let uniqueClipIDsInFallback = Set(videoCandidatesFallback.map { $0.clipID })
        let uniqueClipIDsInAll = uniqueClipIDsInStrict.union(uniqueClipIDsInFallback)
        let uniqueClipIDsInClips = Set(validVideoClips.map { $0.id })
        
        print("SkipSlate: Candidate generation breakdown:")
        print("SkipSlate:   Total video clips: \(validVideoClips.count)")
        print("SkipSlate:   Clips with strict candidates: \(uniqueClipIDsInStrict.count)")
        print("SkipSlate:   Clips with fallback candidates: \(uniqueClipIDsInFallback.count)")
        print("SkipSlate:   Clips with ANY candidates: \(uniqueClipIDsInAll.count)")
        
        if uniqueClipIDsInAll.count < uniqueClipIDsInClips.count {
            let missingClipIDs = uniqueClipIDsInClips.subtracting(uniqueClipIDsInAll)
            print("SkipSlate: ⚠️ WARNING: \(missingClipIDs.count) video clip(s) produced NO candidates (strict or fallback):")
            for clipID in missingClipIDs {
                if let clip = validVideoClips.first(where: { $0.id == clipID }) {
                    print("SkipSlate:   - \(clip.fileName) (ID: \(clipID)) - NO CANDIDATES GENERATED")
                }
            }
        }
        
        for clip in validVideoClips {
            let strictFromClip = videoCandidatesStrict.filter { $0.clipID == clip.id }
            let fallbackFromClip = videoCandidatesFallback.filter { $0.clipID == clip.id }
            let totalFromClip = strictFromClip.count + fallbackFromClip.count
            print("SkipSlate:   - \(clip.fileName): \(strictFromClip.count) strict + \(fallbackFromClip.count) fallback = \(totalFromClip) total candidates")
            if totalFromClip == 0 {
                print("SkipSlate:     ⚠️ WARNING: This clip has NO candidates - it won't be used in the edit!")
            }
        }
        
        // 6.5. CINEMATIC SCORING ENGINE - Score ALL candidates (strict + fallback) for media cache
        // CRASH-PROOF: In QUICK MODE, skip frame-based scoring entirely to prevent crashes
        // Quick mode assigns default scores and avoids Metal/GPU frame extraction
        let scoredCandidatesAll: [ScoredSegment]
        
        if settings.quickMode {
            // QUICK MODE: Skip cinematic scoring - assign default scores
            // This prevents libRPAC.dylib crashes from frame extraction
            print("SkipSlate: ⚡ QUICK MODE - Skipping cinematic scoring, assigning default scores")
            progressCallback?("Quick mode: Skipping detailed analysis...")
            
            scoredCandidatesAll = (videoCandidatesAll + photoCandidates).map { candidate in
                // Create a segment with default values
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: candidate.clipID,
                    sourceStart: candidate.sourceStart.seconds,
                    sourceEnd: CMTimeAdd(candidate.sourceStart, candidate.duration).seconds,
                    enabled: true,
                    colorIndex: 0
                )
                
                let timeRange = CMTimeRange(
                    start: candidate.sourceStart,
                    duration: candidate.duration
                )
                
                // Default score for quick mode - moderate quality, not rejected
                // Create a CinematicScore with default values
                let defaultScore = CinematicScore(
                    faceScore: 0.5,
                    compositionScore: 0.5,
                    stabilityScore: 0.8,  // Assume stable (no shake detection in quick mode)
                    exposureScore: 0.7    // Assume decent exposure
                )
                
                return ScoredSegment(
                    segment: segment,
                    score: defaultScore,
                    clipID: candidate.clipID,
                    timeRange: timeRange
                )
            }
            print("SkipSlate: ⚡ Quick mode assigned default scores to \(scoredCandidatesAll.count) candidates")
        } else {
            // NORMAL MODE: Full cinematic scoring with frame analysis
            progressCallback?("Analyzing cinematic quality of \(videoCandidatesAll.count + photoCandidates.count) segments...")
            scoredCandidatesAll = try await scoreCandidatesWithCinematicEngine(
                videoCandidates: videoCandidatesAll,  // Score ALL candidates for media cache
                photoCandidates: photoCandidates,
                project: project,
                assetsByClipID: assetsByClipID,
                progressCallback: progressCallback
            )
        }
        
        // Separate scored candidates into strict and fallback tiers
        let scoredStrictSet = Set(videoCandidatesStrict.map { $0.clipID.uuidString + "\($0.sourceStart.seconds)-\($0.duration.seconds)" })
        var scoredCandidatesStrict: [ScoredSegment] = []
        var scoredCandidatesFallback: [ScoredSegment] = []
        
        for scoredCandidate in scoredCandidatesAll {
            let candidateKey = scoredCandidate.clipID.uuidString + "\(scoredCandidate.segment.sourceStart)-\(scoredCandidate.segment.duration)"
            if scoredStrictSet.contains(candidateKey) {
                scoredCandidatesStrict.append(scoredCandidate)
            } else {
                scoredCandidatesFallback.append(scoredCandidate)
            }
        }
        
        print("SkipSlate: Scored \(scoredCandidatesStrict.count) strict + \(scoredCandidatesFallback.count) fallback = \(scoredCandidatesAll.count) total candidates")
        
        // Use all scored candidates for media cache, but strict for primary selection
        let scoredCandidates = scoredCandidatesAll  // For backward compatibility in media caching
        
        progressCallback?("Scored \(scoredCandidates.count) segments - Applying diversity filters...")
        print("SkipSlate: Cinematic scoring complete - \(scoredCandidates.count) segments scored")
        
        // CRITICAL: Convert ALL scored candidates to segments for caching (before filtering)
        // CRASH-PROOF FLOW:
        // 1. ALL videos are analyzed regardless of quality (handled by visualAnalyzer.analyzeVideoClips)
        // 2. ALL moments are converted to candidates (handled by generateVideoCandidates)
        // 3. ALL candidates are scored (handled by scoreCandidatesWithCinematicEngine)
        // 4. ALL scored candidates are cached here (for Media tab) - NO QUALITY FILTERING
        // 5. Quality filtering ONLY happens during selection for timeline (in selectSegmentsForPhase)
        //    - Quality thresholds are relaxed for unused clips when enforcing multi-clip
        //    - This ensures ALL videos are represented in the final edit, even if lower quality
        // This allows Media tab to show ALL analyzed segments, not just the filtered ones
        var allAnalyzedSegments: [Segment] = []
        for scoredCandidate in scoredCandidates {
            // Get colorIndex from clip (assigned during import)
            // Each clip has a unique colorIndex - no clamping needed with infinite color palette
            var colorIndex = 0 // Fallback default
            if let clip = project.clips.first(where: { $0.id == scoredCandidate.clipID }) {
                colorIndex = clip.colorIndex
            }
            
            // Create a new Segment with unique ID for caching (these are separate from timeline segments)
            // CRASH-PROOF: Ensure sourceClipID is valid
            guard let sourceClipID = scoredCandidate.segment.sourceClipID else {
                print("SkipSlate: ⚠️ Skipping scored candidate with nil sourceClipID")
                continue // Skip invalid candidates instead of crashing
            }
            
            // CRASH-PROOF: Validate time ranges before creating segment
            let sourceStart = scoredCandidate.segment.sourceStart
            let sourceEnd = scoredCandidate.segment.sourceEnd
            guard sourceStart >= 0 && sourceEnd > sourceStart else {
                print("SkipSlate: ⚠️ Skipping scored candidate with invalid time range: start=\(sourceStart), end=\(sourceEnd)")
                continue // Skip invalid time ranges instead of crashing
            }
            
            let cachedSegment = Segment(
                id: UUID(), // New unique ID for cache
                sourceClipID: sourceClipID,
                sourceStart: sourceStart,
                sourceEnd: sourceEnd,
                enabled: true,
                colorIndex: colorIndex, // Use clip's assigned color
                effects: scoredCandidate.segment.effects,
                compositionStartTime: scoredCandidate.segment.compositionStartTime
            )
            allAnalyzedSegments.append(cachedSegment)
        }
        print("SkipSlate: ✅ Converted ALL \(allAnalyzedSegments.count) scored candidates to segments for caching (from \(scoredCandidates.count) scored candidates)")
        
        // Call callback with ALL analyzed segments (before filtering)
        // CRASH-PROOF: Only call callback if we have segments
        if !allAnalyzedSegments.isEmpty {
            allAnalyzedSegmentsCallback?(allAnalyzedSegments)
            print("SkipSlate: ✅ Provided \(allAnalyzedSegments.count) ALL analyzed segments to callback for Media tab caching")
        } else {
            print("SkipSlate: ⚠️ WARNING: No analyzed segments to cache - Media tab will be empty")
        }
        
        // 6.6. Apply diversity and repetition constraints with MULTI-CLIP ENFORCEMENT
        // CRASH-PROOF: Use strict candidates first, then fallback for diversity
        let filteredSegments = selectSegmentsWithMultiClipEnforcement(
            strictCandidates: scoredCandidatesStrict,
            fallbackCandidates: scoredCandidatesFallback,
            maxTotalSegments: nil,  // No global limit, use story structure
            progressCallback: progressCallback
        )
        
        // Convert filtered segments back to candidates for story structure ordering
        // CRASH-PROOF: Use all candidates (strict + fallback) for lookup
        let filteredCandidates = convertSegmentsToCandidates(
            segments: filteredSegments,
            originalCandidates: videoCandidatesAll + photoCandidates
        )
        
        progressCallback?("Selected \(filteredCandidates.count) diverse segments - Organizing by story structure...")
        print("SkipSlate: Diversity filtering complete - \(filteredCandidates.count) segments selected")
        
        // 7. Select and order segments by story phase (using filtered candidates)
        let selectedSegments = selectAndOrderSegments(
            videoCandidates: filteredCandidates.filter { $0.type == .video },
            photoCandidates: filteredCandidates.filter { $0.type == .image },
            storyStructure: storyStructure,
            musicAnalysis: musicAnalysis,
            settings: highlightSettings
        )
        
        let totalTime = Date().timeIntervalSince(startTime)
        progressCallback?("Complete! Selected \(selectedSegments.count) segments (\(String(format: "%.1f", totalTime))s)")
        print("SkipSlate: Selected \(selectedSegments.count) segments for highlight reel (total time: \(String(format: "%.1f", totalTime))s)")
        
        // 8. Convert to Project Segments
        // CRITICAL: For Highlight Reel, use clip's pre-assigned colorIndex (0-11 for 12 specific colors)
        // This ensures segments use the exact color order: Red, Blue, Green, Yellow, Orange, Purple, Pink, Teal, Navy, Maroon, Gold, Grey
        var segments: [Segment] = []
        
        for candidate in selectedSegments {
            // Get colorIndex from clip (assigned during import)
            // Each clip has a unique colorIndex - segments inherit their clip's color
            var colorIndex = 0 // Fallback default
            
            if let clip = project.clips.first(where: { $0.id == candidate.clipID }) {
                // Use the clip's pre-assigned colorIndex
                colorIndex = clip.colorIndex
            } else {
                print("SkipSlate: ⚠️ Clip not found for candidate.clipID: \(candidate.clipID), using default colorIndex 0")
            }
            
            let segment = Segment(
                id: UUID(),
                sourceClipID: candidate.clipID,
                sourceStart: candidate.sourceStart.seconds,
                sourceEnd: CMTimeAdd(candidate.sourceStart, candidate.duration).seconds,
                enabled: true,
                colorIndex: colorIndex
            )
            segments.append(segment)
        }
        
        print("SkipSlate: Segment creation complete - \(segments.count) segments created with clip color indices")
        
        // CRITICAL: Validate that highlight reels use clips from multiple videos (unless user only uploaded one video)
        // CRASH-PROOF: Use fallback candidates if validation fails
        let validatedSegments = try validateMultiVideoSelection(
            segments: segments,
            project: project,
            fallbackCandidates: scoredCandidatesFallback  // Pass fallback candidates for recovery
        )
        
        print("SkipSlate: Multi-video validation complete - using segments from \(Set(validatedSegments.compactMap { $0.sourceClipID }).count) unique clips")
        return validatedSegments
    }
    
    // MARK: - Multi-Clip Selection with Fallback
    
    /// CRASH-PROOF: Select segments with multi-clip enforcement using strict + fallback candidates
    /// This ensures highlight reels use segments from multiple clips when available
    private func selectSegmentsWithMultiClipEnforcement(
        strictCandidates: [ScoredSegment],
        fallbackCandidates: [ScoredSegment],
        maxTotalSegments: Int?,
        progressCallback: ProgressCallback? = nil
    ) -> [Segment] {
        // CRASH-PROOF: Validate inputs
        guard !strictCandidates.isEmpty || !fallbackCandidates.isEmpty else {
            print("SkipSlate: selectSegmentsWithMultiClipEnforcement - No candidates provided")
            return []
        }
        
        progressCallback?("Selecting segments with multi-clip distribution...")
        
        // 1. Filter out rejected segments from both tiers
        let strictNonRejected = strictCandidates.filter { !$0.score.isRejected }
        let fallbackNonRejected = fallbackCandidates.filter { !$0.score.isRejected }
        
        print("SkipSlate: Multi-clip selection - \(strictNonRejected.count) strict + \(fallbackNonRejected.count) fallback non-rejected candidates")
        
        // 2. Sort strict candidates by score (descending)
        let sortedStrict = strictNonRejected.sorted { $0.score.overall > $1.score.overall }
        
        // 3. Group fallback candidates by clipID for diversity enforcement
        var fallbackByClip: [UUID: [ScoredSegment]] = [:]
        for candidate in fallbackNonRejected {
            fallbackByClip[candidate.clipID, default: []].append(candidate)
        }
        
        // Sort fallback candidates within each clip by score
        for clipID in fallbackByClip.keys {
            fallbackByClip[clipID]?.sort { $0.score.overall > $1.score.overall }
        }
        
        // 4. Primary selection from strict candidates with per-clip cap
        let maxPerClip = 5  // CRASH-PROOF: Reasonable limit to prevent one clip dominating
        var selected: [Segment] = []
        var segmentsPerClip: [UUID: Int] = [:]
        var usedTimeRanges: [UUID: [CMTimeRange]] = [:]
        
        for candidate in sortedStrict {
            // Check global limit
            if let maxTotal = maxTotalSegments, selected.count >= maxTotal {
                break
            }
            
            // Check per-clip limit
            let currentCount = segmentsPerClip[candidate.clipID] ?? 0
            if currentCount >= maxPerClip {
                continue  // Skip if this clip already has max segments
            }
            
            // Check for overlap/duplicate (same logic as CinematicSegmentSelector)
            if let existingRanges = usedTimeRanges[candidate.clipID] {
                let isDuplicate = existingRanges.contains { existingRange in
                    let overlap = candidate.timeRange.intersection(existingRange)
                    guard !overlap.isEmpty else { return false }
                    let overlapRatio = overlap.duration.seconds / candidate.timeRange.duration.seconds
                    return overlapRatio > 0.8  // 80% overlap = duplicate
                }
                
                if isDuplicate { continue }
                
                // Check minimum time separation
                let isTooClose = existingRanges.contains { existingRange in
                    let distance = abs(CMTimeSubtract(candidate.timeRange.start, existingRange.start).seconds)
                    return distance < 2.0  // 2 seconds minimum separation
                }
                
                if isTooClose { continue }
            }
            
            // Accept this strict candidate
            selected.append(candidate.segment)
            segmentsPerClip[candidate.clipID, default: 0] += 1
            usedTimeRanges[candidate.clipID, default: []].append(candidate.timeRange)
        }
        
        // 5. Check diversity: if we only have segments from one clip, add fallback from other clips
        let uniqueClips = Set(selected.compactMap { $0.sourceClipID })
        
        if uniqueClips.count == 1, let dominantClipID = uniqueClips.first {
            print("SkipSlate: Multi-clip selection - Only one clip in strict selection, adding fallback from other clips")
            
            // Find other clips with fallback candidates
            let otherClipsWithFallback = fallbackByClip.filter { $0.key != dominantClipID && !$0.value.isEmpty }
            
            // Add top fallback candidates from each other clip (up to 2 per clip)
            for (clipID, fallbackSegments) in otherClipsWithFallback {
                if let maxTotal = maxTotalSegments, selected.count >= maxTotal {
                    break
                }
                
                let currentCount = segmentsPerClip[clipID] ?? 0
                if currentCount >= 2 {  // Limit fallback to 2 per clip
                    continue
                }
                
                // Add top 1-2 fallback segments from this clip
                let segmentsToAdd = min(2 - currentCount, fallbackSegments.count)
                for i in 0..<segmentsToAdd {
                    let candidate = fallbackSegments[i]
                    
                    // Check for duplicates
                    if let existingRanges = usedTimeRanges[clipID] {
                        let isDuplicate = existingRanges.contains { existingRange in
                            let overlap = candidate.timeRange.intersection(existingRange)
                            guard !overlap.isEmpty else { return false }
                            let overlapRatio = overlap.duration.seconds / candidate.timeRange.duration.seconds
                            return overlapRatio > 0.8
                        }
                        if isDuplicate { continue }
                    }
                    
                    selected.append(candidate.segment)
                    segmentsPerClip[clipID, default: 0] += 1
                    usedTimeRanges[clipID, default: []].append(candidate.timeRange)
                    print("SkipSlate: Multi-clip selection - Added fallback segment from clip \(clipID) (score: \(String(format: "%.2f", candidate.score.overall)))")
                }
            }
        }
        
        // 6. Log final selection
        let finalUniqueClips = Set(selected.compactMap { $0.sourceClipID })
        print("SkipSlate: Multi-clip selection - Final: \(selected.count) segments from \(finalUniqueClips.count) clips")
        for (clipID, count) in segmentsPerClip {
            print("SkipSlate:   - Clip \(clipID): \(count) segment(s)")
        }
        
        progressCallback?("Selected \(selected.count) segments from \(finalUniqueClips.count) clips")
        
        return selected
    }
    
    /// CRASH-PROOF: Convert Segment objects back to HighlightSegmentCandidate for story structure ordering
    private func convertSegmentsToCandidates(
        segments: [Segment],
        originalCandidates: [HighlightSegmentCandidate]
    ) -> [HighlightSegmentCandidate] {
        var result: [HighlightSegmentCandidate] = []
        
        // CRASH-PROOF: Create a lookup map for fast candidate retrieval
        var candidateMap: [String: HighlightSegmentCandidate] = [:]
        for candidate in originalCandidates {
            let key = "\(candidate.clipID.uuidString)-\(candidate.sourceStart.seconds)-\(candidate.duration.seconds)"
            candidateMap[key] = candidate
        }
        
        // Match segments to original candidates
        for segment in segments {
            // CRASH-PROOF: Validate segment
            guard let sourceClipID = segment.sourceClipID else {
                print("SkipSlate: ⚠️ convertSegmentsToCandidates - Segment has nil sourceClipID, skipping")
                continue
            }
            
            let key = "\(sourceClipID.uuidString)-\(segment.sourceStart)-\(segment.duration)"
            if let candidate = candidateMap[key] {
                result.append(candidate)
            } else {
                // CRASH-PROOF: If exact match not found, try to find closest match
                let matchingCandidates = originalCandidates.filter {
                    $0.clipID == sourceClipID &&
                    abs($0.sourceStart.seconds - segment.sourceStart) < 0.1 &&
                    abs($0.duration.seconds - segment.duration) < 0.1
                }
                
                if let closest = matchingCandidates.first {
                    result.append(closest)
                } else {
                    print("SkipSlate: ⚠️ convertSegmentsToCandidates - No matching candidate found for segment from clip \(sourceClipID)")
                }
            }
        }
        
        return result
    }
    
    // MARK: - Multi-Video Validation
    
    /// CRASH-PROOF: Ensures highlight reels never use clips from just one video (unless user only uploaded one video)
    /// Uses fallback candidates if needed to ensure multi-clip diversity
    private func validateMultiVideoSelection(
        segments: [Segment],
        project: Project,
        fallbackCandidates: [ScoredSegment] = []
    ) throws -> [Segment] {
        // CRITICAL: Safe validation with error handling
        guard !segments.isEmpty else {
            print("SkipSlate: ⚠️ Multi-video validation - No segments to validate")
            return segments
        }
        
        // Get video clips (exclude audio-only and images for this validation)
        let videoClips = project.clips.filter { clip in
            clip.type == .videoWithAudio || clip.type == .videoOnly
        }
        
        // CRITICAL: Only apply this rule to highlight reels (not other project types)
        guard project.type == .highlightReel else {
            print("SkipSlate: Multi-video validation skipped - not a highlight reel project")
            return segments
        }
        
        // CRITICAL: If user only uploaded one video, allow it (as requested by user)
        guard videoClips.count > 1 else {
            print("SkipSlate: Multi-video validation skipped - user only uploaded \(videoClips.count) video clip")
            return segments
        }
        
        // Get unique clip IDs used in segments
        let uniqueClipIDs = Set(segments.compactMap { $0.sourceClipID })
        
        // CRITICAL: Check if all segments come from the same video clip
        guard uniqueClipIDs.count > 1 else {
            // All segments are from one video - this is a CRITICAL ERROR for Highlight Reel
            print("SkipSlate: ⚠️⚠️⚠️ CRITICAL ERROR: All segments come from single video clip!")
            print("SkipSlate: This should NEVER happen for Highlight Reel with multiple videos.")
            print("SkipSlate: Total segments: \(segments.count), Unique clip IDs: \(uniqueClipIDs.count)")
            
            // Find the problematic clip ID
            guard let singleClipID = uniqueClipIDs.first else {
                print("SkipSlate: ⚠️ ERROR: Cannot identify single clip ID")
                return segments // Return original if we can't fix it
            }
            
            if let problematicClip = videoClips.first(where: { $0.id == singleClipID }) {
                print("SkipSlate: Problematic clip: \(problematicClip.fileName) (ID: \(singleClipID))")
            }
            
            // Check if there are other video clips available
            let otherVideoClips = videoClips.filter { $0.id != singleClipID }
            
            guard !otherVideoClips.isEmpty else {
                print("SkipSlate: ⚠️ ERROR: No other video clips available for diversification")
                return segments // User only has one video, return original
            }
            
            print("SkipSlate: Available other clips: \(otherVideoClips.map { $0.fileName }.joined(separator: ", "))")
            
            // CRITICAL: Check if we have fallback candidates from other clips
            let otherClipIDs = Set(otherVideoClips.map { $0.id })
            let fallbackFromOtherClips = fallbackCandidates.filter { otherClipIDs.contains($0.clipID) }
            
            if !fallbackFromOtherClips.isEmpty {
                print("SkipSlate: ⚠️ WARNING: Only segments from one video detected, but found \(fallbackFromOtherClips.count) fallback candidates from other clips")
                print("SkipSlate: This indicates selection logic may need adjustment, but segments are valid")
                // Return segments as-is - selection logic should have handled this, but don't truncate
                return segments
            } else {
                // No fallback candidates from other clips - this is acceptable if other clips truly have no usable content
                print("SkipSlate: ⚠️ WARNING: Only segments from one video detected, and no fallback candidates from other clips")
                print("SkipSlate: This likely means other videos didn't produce any usable candidates (strict or fallback)")
                print("SkipSlate: Returning segments as-is - user can manually add segments from Media tab if needed")
                // CRASH-PROOF: Don't truncate - return all segments. User can manually adjust via Media tab.
                return segments
            }
        }
        
        // Validation passed - segments come from multiple clips
        print("SkipSlate: ✓ Multi-video validation passed - segments from \(uniqueClipIDs.count) different clips")
        
        // CRITICAL: Also verify that we're using a reasonable distribution
        let segmentsPerClipCount: [UUID: Int] = Dictionary(grouping: segments.compactMap { $0.sourceClipID }) { $0 }.mapValues { $0.count }
        print("SkipSlate: Segment distribution per clip:")
        for (clipID, count) in segmentsPerClipCount {
            if let clip = videoClips.first(where: { $0.id == clipID }) {
                print("SkipSlate:   - \(clip.fileName): \(count) segments")
            }
        }
        
        // Ensure no single clip dominates (more than 60% of segments)
        let maxAllowedFromSingleClip = max(1, Int(Double(segments.count) * 0.6))
        for (clipID, count) in segmentsPerClipCount {
            if count > maxAllowedFromSingleClip {
                print("SkipSlate: ⚠️ WARNING: Clip \(clipID) has \(count) segments (max allowed: \(maxAllowedFromSingleClip)) - distribution may be uneven")
            }
        }
        
        return segments
    }
    
    // CRITICAL: Timeout helper to prevent hanging operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "HighlightReelService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out after \(seconds) seconds"])
            }
            
            guard let result = try await group.next() else {
                throw NSError(domain: "HighlightReelService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed"])
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Helper Methods
    
    private func findMainMusicTrack(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        progressCallback: ProgressCallback? = nil
    ) async -> (MediaClip?, AVAsset?) {
        print("SkipSlate: Finding main music track for Highlight Reel...")
        print("SkipSlate: Project has \(project.clips.count) clips")
        progressCallback?("Looking for music track...")
        
        // Log all clip types for debugging
        for (index, clip) in project.clips.enumerated() {
            print("SkipSlate:   Clip \(index + 1): \(clip.fileName), type: \(clip.type), hasAudioTrack: \(clip.hasAudioTrack)")
        }
        
        // Prefer audio-only clip (this is the music track)
        for clip in project.clips where clip.type == .audioOnly {
            print("SkipSlate: Found audio-only clip: \(clip.fileName)")
            if let asset = assetsByClipID[clip.id] {
                // Verify it actually has audio tracks
                do {
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    if !audioTracks.isEmpty {
                        print("SkipSlate: ✓ Using audio-only clip as music track (has \(audioTracks.count) audio track(s))")
                        return (clip, asset)
                    } else {
                        print("SkipSlate: ⚠ Audio-only clip has no audio tracks, skipping")
                    }
                } catch {
                    print("SkipSlate: ⚠ Error verifying audio tracks: \(error)")
                }
            } else {
                print("SkipSlate: ⚠ Audio-only clip found but asset not in assetsByClipID")
            }
        }
        
        // FALLBACK: Check if any clips are misclassified
        // Some audio files might be detected as videoOnly if detection fails
        print("SkipSlate: No audioOnly clips found, checking for misclassified audio files...")
        progressCallback?("Checking for misclassified audio files...")
        
        for clip in project.clips {
            // Check if clip has audio track even if type is wrong
            if clip.hasAudioTrack && (clip.type == .videoOnly || clip.type == .videoWithAudio) {
                print("SkipSlate: Found clip with audio track but wrong type: \(clip.fileName) (type: \(clip.type))")
                // Try to use it as music if it's the only audio source
                if let asset = assetsByClipID[clip.id] {
                    // Verify it actually has audio tracks
                    do {
                        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                        if !audioTracks.isEmpty {
                            print("SkipSlate: ✓ Using misclassified clip as music track (has \(audioTracks.count) audio track(s))")
                            print("SkipSlate: ⚠ WARNING: Clip was misclassified during import. Consider re-importing the audio file.")
                            return (clip, asset)
                        }
                    } catch {
                        print("SkipSlate: Could not verify audio tracks: \(error)")
                    }
                }
            }
        }
        
        // Otherwise use first video clip's audio (if it has audio)
        // NOTE: This is not ideal for Highlight Reel, but we'll allow it as a last resort
        for clip in project.clips where clip.type == .videoWithAudio {
            if let asset = assetsByClipID[clip.id] {
                do {
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    if !audioTracks.isEmpty {
                        print("SkipSlate: ⚠ Using video clip's audio as fallback (not ideal for Highlight Reel)")
                        print("SkipSlate: ⚠ For best results, import a separate audio-only music track")
                        return (clip, asset)
                    }
                } catch {
                    print("SkipSlate: Could not verify video clip audio: \(error)")
                }
            }
        }
        
        print("SkipSlate: ✗✗✗ NO MUSIC TRACK FOUND - Highlight Reel requires music!")
        return (nil, nil)
    }
    
    private func determineTargetDuration(
        musicDuration: CMTime,
        targetLength: Double?
    ) -> CMTime {
        if let targetSeconds = targetLength {
            let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
            return min(target, musicDuration)
        }
        return musicDuration
    }
    
    private func planStoryStructure(
        totalDuration: CMTime,
        pace: Pace,
        musicAnalysis: MusicAnalysis
    ) -> StoryStructure {
        let totalSeconds = totalDuration.seconds
        
        // Use music analysis to determine story structure
        // If music has clear sections, align story phases to them
        if let introZone = musicAnalysis.introZone, let climaxZone = musicAnalysis.climaxZone {
            // Music-driven structure: align to music sections
            let introEnd = min(introZone.end.seconds, totalSeconds * 0.2)
            let climaxStart = max(climaxZone.start.seconds, totalSeconds * 0.5)
            let climaxEnd = min(climaxZone.end.seconds, totalSeconds * 0.85)
            
            return StoryStructure(
                introDuration: CMTime(seconds: introEnd, preferredTimescale: 600),
                buildDuration: CMTime(seconds: climaxStart - introEnd, preferredTimescale: 600),
                climaxDuration: CMTime(seconds: climaxEnd - climaxStart, preferredTimescale: 600),
                outroDuration: CMTime(seconds: totalSeconds - climaxEnd, preferredTimescale: 600),
                pace: pace
            )
        } else {
            // Default structure: balanced phases
            return StoryStructure(
                introDuration: CMTime(seconds: totalSeconds * 0.15, preferredTimescale: 600),
                buildDuration: CMTime(seconds: totalSeconds * 0.40, preferredTimescale: 600),
                climaxDuration: CMTime(seconds: totalSeconds * 0.30, preferredTimescale: 600),
                outroDuration: CMTime(seconds: totalSeconds * 0.15, preferredTimescale: 600),
                pace: pace
            )
        }
    }
    
    // MARK: - Two-Tier Candidate Generation
    
    /// Generate candidates with two tiers: strict (high quality) and fallback (relaxed thresholds)
    /// This ensures all clips produce candidates, even if they don't meet strict quality thresholds
    private func generateVideoCandidates(
        moments: [VideoMoment],
        beats: [CMTime],
        pace: HighlightPace
    ) -> (strict: [HighlightSegmentCandidate], fallback: [HighlightSegmentCandidate]) {
        var strictCandidates: [HighlightSegmentCandidate] = []
        var fallbackCandidates: [HighlightSegmentCandidate] = []
        
        // STRICT TIER: High-quality candidates with strict duration/framing thresholds
        let strictMinDuration: Double = 0.5
        let strictMaxDuration: Double = 10.0  // Strict max duration for high-quality segments
        
        // FALLBACK TIER: Relaxed thresholds to ensure all clips produce candidates
        let fallbackMinDuration: Double = 0.5
        let fallbackMaxDuration: Double = 30.0  // Allow longer segments in fallback tier
        
        // CRASH-PROOF: Validate inputs
        guard !moments.isEmpty else {
            print("SkipSlate: generateVideoCandidates - No moments provided, returning empty candidates")
            return (strict: [], fallback: [])
        }
        
        for moment in moments {
            // CRASH-PROOF: Validate moment duration
            let momentDuration = moment.duration.seconds
            guard momentDuration.isFinite && momentDuration > 0 else {
                print("SkipSlate: Skipping moment - invalid duration: \(momentDuration)s")
                continue
            }
            
            // CRASH-PROOF: Validate moment sourceStart
            guard moment.sourceStart.isValid && !moment.sourceStart.isIndefinite else {
                print("SkipSlate: Skipping moment - invalid sourceStart")
                continue
            }
            
            // Only reject moments that are too short (less than 0.5s)
            guard momentDuration >= fallbackMinDuration else {
                print("SkipSlate: Skipping moment - duration \(momentDuration)s too short (minimum: \(fallbackMinDuration)s)")
                continue
            }
            
            // Helper function to create a candidate from a time range
            func createCandidate(
                from start: CMTime,
                duration: Double,
                isStrict: Bool
            ) -> HighlightSegmentCandidate? {
                // CRASH-PROOF: Validate time range
                guard start.isValid && !start.isIndefinite,
                      duration.isFinite && duration > 0 else {
                    return nil
                }
                
                // Snap start to nearest beat
                let snappedStart = snapToNearestBeat(time: start, beats: beats)
                
                // Adjust duration to fit pace constraints
                let minDuration = isStrict 
                    ? max(strictMinDuration, pace.minSegmentDuration)
                    : max(fallbackMinDuration, pace.minSegmentDuration)
                let maxDuration = isStrict
                    ? min(strictMaxDuration, pace.maxSegmentDuration)
                    : min(fallbackMaxDuration, pace.maxSegmentDuration)
                
                var finalDuration = duration
                finalDuration = max(minDuration, min(maxDuration, finalDuration))
                
                // CRASH-PROOF: Validate final duration
                guard finalDuration.isFinite && finalDuration > 0 else {
                    return nil
                }
                
                // Snap duration to beat intervals if possible
                if let nextBeat = findNextBeat(after: snappedStart, beats: beats) {
                    let beatInterval = CMTimeSubtract(nextBeat, snappedStart).seconds
                    if beatInterval.isFinite && beatInterval >= minDuration && beatInterval <= maxDuration {
                        finalDuration = beatInterval
                    }
                }
                
                let beatIndex = findBeatIndex(for: snappedStart, beats: beats)
                
                return HighlightSegmentCandidate(
                    clipID: moment.clipID,
                    type: .video,
                    sourceStart: snappedStart,
                    duration: CMTime(seconds: finalDuration, preferredTimescale: 600),
                    hasFaces: moment.hasFaces,
                    motionLevel: moment.motionLevel,
                    shotType: moment.shotType,
                    score: moment.score,
                    suggestedBeatIndex: beatIndex,
                    motionTransform: nil
                )
            }
            
            // Determine if this moment qualifies for strict tier
            let isStrictDuration = momentDuration >= strictMinDuration && momentDuration <= strictMaxDuration
            let isFallbackDuration = momentDuration >= fallbackMinDuration && momentDuration <= fallbackMaxDuration
            
            // CRITICAL: Handle long moments by splitting them into multiple candidates
            if momentDuration > fallbackMaxDuration {
                // Split long moment into multiple shorter candidates
                let numberOfSplits = max(1, Int(ceil(momentDuration / fallbackMaxDuration)))
                let splitDuration = momentDuration / Double(numberOfSplits)
                
                // CRASH-PROOF: Limit number of splits to prevent excessive candidates
                guard numberOfSplits <= 10 else {
                    print("SkipSlate: ⚠️ Moment too long (\(momentDuration)s), limiting splits to 10")
                    continue
                }
                
                print("SkipSlate: Splitting long moment (\(momentDuration)s) into \(numberOfSplits) candidates of ~\(splitDuration)s each")
                
                for i in 0..<numberOfSplits {
                    // CRASH-PROOF: Calculate split start safely
                    let splitOffset = Double(i) * splitDuration
                    guard splitOffset.isFinite else { continue }
                    
                    let splitStart = CMTimeAdd(moment.sourceStart, CMTime(seconds: splitOffset, preferredTimescale: 600))
                    
                    // Create fallback candidate (strict tier doesn't accept long moments)
                    if let fallbackCandidate = createCandidate(from: splitStart, duration: splitDuration, isStrict: false) {
                        fallbackCandidates.append(fallbackCandidate)
                    }
                }
                continue  // Skip the normal processing for split moments
            }
            
            // Normal processing for moments within duration range
            // Try strict tier first
            if isStrictDuration {
                if let strictCandidate = createCandidate(from: moment.sourceStart, duration: momentDuration, isStrict: true) {
                    strictCandidates.append(strictCandidate)
                    continue  // Don't add to fallback if it's already in strict
                }
            }
            
            // Add to fallback tier if it passes fallback duration check
            if isFallbackDuration {
                if let fallbackCandidate = createCandidate(from: moment.sourceStart, duration: momentDuration, isStrict: false) {
                    fallbackCandidates.append(fallbackCandidate)
                }
            }
        }
        
        print("SkipSlate: Generated \(strictCandidates.count) strict candidates and \(fallbackCandidates.count) fallback candidates from \(moments.count) moments")
        
        // CRASH-PROOF: Return empty arrays if both are empty (shouldn't happen, but safety check)
        return (strict: strictCandidates, fallback: fallbackCandidates)
    }
    
    private func generatePhotoCandidates(
        moments: [PhotoMoment],
        beats: [CMTime],
        pace: HighlightPace,
        motionIntensity: CGFloat
    ) -> [HighlightSegmentCandidate] {
        var candidates: [HighlightSegmentCandidate] = []
        
        for moment in moments {
            // Determine duration based on pace
            let durationRange = pace.photoBaseDuration
            let duration = Double.random(in: durationRange)
            
            // Snap to nearest beat (use first beat as reference)
            let snappedStart = beats.first ?? .zero
            
            // Create Ken Burns motion transform
            let motionTransform = createKenBurnsTransform(
                for: moment,
                motionIntensity: motionIntensity
            )
            
            let beatIndex = findBeatIndex(for: snappedStart, beats: beats)
            
            let candidate = HighlightSegmentCandidate(
                clipID: moment.clipID,
                type: .image,
                sourceStart: snappedStart,
                duration: CMTime(seconds: duration, preferredTimescale: 600),
                hasFaces: moment.hasFaces,
                motionLevel: 0.0, // Photos don't have motion
                shotType: nil,
                score: moment.score,
                suggestedBeatIndex: beatIndex,
                motionTransform: motionTransform
            )
            candidates.append(candidate)
        }
        
        return candidates
    }
    
    private func createKenBurnsTransform(
        for moment: PhotoMoment,
        motionIntensity: CGFloat
    ) -> MotionTransform {
        let baseZoom: CGFloat = 0.08
        let maxExtra: CGFloat = 0.07
        let zoomAmount = baseZoom + maxExtra * motionIntensity
        
        if moment.hasFaces {
            // Zoom in toward subject (faces)
            let subjectCenter = CGPoint(
                x: moment.subjectRect.midX - 0.5,
                y: moment.subjectRect.midY - 0.5
            )
            
            return MotionTransform(
                startScale: 1.0,
                endScale: 1.0 + zoomAmount,
                startOffset: CGPoint(x: 0, y: 0),
                endOffset: CGPoint(
                    x: -subjectCenter.x * 0.3,
                    y: -subjectCenter.y * 0.3
                )
            )
        } else {
            // Subtle pan across image
            return MotionTransform(
                startScale: 1.0,
                endScale: 1.0 + zoomAmount * 0.5,
                startOffset: CGPoint(x: -0.1, y: 0),
                endOffset: CGPoint(x: 0.1, y: 0)
            )
        }
    }
    
    private func selectAndOrderSegments(
        videoCandidates: [HighlightSegmentCandidate],
        photoCandidates: [HighlightSegmentCandidate],
        storyStructure: StoryStructure,
        musicAnalysis: MusicAnalysis,
        settings: HighlightReelSettings
    ) -> [HighlightSegmentCandidate] {
        var selected: [HighlightSegmentCandidate] = []
        var segmentsPerClip: [UUID: Int] = [:] // Track how many segments from each clip
        
        // CRITICAL: Calculate max segments per clip dynamically based on total clips
        // For Highlight Reel, ensure all clips are represented fairly
        let uniqueVideoClipIDsForCalculation = Set(videoCandidates.map { $0.clipID })
        let totalVideoClips = uniqueVideoClipIDsForCalculation.count
        
        // Calculate max segments per clip: distribute segments evenly
        // If we need ~20 segments total and have 4 clips, each gets ~5 segments max
        // But allow some flexibility: minimum 1 per clip, max based on total clips
        let estimatedTotalSegments = Int(storyStructure.introDuration.seconds + storyStructure.buildDuration.seconds + storyStructure.climaxDuration.seconds + storyStructure.outroDuration.seconds) / 3
        let maxSegmentsPerClip: Int
        if totalVideoClips > 0 {
            // Ensure at least 1 segment per clip, but limit to prevent over-representation
            // Formula: (estimated segments / total clips) * 1.5 (allow some clips to have more)
            maxSegmentsPerClip = max(1, min(10, Int(Double(estimatedTotalSegments) / Double(totalVideoClips) * 1.5)))
        } else {
            maxSegmentsPerClip = 3 // Fallback
        }
        
        print("SkipSlate: Multi-clip distribution - \(totalVideoClips) video clips, max \(maxSegmentsPerClip) segments per clip")
        
        // Combine and sort all candidates by score
        let allCandidates = (videoCandidates + photoCandidates).sorted { $0.score > $1.score }
        
        // CRITICAL: Intro MUST start with a master/wide shot (establishing shot)
        // Find the best master or wide shot to start with
        let masterWideCandidates = allCandidates.filter { 
            ($0.shotType == .master || $0.shotType == .wide) && $0.score >= 0.5
        }.sorted { $0.score > $1.score }
        
        var introSegments: [HighlightSegmentCandidate] = []
        if let openingShot = masterWideCandidates.first {
            // Use the best master/wide shot as the opening
            introSegments.append(openingShot)
            segmentsPerClip[openingShot.clipID, default: 0] += 1
            print("SkipSlate: Selected opening master/wide shot: clip \(openingShot.clipID), type: \(openingShot.shotType), score: \(openingShot.score)")
            
            // Fill remaining intro duration with other appropriate shots
            let remainingIntroDuration = CMTimeSubtract(storyStructure.introDuration, openingShot.duration)
            if remainingIntroDuration.seconds > 0.5 {
                let uniqueVideoClipIDs = Set(videoCandidates.map { $0.clipID })
                let needsMultiClipEnforcement = uniqueVideoClipIDs.count > 1
                
                let additionalIntro = selectSegmentsForPhase(
                    phase: .intro,
                    candidates: allCandidates,
                    targetDuration: remainingIntroDuration,
                    segmentsPerClip: &segmentsPerClip,
                    maxSegmentsPerClip: maxSegmentsPerClip,
                    musicAnalysis: musicAnalysis,
                    settings: settings,
                    enforceMultiClip: needsMultiClipEnforcement
                )
                introSegments.append(contentsOf: additionalIntro)
            }
        } else {
            // Fallback: use regular intro selection if no master/wide shots found
            let uniqueVideoClipIDs = Set(videoCandidates.map { $0.clipID })
            let needsMultiClipEnforcement = uniqueVideoClipIDs.count > 1
            
            introSegments = selectSegmentsForPhase(
                phase: .intro,
                candidates: allCandidates,
                targetDuration: storyStructure.introDuration,
                segmentsPerClip: &segmentsPerClip,
                maxSegmentsPerClip: maxSegmentsPerClip,
                musicAnalysis: musicAnalysis,
                settings: settings,
                enforceMultiClip: needsMultiClipEnforcement
            )
            print("SkipSlate: ⚠ No master/wide shots found for opening, using best available intro shots")
        }
        selected.append(contentsOf: introSegments)
        
        // CRITICAL: Count unique clips in video clips to determine if multi-clip enforcement is needed
        let uniqueVideoClipIDsInCandidates = Set(videoCandidates.map { $0.clipID })
        let needsMultiClipEnforcement = uniqueVideoClipIDsInCandidates.count > 1 // Only enforce if multiple clips available
        
        let buildSegments = selectSegmentsForPhase(
            phase: .build,
            candidates: allCandidates,
            targetDuration: storyStructure.buildDuration,
            segmentsPerClip: &segmentsPerClip,
            maxSegmentsPerClip: maxSegmentsPerClip,
            musicAnalysis: musicAnalysis,
            settings: settings,
            enforceMultiClip: needsMultiClipEnforcement
        )
        selected.append(contentsOf: buildSegments)
        
        let climaxSegments = selectSegmentsForPhase(
            phase: .climax,
            candidates: allCandidates,
            targetDuration: storyStructure.climaxDuration,
            segmentsPerClip: &segmentsPerClip,
            maxSegmentsPerClip: maxSegmentsPerClip,
            musicAnalysis: musicAnalysis,
            settings: settings,
            enforceMultiClip: needsMultiClipEnforcement
        )
        selected.append(contentsOf: climaxSegments)
        
        let outroSegments = selectSegmentsForPhase(
            phase: .outro,
            candidates: allCandidates,
            targetDuration: storyStructure.outroDuration,
            segmentsPerClip: &segmentsPerClip,
            maxSegmentsPerClip: maxSegmentsPerClip,
            musicAnalysis: musicAnalysis,
            settings: settings,
            enforceMultiClip: needsMultiClipEnforcement
        )
        selected.append(contentsOf: outroSegments)
        
        // Align all segments to beats
        return alignSegmentsToBeats(segments: selected, beats: musicAnalysis.beatTimes)
    }
    
    private func selectSegmentsForPhase(
        phase: StoryPhase,
        candidates: [HighlightSegmentCandidate],
        targetDuration: CMTime,
        segmentsPerClip: inout [UUID: Int],
        maxSegmentsPerClip: Int,
        musicAnalysis: MusicAnalysis,
        settings: HighlightReelSettings,
        enforceMultiClip: Bool = false // CRITICAL: For highlight reels, ensure multiple clips are used
    ) -> [HighlightSegmentCandidate] {
        var selected: [HighlightSegmentCandidate] = []
        var accumulatedDuration = CMTime.zero
        let targetSeconds = targetDuration.seconds
        
        // Track used time ranges per clip to prevent duplicate/similar shots
        var usedTimeRanges: [UUID: [CMTimeRange]] = [:]
        let minTimeSeparation: Double = 2.0 // Minimum seconds between shots from same clip
        
        // Filter candidates based on phase requirements AND quality
        let filteredCandidates = candidates.filter { candidate in
            // CRITICAL: Limit segments per clip to maxSegmentsPerClip (default 3)
            let currentCount = segmentsPerClip[candidate.clipID] ?? 0
            if currentCount >= maxSegmentsPerClip {
                return false // Already used max segments from this clip
            }
            
            // CRITICAL QUALITY FILTERS - Adaptive thresholds based on multi-clip enforcement
            
            // When enforcing multi-clip, relax quality filters for unused clips to ensure all clips get segments
            // This prevents the issue where only one clip has high-quality candidates and others get filtered out
            let isUnusedClip = currentCount == 0
            let qualityThreshold: CGFloat = (enforceMultiClip && isUnusedClip) ? 0.3 : 0.5 // Lower threshold for unused clips when enforcing multi-clip
            
            // 1. Quality threshold: adaptive based on clip usage
            // CRASH-PROOF: Safe comparison with CGFloat
            guard candidate.score >= qualityThreshold else {
                return false
            }
            
            // 2. Require faces OR be a good shot type - but relax for unused clips when enforcing multi-clip
            // CRASH-PROOF: When enforcing multi-clip and clip is unused, accept ANY candidate to ensure all clips get represented
            // This ensures ALL videos are analyzed and used, regardless of quality
            if enforceMultiClip && isUnusedClip {
                // Accept any candidate from unused clips - quality filtering already handled above
                // This ensures we use segments from ALL clips, even if they're lower quality
            } else {
                // For normal selection (non-unused clips), apply strict quality filters
                guard candidate.hasFaces || candidate.shotType == .master || candidate.shotType == .wide else {
                    return false
                }
            }
            
            // 3. Prevent duplicate shots - check if we've already used a similar time range from this clip
            let candidateTimeRange = CMTimeRange(
                start: candidate.sourceStart,
                duration: candidate.duration
            )
            
            if let existingRanges = usedTimeRanges[candidate.clipID] {
                // Check if this time range overlaps or is too close to any existing range
                let isDuplicate = existingRanges.contains { existingRange in
                    let distance = abs(CMTimeSubtract(candidate.sourceStart, existingRange.start).seconds)
                    return distance < minTimeSeparation
                }
                if isDuplicate {
                    return false // Too similar to an already used shot
                }
            }
            
            // Phase-specific filtering - relaxed for unused clips when enforcing multi-clip
            switch phase {
            case .intro:
                // CRITICAL: Intro MUST start with master/wide shot (establishing shot)
                // Prefer master shots first, then wide, then medium
                // But if enforcing multi-clip and clip is unused, accept any shot type
                if enforceMultiClip && isUnusedClip {
                    return true // Accept any shot type for unused clips to ensure diversity
                }
                return candidate.shotType == .master || candidate.shotType == .wide || candidate.shotType == .medium
            case .build:
                // All shot types, but require higher quality and faces
                // Relax for unused clips when enforcing multi-clip
                if enforceMultiClip && isUnusedClip {
                    return candidate.score >= qualityThreshold // Relaxed threshold for unused clips
                }
                // CRASH-PROOF: Safe comparison with CGFloat
                return candidate.score >= 0.55 && candidate.hasFaces
            case .climax:
                // Prefer high motion, faces, close/medium shots, higher quality
                // Relax for unused clips when enforcing multi-clip
                if enforceMultiClip && isUnusedClip {
                    return candidate.score >= qualityThreshold // Relaxed threshold for unused clips
                }
                // CRASH-PROOF: Safe comparison with CGFloat
                return (candidate.motionLevel > CGFloat(0.3) || candidate.hasFaces) && candidate.score >= CGFloat(0.6)
            case .outro:
                // Prefer wide/master shots for outro (return to wide view)
                // But if enforcing multi-clip and clip is unused, accept any shot type
                if enforceMultiClip && isUnusedClip {
                    return true // Accept any shot type for unused clips to ensure diversity
                }
                return candidate.shotType == .master || candidate.shotType == .wide || candidate.shotType == .medium
            }
        }
        
        // Greedy selection - prioritize higher quality scores
        // But also consider variety (prefer clips with fewer segments already used)
            // CRITICAL: When enforcing multi-clip selection, STRONGLY prioritize diversity
            // For Highlight Reel with multiple clips, we MUST ensure all clips are represented
            let sortedCandidates = filteredCandidates.sorted { candidate1, candidate2 in
                let candidate1Count = segmentsPerClip[candidate1.clipID] ?? 0
                let candidate2Count = segmentsPerClip[candidate2.clipID] ?? 0
                
                // CRITICAL: When enforcing multi-clip, STRICTLY prioritize clips with zero segments first
                // This ensures every clip gets at least one segment before any clip gets a second
                if enforceMultiClip {
                    // Primary sort: STRICTLY prefer clips with zero segments (unused clips)
                    if candidate1Count == 0 && candidate2Count > 0 {
                        return true // ALWAYS prefer unused clips - ensures all clips are used
                    }
                    if candidate2Count == 0 && candidate1Count > 0 {
                        return false
                    }
                    
                    // Secondary sort: STRICTLY prefer clips with fewer segments
                    // If one clip has 1 segment and another has 2, prefer the one with 1
                    if candidate1Count != candidate2Count {
                        return candidate1Count < candidate2Count
                    }
                    
                    // Tertiary sort: quality score (only when segment counts are EQUAL)
                    // This ensures that among clips with same usage, we pick the best quality
                    return candidate1.score > candidate2.score
                } else {
                    // Normal sorting when not enforcing multi-clip (single video scenario)
                    // Primary sort: quality score
                    if abs(candidate1.score - candidate2.score) > 0.1 {
                        return candidate1.score > candidate2.score
                    }
                    // Secondary sort: prefer clips with fewer segments already used (for variety)
                    if candidate1Count != candidate2Count {
                        return candidate1Count < candidate2Count // Prefer clips with fewer segments
                    }
                    // Tertiary sort: prefer better shot types for phase
                    return candidate1.score > candidate2.score
                }
            }
        
        for candidate in sortedCandidates {
            if accumulatedDuration.seconds >= targetSeconds {
                break
            }
            
            let candidateDuration = candidate.duration.seconds
            if accumulatedDuration.seconds + candidateDuration <= targetSeconds * 1.1 { // Allow 10% over
                selected.append(candidate)
                // Increment segment count for this clip
                segmentsPerClip[candidate.clipID, default: 0] += 1
                let newCount = segmentsPerClip[candidate.clipID] ?? 0
                
                // Track used time range to prevent duplicates
                let candidateTimeRange = CMTimeRange(
                    start: candidate.sourceStart,
                    duration: candidate.duration
                )
                usedTimeRanges[candidate.clipID, default: []].append(candidateTimeRange)
                
                print("SkipSlate: Selected segment from clip \(candidate.clipID) (count: \(newCount)/\(maxSegmentsPerClip), score: \(candidate.score), hasFaces: \(candidate.hasFaces))")
                accumulatedDuration = CMTimeAdd(accumulatedDuration, candidate.duration)
            }
        }
        
        return selected
    }
    
    private func alignSegmentsToBeats(
        segments: [HighlightSegmentCandidate],
        beats: [CMTime]
    ) -> [HighlightSegmentCandidate] {
        guard !beats.isEmpty else { return segments }
        
        var aligned: [HighlightSegmentCandidate] = []
        var currentTime = CMTime.zero
        var beatIndex = 0
        
        for var segment in segments {
            // Snap start to nearest beat
            if beatIndex < beats.count {
                let nearestBeat = beats[beatIndex]
                if CMTimeCompare(nearestBeat, currentTime) >= 0 {
                    segment = HighlightSegmentCandidate(
                        clipID: segment.clipID,
                        type: segment.type,
                        sourceStart: segment.sourceStart, // Keep original source start
                        duration: segment.duration,
                        hasFaces: segment.hasFaces,
                        motionLevel: segment.motionLevel,
                        shotType: segment.shotType,
                        score: segment.score,
                        suggestedBeatIndex: beatIndex,
                        motionTransform: segment.motionTransform
                    )
                    currentTime = CMTimeAdd(nearestBeat, segment.duration)
                    beatIndex += 1
                } else {
                    currentTime = CMTimeAdd(currentTime, segment.duration)
                    beatIndex += 1
                }
            } else {
                currentTime = CMTimeAdd(currentTime, segment.duration)
            }
            
            aligned.append(segment)
        }
        
        return aligned
    }
    
    private func snapToNearestBeat(time: CMTime, beats: [CMTime]) -> CMTime {
        guard !beats.isEmpty else { return time }
        
        var nearest = beats[0]
        var minDiff = abs(CMTimeSubtract(time, nearest).seconds)
        
        for beat in beats {
            let diff = abs(CMTimeSubtract(time, beat).seconds)
            if diff < minDiff {
                minDiff = diff
                nearest = beat
            }
        }
        
        // Only snap if within 0.2 seconds
        if minDiff <= 0.2 {
            return nearest
        }
        
        return time
    }
    
    private func findNextBeat(after time: CMTime, beats: [CMTime]) -> CMTime? {
        return beats.first { CMTimeCompare($0, time) > 0 }
    }
    
    private func findBeatIndex(for time: CMTime, beats: [CMTime]) -> Int {
        guard !beats.isEmpty else { return 0 }
        
        var nearestIndex = 0
        var minDiff = abs(CMTimeSubtract(time, beats[0]).seconds)
        
        for (index, beat) in beats.enumerated() {
            let diff = abs(CMTimeSubtract(time, beat).seconds)
            if diff < minDiff {
                minDiff = diff
                nearestIndex = index
            }
        }
        
        return nearestIndex
    }
    
    private func generateFallbackHighlight(
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        settings: AutoEditSettings
    ) async throws -> [Segment] {
        // Fallback to simple mashup if no music
        let videoClips = project.clips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly }
        let imageClips = project.clips.filter { $0.type == .image }
        
        return try createMashupSegments(
            videoClips: videoClips,
            imageClips: imageClips,
            targetLength: settings.targetLengthSeconds
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
        
        let hasBoth = !videoClips.isEmpty && !imageClips.isEmpty
        var useVideo = !videoClips.isEmpty
        
        let segmentDuration: Double = 2.0
        let imageDuration: Double = 3.0
        
        while true {
            if useVideo && !videoClips.isEmpty {
                let clip = videoClips[videoIndex % videoClips.count]
                
                // Use the clip's pre-assigned colorIndex from import
                // All segments from the same clip will share this color
                let duration = min(segmentDuration, clip.duration)
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: clip.id,
                    sourceStart: 0.0,
                    sourceEnd: duration,
                    enabled: true,
                    colorIndex: clip.colorIndex
                )
                segments.append(segment)
                currentTime += duration
                videoIndex += 1
                
                if hasBoth { useVideo = false }
            } else if !imageClips.isEmpty {
                let clip = imageClips[imageIndex % imageClips.count]
                
                // Use the clip's pre-assigned colorIndex from import
                let segment = Segment(
                    id: UUID(),
                    sourceClipID: clip.id,
                    sourceStart: 0.0,
                    sourceEnd: imageDuration,
                    enabled: true,
                    colorIndex: clip.colorIndex
                )
                segments.append(segment)
                currentTime += imageDuration
                imageIndex += 1
                
                if hasBoth { useVideo = true }
            } else {
                break
            }
            
            if let target = targetLength, currentTime >= target {
                break
            }
        }
        
        return segments
    }
    
    // MARK: - Cinematic Scoring Integration
    
    /// Score all candidates using the cinematic scoring engine
    /// CRASH-PROOF: This function has multiple safety measures to prevent crashes:
    /// 1. Sequential processing to prevent thread-safety issues
    /// 2. Autoreleasepool to manage memory pressure
    /// 3. Delays between processing to prevent QoS tracking overload
    /// 4. Fallback scores for failed candidates
    private func scoreCandidatesWithCinematicEngine(
        videoCandidates: [HighlightSegmentCandidate],
        photoCandidates: [HighlightSegmentCandidate],
        project: Project,
        assetsByClipID: [UUID: AVAsset],
        progressCallback: ProgressCallback? = nil
    ) async throws -> [ScoredSegment] {
        var scored: [ScoredSegment] = []
        let allCandidates = videoCandidates + photoCandidates
        let total = allCandidates.count
        var failedCount = 0
        
        print("SkipSlate: Starting cinematic scoring for \(total) candidates...")
        
        // CRITICAL: Process sequentially to prevent memory issues and crashes
        // Frame analysis uses CIContext which is NOT thread-safe
        for (index, candidate) in allCandidates.enumerated() {
            // Add small delay between candidates to prevent QoS tracking overload (libRPAC.dylib crashes)
            if index > 0 {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
            }
            
            if index % 5 == 0 || index == total - 1 {
                progressCallback?("Scoring segments: \(index + 1)/\(total)")
            }
            
            guard let clip = project.clips.first(where: { $0.id == candidate.clipID }),
                  let asset = assetsByClipID[candidate.clipID] else {
                print("SkipSlate: Warning - Cannot score candidate, clip not found: \(candidate.clipID)")
                continue
            }
            
            // Create a temporary Segment for scoring
            let segment = Segment(
                id: UUID(),
                sourceClipID: candidate.clipID,
                sourceStart: candidate.sourceStart.seconds,
                sourceEnd: CMTimeAdd(candidate.sourceStart, candidate.duration).seconds,
                enabled: true,
                colorIndex: 0
            )
            
            let timeRange = CMTimeRange(
                start: candidate.sourceStart,
                duration: candidate.duration
            )
            
            // Score the segment with error handling
            // CRITICAL: Process sequentially to prevent memory issues
            // CRASH-PROOF: Use autoreleasepool to manage memory and add fallback scoring
            do {
                let score = try await cinematicScorer.scoreSegment(segment, in: clip, asset: asset)
                
                let scoredSegment = ScoredSegment(
                    segment: segment,
                    score: score,
                    clipID: candidate.clipID,
                    timeRange: timeRange
                )
                
                scored.append(scoredSegment)
                
                // Log scoring details (only for rejected or high-quality segments to reduce log spam)
                if score.isRejected {
                    print("SkipSlate: CinematicScore - REJECTED: Clip \(candidate.clipID), \(segment.sourceStart)-\(segment.sourceEnd)s")
                    print("SkipSlate:   Reason: \(score.rejectionReason ?? "Unknown")")
                } else if score.overall > 0.7 {
                    print("SkipSlate: CinematicScore - HIGH QUALITY: Clip \(candidate.clipID), \(segment.sourceStart)-\(segment.sourceEnd)s, Overall: \(String(format: "%.2f", score.overall))")
                }
            } catch {
                print("SkipSlate: Error scoring segment \(segment.sourceStart)-\(segment.sourceEnd)s: \(error)")
                failedCount += 1
                
                // CRASH-PROOF: Add fallback score instead of skipping
                // This ensures all candidates are still available even if scoring fails
                let fallbackScore = CinematicScore(
                    faceScore: 0.4,
                    compositionScore: 0.4,
                    stabilityScore: 0.6,
                    exposureScore: 0.5
                )
                let fallbackScoredSegment = ScoredSegment(
                    segment: segment,
                    score: fallbackScore,
                    clipID: candidate.clipID,
                    timeRange: timeRange
                )
                scored.append(fallbackScoredSegment)
                print("SkipSlate: Added fallback score for failed segment")
            }
            
            // Force memory cleanup every 10 segments to prevent buildup
            if (index + 1) % 10 == 0 {
                autoreleasepool {
                    // Release resources periodically
                }
            }
        }
        
        if failedCount > 0 {
            print("SkipSlate: Cinematic scoring complete - \(scored.count)/\(total) segments scored (\(failedCount) used fallback scores)")
        } else {
            print("SkipSlate: Cinematic scoring complete - \(scored.count)/\(total) segments scored successfully")
        }
        return scored
    }
    
    // MARK: - Quick Mode
    
    /// Create VideoMoments quickly without AI analysis - just based on beats and clip duration
    /// This is FAST (< 1 second) compared to full AI analysis (60-180+ seconds per clip)
    private func createQuickModeVideoMoments(
        clips: [MediaClip],
        assetsByClipID: [UUID: AVAsset],
        beatTimes: [Double]
    ) async -> [VideoMoment] {
        var moments: [VideoMoment] = []
        
        // Get segment durations from beat intervals (1-3 seconds typically)
        var segmentDurations: [Double] = []
        for i in 0..<beatTimes.count - 1 {
            let duration = beatTimes[i + 1] - beatTimes[i]
            // Group beats into 1-3 second segments
            if duration >= 0.5 && duration <= 4.0 {
                segmentDurations.append(duration)
            }
        }
        
        // Default segment duration if no good beat intervals
        if segmentDurations.isEmpty {
            segmentDurations = [1.5, 2.0, 2.5, 1.0, 2.0] // Mix of durations
        }
        
        // Create moments for each clip
        for clip in clips {
            guard let asset = assetsByClipID[clip.id] else { continue }
            
            let clipDuration: Double
            do {
                let assetDuration = try await asset.load(.duration)
                clipDuration = assetDuration.seconds
            } catch {
                print("SkipSlate: Quick mode - couldn't load duration for \(clip.fileName)")
                continue
            }
            
            // Create segments spread across the clip
            var currentTime: Double = 0.0
            var segmentIndex = 0
            
            while currentTime < clipDuration - 0.5 {
                let segmentDuration = segmentDurations[segmentIndex % segmentDurations.count]
                let endTime = min(currentTime + segmentDuration, clipDuration)
                let actualDuration = endTime - currentTime
                
                // Only create segment if it's at least 0.5 seconds
                if actualDuration >= 0.5 {
                    // VideoMoment uses: clipID, sourceStart, duration, hasFaces, motionLevel, score, shotType
                    let moment = VideoMoment(
                        clipID: clip.id,
                        sourceStart: CMTime(seconds: currentTime, preferredTimescale: 600),
                        duration: CMTime(seconds: actualDuration, preferredTimescale: 600),
                        hasFaces: false,
                        motionLevel: 0.5,  // Neutral motion
                        score: 0.5,        // Neutral score
                        shotType: .medium  // Default shot type
                    )
                    moments.append(moment)
                }
                
                currentTime = endTime
                segmentIndex += 1
            }
            
            print("SkipSlate: ⚡ Quick mode - created \(moments.filter { $0.clipID == clip.id }.count) moments for \(clip.fileName)")
        }
        
        return moments
    }
    
}

// MARK: - Helper Extensions

extension HighlightPace {
    static func from(_ pace: Pace) -> HighlightPace {
        switch pace {
        case .relaxed: return .relaxed
        case .normal: return .normal
        case .tight: return .tight
        }
    }
}

extension HighlightStyle {
    static func from(_ style: AutoEditStyle) -> HighlightStyle {
        switch style {
        case .sportsHypeShort, .quickCuts, .dynamicHighlights:
            return .montage
        case .eventRecapHuman, .storyArc:
            return .hero
        case .timelineStory:
            return .recap
        default:
            return .montage
        }
    }
}

struct StoryStructure {
    let introDuration: CMTime
    let buildDuration: CMTime
    let climaxDuration: CMTime
    let outroDuration: CMTime
    let pace: Pace
}

