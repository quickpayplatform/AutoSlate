//
//  HighlightReelVisualAnalyzer.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation
import Vision
import CoreImage

/// Analyzes video clips and photos for highlight reel editing
class HighlightReelVisualAnalyzer {
    static let shared = HighlightReelVisualAnalyzer()
    
    private let frameAnalysis = FrameAnalysisService.shared
    
    // CRITICAL: Use FrameAnalysisService's shared context and queue for thread safety
    // Access the serial queue from FrameAnalysisService for thread-safe operations
    private var ciQueue: DispatchQueue {
        return FrameAnalysisService.shared.ciQueue
    }
    
    /// Create a fresh CIContext for each operation to avoid shared state corruption
    /// CRITICAL: Each operation gets its own context to prevent memory corruption and crashes
    private func createCIContext() -> CIContext {
        return FrameAnalysisService.shared.createCIContext()
    }
    
    private init() {}
    
    /// Progress callback type
    typealias ProgressCallback = (String) -> Void
    
    /// Analyze all video clips and return VideoMoment candidates
    func analyzeVideoClips(
        clips: [MediaClip],
        assetsByClipID: [UUID: AVAsset],
        progressCallback: ProgressCallback? = nil
    ) async throws -> [VideoMoment] {
        var moments: [VideoMoment] = []
        
        let videoClips = clips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly }
        let totalClips = videoClips.count
        print("SkipSlate: Analyzing \(totalClips) video clips for visual moments...")
        print("SkipSlate: CRITICAL - Processing clips SEQUENTIALLY (one at a time) to prevent crashes")
        
        // CRITICAL: Process clips one at a time, sequentially - no concurrent analysis
        // This prevents CIContext conflicts and memory issues
        for (index, clip) in videoClips.enumerated() {
            guard let asset = assetsByClipID[clip.id] else {
                print("SkipSlate: Warning - No asset found for clip \(clip.fileName)")
                continue
            }
            
            let clipStartTime = Date()
            progressCallback?("Analyzing video \(index + 1)/\(totalClips): \(clip.fileName)")
            print("SkipSlate: [SEQUENTIAL] Analyzing video clip \(index + 1)/\(totalClips): \(clip.fileName)")
            
            // CRITICAL: await ensures this clip is completely done before starting the next one
            // Wrap in do-catch to prevent crashes
            do {
                // This await ensures sequential processing - no overlap between clips
                let videoMoments = try await analyzeVideoClip(
                    clip: clip,
                    asset: asset,
                    progressCallback: { message in
                        progressCallback?("\(clip.fileName): \(message)")
                    }
                )
                let clipTime = Date().timeIntervalSince(clipStartTime)
                print("SkipSlate: [SEQUENTIAL] Found \(videoMoments.count) moments in clip \(clip.fileName) (took \(String(format: "%.1f", clipTime))s)")
                moments.append(contentsOf: videoMoments)
                
                progressCallback?("Video \(index + 1)/\(totalClips) complete (\(String(format: "%.1f", clipTime))s)")
                
                // Small delay to ensure all resources are released before next clip
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second pause
            } catch {
                let clipTime = Date().timeIntervalSince(clipStartTime)
                print("SkipSlate: Error analyzing clip \(clip.fileName): \(error) (took \(String(format: "%.1f", clipTime))s)")
                progressCallback?("Video \(index + 1)/\(totalClips) failed - skipping")
                // Continue with next clip instead of crashing
                continue
            }
        }
        
        return moments
    }
    
    /// Analyze a single video clip
    private func analyzeVideoClip(
        clip: MediaClip,
        asset: AVAsset,
        progressCallback: ProgressCallback? = nil
    ) async throws -> [VideoMoment] {
        // Sample frames at a reasonable rate - more aggressive for very long videos
        // This prevents memory issues and crashes on large videos
        let duration = try await asset.load(.duration)
        let sampleInterval: Double
        if duration.seconds > 300 { // 5+ minutes
            sampleInterval = 3.0 // ~0.33 FPS for very long videos
        } else if duration.seconds > 120 { // 2-5 minutes
            sampleInterval = 2.0 // 0.5 FPS
        } else if duration.seconds > 60 { // 1-2 minutes
            sampleInterval = 1.0 // 1 FPS
        } else {
            sampleInterval = 0.5 // 2 FPS for shorter videos
        }
        
        print("SkipSlate: Video duration: \(String(format: "%.1f", duration.seconds))s, using \(String(format: "%.1f", 1.0/sampleInterval)) FPS sampling")
        
        // Add error handling and limits
        let frameAnalyses: [FrameAnalysisService.FrameAnalysis]
        do {
            frameAnalyses = try await frameAnalysis.analyzeFrames(
                from: asset,
                sampleInterval: sampleInterval,
                progressCallback: { current, total in
                    progressCallback?("Analyzing frames: \(current)/\(total)")
                }
            )
        } catch {
            print("SkipSlate: Error analyzing frames for \(clip.fileName): \(error)")
            // Return empty moments if analysis fails - don't crash
            return []
        }
        
        guard !frameAnalyses.isEmpty else {
            print("SkipSlate: No frame analyses returned for \(clip.fileName)")
            return []
        }
        
        print("SkipSlate: Processing \(frameAnalyses.count) frame analyses for \(clip.fileName)...")
        
        // Process frames in batches to manage memory
        var moments: [VideoMoment] = []
        var previousAnalysis: FrameAnalysisService.FrameAnalysis?
        var currentWindowStart: Double = 0
        var windowAnalyses: [FrameAnalysisService.FrameAnalysis] = []
            
            // Group frames into 1-3 second windows
            let windowDuration = 2.0
            
            // Process analyses in batches to prevent memory issues
            let batchSize = 50
            for batchStart in stride(from: 0, to: frameAnalyses.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, frameAnalyses.count)
                let batch = Array(frameAnalyses[batchStart..<batchEnd])
                
                autoreleasepool {
                    for analysis in batch {
                        // Calculate motion level from previous frame
                        let motionLevel: CGFloat
                        if let prev = previousAnalysis {
                            // Simple motion: difference in shot quality score
                            motionLevel = CGFloat(abs(analysis.shotQualityScore - prev.shotQualityScore))
                        } else {
                            motionLevel = 0.0
                        }
                        
                        windowAnalyses.append(analysis)
                        
                        // If window is complete or we hit a significant change
                        let windowTime = analysis.timestamp - currentWindowStart
                        let shouldCloseWindow = windowTime >= windowDuration || 
                                               (previousAnalysis != nil && motionLevel > 0.3)
                        
                        if shouldCloseWindow && !windowAnalyses.isEmpty {
                            // Create moment from window with error handling
                            do {
                                let avgScore = windowAnalyses.map { $0.shotQualityScore }.reduce(0, +) / Float(windowAnalyses.count)
                                let hasFacesInWindow = windowAnalyses.contains { $0.hasFace }
                                let isLandscapeWindow = windowAnalyses.contains { $0.isLandscapeShot }
                                let avgFramingScore = windowAnalyses.map { $0.framingScore }.reduce(0, +) / Float(windowAnalyses.count)
                                let hasGoodLighting = windowAnalyses.contains { $0.hasGoodLighting }
                                
                                // CRITICAL: Per user requirement - ALL videos should be analyzed regardless of quality
                                // Quality filtering happens later during selection, not during moment generation
                                // This ensures ALL clips produce moments that can be cached and scored
                                
                                // RELAXED QUALITY FILTERS - Only reject truly unusable moments (extreme cases)
                                // 1. Minimum quality score threshold - VERY LOW to accept almost everything (0.1 instead of 0.5)
                                // This allows low-quality moments to be generated and cached, then filtered during selection
                                let passesQualityCheck = avgScore >= 0.1  // Accept almost everything
                                
                                // 2. Accept shots with faces OR landscape shots OR any shot with minimum quality
                                // No longer rejecting shots without faces - quality filtering happens during selection
                                let passesFaceCheck = hasFacesInWindow || isLandscapeWindow || avgScore >= 0.2  // Accept if quality > 0.2
                                
                                // 3. RELAXED framing check - Accept moments with ANY framing score (even 0.0)
                                // Quality filtering happens during selection, not here
                                let passesFramingCheck = true  // Accept ALL framing scores - filter later
                                
                                // 4. Accept moments regardless of lighting - filter during selection instead
                                let passesLightingCheck = true  // Accept ALL lighting conditions - filter later
                                
                                // CRITICAL: Accept ALL moments that pass minimal checks
                                // This ensures EVERY clip produces at least some moments for caching and scoring
                                if passesQualityCheck && passesFaceCheck {
                                    // All filters passed - this is a good shot
                                    let motionVariation = windowAnalyses.enumerated().compactMap { index, analysis in
                                        index > 0 ? abs(analysis.shotQualityScore - windowAnalyses[index - 1].shotQualityScore) : nil
                                    }.reduce(0, +) / Float(max(1, windowAnalyses.count - 1))
                                    
                                    // Determine shot type using improved detection
                                    let faceAnalysis = windowAnalyses.first(where: { $0.hasFace })
                                    let faceBounds = faceAnalysis?.faceBounds
                                    let faceArea = faceBounds.map { $0.width * $0.height }
                                    let avgMotionLevel = windowAnalyses.map { CGFloat($0.shotQualityScore) }.reduce(0, +) / CGFloat(windowAnalyses.count)
                                    let shotType = ShotType.from(faceArea: faceArea, hasFaces: hasFacesInWindow, motionLevel: avgMotionLevel)
                                    
                                    let moment = VideoMoment(
                                        clipID: clip.id,
                                        sourceStart: CMTime(seconds: currentWindowStart, preferredTimescale: 600),
                                        duration: CMTime(seconds: windowTime, preferredTimescale: 600),
                                        hasFaces: hasFacesInWindow,
                                        motionLevel: CGFloat(motionVariation),
                                        score: CGFloat(avgScore),
                                        shotType: shotType
                                    )
                                    moments.append(moment)
                                } else {
                                    // Rejected - log reason
                                    if !passesQualityCheck {
                                        print("SkipSlate: Rejected moment - quality score too low: \(avgScore)")
                                    } else if !passesFaceCheck {
                                        print("SkipSlate: Rejected moment - no faces and not landscape: \(avgScore)")
                                    } else if !passesFramingCheck {
                                        print("SkipSlate: Rejected moment - poor framing: \(avgFramingScore)")
                                    } else if !passesLightingCheck {
                                        print("SkipSlate: Rejected moment - poor lighting and borderline quality: \(avgScore)")
                                    }
                                }
                                
                                // Reset window
                                currentWindowStart = analysis.timestamp
                                windowAnalyses = [analysis]
                            } catch {
                                print("SkipSlate: Error creating moment from window: \(error)")
                                // Reset window on error
                                currentWindowStart = analysis.timestamp
                                windowAnalyses = [analysis]
                            }
                        }
                        
                        previousAnalysis = analysis
                    }
                }
            }
            
            // Close final window with error handling
            if !windowAnalyses.isEmpty, let lastAnalysis = frameAnalyses.last {
                autoreleasepool {
                    do {
                        let windowTime = lastAnalysis.timestamp - currentWindowStart
                        let avgScore = windowAnalyses.map { $0.shotQualityScore }.reduce(0, +) / Float(windowAnalyses.count)
                        let hasFacesInWindow = windowAnalyses.contains { $0.hasFace }
                        let isLandscapeWindow = windowAnalyses.contains { $0.isLandscapeShot }
                        let avgFramingScore = windowAnalyses.map { $0.framingScore }.reduce(0, +) / Float(windowAnalyses.count)
                        let hasGoodLighting = windowAnalyses.contains { $0.hasGoodLighting }
                        
                        // CRITICAL: Same relaxed quality filters as above
                        // Per user requirement - ALL videos should be analyzed regardless of quality
                        
                        // 1. Minimum quality score threshold - VERY LOW to accept almost everything
                        let passesQualityCheck = avgScore >= 0.1  // Accept almost everything
                        
                        // 2. Accept shots with faces OR landscape OR any shot with minimum quality
                        let passesFaceCheck = hasFacesInWindow || isLandscapeWindow || avgScore >= 0.2
                        
                        // 3. Accept ALL framing scores - filter later during selection
                        let passesFramingCheck = true
                        
                        // 4. Accept ALL lighting conditions - filter later during selection
                        let passesLightingCheck = true
                        
                        // CRITICAL: Accept final moment if it passes minimal checks
                        guard passesQualityCheck && passesFaceCheck else {
                            print("SkipSlate: Rejected final moment - quality score too low: \(avgScore)")
                            return
                        }
                        
                        // All filters passed - create the moment
                        let motionVariation = windowAnalyses.enumerated().compactMap { index, analysis in
                            index > 0 ? abs(analysis.shotQualityScore - windowAnalyses[index - 1].shotQualityScore) : nil
                        }.reduce(0, +) / Float(max(1, windowAnalyses.count - 1))
                        
                        // Determine shot type using improved detection
                        let faceAnalysis = windowAnalyses.first(where: { $0.hasFace })
                        let faceBounds = faceAnalysis?.faceBounds
                        let faceArea = faceBounds.map { $0.width * $0.height }
                        let avgMotionLevel = windowAnalyses.map { CGFloat($0.shotQualityScore) }.reduce(0, +) / CGFloat(windowAnalyses.count)
                        let shotType = ShotType.from(faceArea: faceArea, hasFaces: hasFacesInWindow, motionLevel: avgMotionLevel)
                        
                        let moment = VideoMoment(
                            clipID: clip.id,
                            sourceStart: CMTime(seconds: currentWindowStart, preferredTimescale: 600),
                            duration: CMTime(seconds: windowTime, preferredTimescale: 600),
                            hasFaces: hasFacesInWindow,
                            motionLevel: CGFloat(motionVariation),
                            score: CGFloat(avgScore),
                            shotType: shotType
                        )
                        moments.append(moment)
                    } catch {
                        print("SkipSlate: Error creating final moment: \(error)")
                    }
                }
            }
            
        print("SkipSlate: Created \(moments.count) moments from \(frameAnalyses.count) frame analyses for \(clip.fileName)")
        
        // CRITICAL FALLBACK: Per user requirement - ALL videos should be analyzed regardless of quality
        // If a clip produced zero moments (all rejected), create at least ONE fallback moment from the middle
        // This ensures every clip has moments for caching and scoring, even if quality is very low
        if moments.isEmpty && !frameAnalyses.isEmpty {
            print("SkipSlate: ⚠️ Clip \(clip.fileName) produced zero moments - creating fallback moment from middle of clip")
            
            // Create a fallback moment from the middle of the clip
            let middleIndex = frameAnalyses.count / 2
            let middleAnalysis = frameAnalyses[middleIndex]
            let clipDuration = clip.duration
            let fallbackStart = max(0.0, min(middleAnalysis.timestamp - 1.0, clipDuration - 2.0))
            let fallbackDuration = min(2.0, clipDuration - fallbackStart)
            
            let fallbackMoment = VideoMoment(
                clipID: clip.id,
                sourceStart: CMTime(seconds: fallbackStart, preferredTimescale: 600),
                duration: CMTime(seconds: fallbackDuration, preferredTimescale: 600),
                hasFaces: middleAnalysis.hasFace,
                motionLevel: 0.0,
                score: CGFloat(max(0.1, middleAnalysis.shotQualityScore)), // Minimum 0.1 to pass quality checks
                shotType: .medium // Default shot type
            )
            moments.append(fallbackMoment)
            print("SkipSlate: ✅ Created fallback moment for \(clip.fileName) at \(fallbackStart)s (duration: \(fallbackDuration)s, score: \(fallbackMoment.score))")
        }
        
        return moments
    }
    
    /// Analyze all photo clips and return PhotoMoment candidates
    func analyzePhotoClips(
        clips: [MediaClip],
        assetsByClipID: [UUID: AVAsset],
        progressCallback: ProgressCallback? = nil
    ) async throws -> [PhotoMoment] {
        var moments: [PhotoMoment] = []
        
        let imageClips = clips.filter { $0.type == .image }
        let totalPhotos = imageClips.count
        print("SkipSlate: Analyzing \(totalPhotos) photo clips...")
        
        for (index, clip) in imageClips.enumerated() {
            guard let asset = assetsByClipID[clip.id] else {
                print("SkipSlate: Warning - No asset found for photo \(clip.fileName)")
                continue
            }
            
            progressCallback?("Analyzing photo \(index + 1)/\(totalPhotos): \(clip.fileName)")
            print("SkipSlate: Analyzing photo \(index + 1)/\(totalPhotos): \(clip.fileName)")
            let photoMoment = try await analyzePhotoClip(clip: clip, asset: asset)
            moments.append(photoMoment)
        }
        
        return moments
    }
    
    /// Analyze a single photo clip
    private func analyzePhotoClip(clip: MediaClip, asset: AVAsset) async throws -> PhotoMoment {
        // Extract image from photo
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        guard let cgImage = try? await imageGenerator.image(at: .zero).image else {
            throw NSError(domain: "HighlightReelVisualAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract image"])
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Detect faces
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        try handler.perform([faceDetectionRequest])
        
        let observations = faceDetectionRequest.results as? [VNFaceObservation] ?? []
        let hasFaces = !observations.isEmpty
        
        // Find subject bounding box (faces or center of image)
        let subjectRect: CGRect = if let primaryFace = observations.max(by: { face1, face2 in
            let area1 = face1.boundingBox.width * face1.boundingBox.height
            let area2 = face2.boundingBox.width * face2.boundingBox.height
            return area1 < area2
        }) {
            primaryFace.boundingBox
        } else {
            // No faces - use center region
            CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        }
        
        // Calculate interest score
        var score: CGFloat = 0.5 // Base score
        
        if hasFaces {
            score += 0.3 // Faces add significant interest
        }
        
        // Check contrast/brightness (simplified)
        // Use shared CIContext to avoid Metal cache conflicts
        // Wrap in autoreleasepool for memory management
        autoreleasepool {
            if let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: ciImage.extent
            ]),
            let output = avgFilter.outputImage {
                // CRITICAL: createCGImage must be called on the serial queue for thread safety
                // Use async to avoid blocking
                let hasValidImage = ciQueue.sync {
                    let context = createCIContext()
                    return context.createCGImage(output, from: output.extent) != nil
                }
                if hasValidImage {
                    // Simple brightness check
                    // Higher score for balanced exposure
                    score += 0.2
                }
            }
        }
        
        score = min(score, 1.0)
        
        // Base duration will be set by pace settings
        return PhotoMoment(
            clipID: clip.id,
            duration: CMTime(seconds: 2.0, preferredTimescale: 600), // Default, will be adjusted
            hasFaces: hasFaces,
            score: score,
            subjectRect: subjectRect
        )
    }
}

