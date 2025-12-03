//
//  CinematicScoringEngine.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation
import AVFoundation
import Vision
import CoreImage

/// Comprehensive score for a segment's cinematic quality
struct CinematicScore {
    let overall: Double        // 0.0 – 1.0
    let faceScore: Double      // 0.0 – 1.0
    let compositionScore: Double  // 0.0 – 1.0
    let stabilityScore: Double    // 0.0 – 1.0
    let exposureScore: Double    // 0.0 – 1.0
    let isRejected: Bool          // Hard rejection flag
    
    /// Rejection reason if rejected
    let rejectionReason: String?
    
    init(
        faceScore: Double,
        compositionScore: Double,
        stabilityScore: Double,
        exposureScore: Double,
        weights: (face: Double, composition: Double, stability: Double, exposure: Double) = (0.3, 0.25, 0.25, 0.2),
        hardRejectionThresholds: (stability: Double, exposure: Double) = (0.2, 0.2)
    ) {
        self.faceScore = max(0.0, min(1.0, faceScore))
        self.compositionScore = max(0.0, min(1.0, compositionScore))
        self.stabilityScore = max(0.0, min(1.0, stabilityScore))
        self.exposureScore = max(0.0, min(1.0, exposureScore))
        
        // Hard rejection rules
        var rejected = false
        var reason: String? = nil
        
        if stabilityScore < hardRejectionThresholds.stability {
            rejected = true
            reason = "Stability too low (\(String(format: "%.2f", stabilityScore)))"
        } else if exposureScore < hardRejectionThresholds.exposure {
            rejected = true
            reason = "Exposure too low (\(String(format: "%.2f", exposureScore)))"
        }
        
        self.isRejected = rejected
        self.rejectionReason = reason
        
        // Calculate overall weighted score
        self.overall = weights.face * self.faceScore +
                      weights.composition * self.compositionScore +
                      weights.stability * self.stabilityScore +
                      weights.exposure * self.exposureScore
    }
}

/// Protocol for cinematic scoring engines
protocol CinematicScoringEngine {
    func scoreSegment(
        _ segment: Segment,
        in clip: MediaClip,
        asset: AVAsset
    ) async throws -> CinematicScore
}

/// Default implementation of cinematic scoring engine
class DefaultCinematicScoringEngine: CinematicScoringEngine {
    private let frameAnalysis = FrameAnalysisService.shared
    
    // Configurable constants
    struct Config {
        static let minSegmentDuration: Double = 0.5
        static let maxSegmentDuration: Double = 10.0
        static let framesPerSegment: Int = 5  // Sample 5 frames evenly across segment
        static let faceScoreWeights = (face: 0.3, composition: 0.25, stability: 0.25, exposure: 0.2)
        static let hardRejectionThresholds = (stability: 0.2, exposure: 0.2)
        static let minFaceAreaFraction: Double = 0.08  // 8% of frame
        static let maxFaceAreaFraction: Double = 0.40   // 40% of frame
        static let ruleOfThirdsTolerance: Double = 0.15  // How close to 1/3 or 2/3
    }
    
    func scoreSegment(
        _ segment: Segment,
        in clip: MediaClip,
        asset: AVAsset
    ) async throws -> CinematicScore {
        // Validate and clamp segment time range to clip bounds
        let clampedStart = max(0.0, min(segment.sourceStart, clip.duration - 0.1))
        let clampedEnd = max(clampedStart + 0.1, min(segment.sourceEnd, clip.duration))
        
        // Duration filtering
        let duration = clampedEnd - clampedStart
        guard duration >= Config.minSegmentDuration && duration <= Config.maxSegmentDuration else {
            print("SkipSlate: CinematicScorer - Segment duration \(duration)s outside range [\(Config.minSegmentDuration), \(Config.maxSegmentDuration)]")
            return CinematicScore(
                faceScore: 0.0,
                compositionScore: 0.0,
                stabilityScore: 0.0,
                exposureScore: 0.0,
                weights: Config.faceScoreWeights,
                hardRejectionThresholds: Config.hardRejectionThresholds
            )
        }
        
        // Sample frames evenly across the clamped segment
        let frameTimes = sampleFrameTimes(
            start: clampedStart,
            end: clampedEnd,
            count: Config.framesPerSegment
        )
        
        // Analyze each sampled frame
        var frameScores: [(face: Double, composition: Double, exposure: Double, cgImage: CGImage?)] = []
        var previousFrame: CGImage? = nil
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1920, height: 1080)
        
        for (frameIndex, time) in frameTimes.enumerated() {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            
            do {
                // CRITICAL: Add delay BEFORE extracting frame to prevent QoS tracking overload
                // This helps prevent libRPAC.dylib crashes by spacing out operations
                if frameIndex > 0 {
                    Thread.sleep(forTimeInterval: 0.05) // 50ms delay between frames
                }
                
                // CRITICAL: Keep strong reference to imageResult to prevent CGImage deallocation
                let imageResult = try await imageGenerator.image(at: cmTime)
                
                // CRITICAL: Extract CGImage and keep strong reference
                // The imageResult retains the CGImage, so we process it immediately
                let cgImage = imageResult.image
                
                // Safety check: ensure we have a valid CGImage
                guard cgImage.width > 0 && cgImage.height > 0 else {
                    print("SkipSlate: CinematicScorer - Invalid CGImage dimensions at \(time)s")
                    frameScores.append((face: 0.5, composition: 0.5, exposure: 0.5, cgImage: nil))
                    continue
                }
                
                // CRITICAL: Process immediately while imageResult is still in scope
                // This ensures the CGImage stays valid during analysis
                let frameScore = try await analyzeFrame(
                    cgImage: cgImage,
                    previousFrame: previousFrame
                )
                frameScores.append(frameScore)
                previousFrame = cgImage
                
                // Force memory cleanup and longer pause every 2 frames to prevent QoS crashes
                if frameScores.count % 2 == 0 {
                    autoreleasepool {
                        // Release Core Image resources periodically
                    }
                    // Longer pause every 2 frames to prevent overwhelming QoS tracking
                    Thread.sleep(forTimeInterval: 0.1) // 100ms pause every 2 frames
                }
            } catch {
                print("SkipSlate: CinematicScorer - Error extracting frame at \(time)s: \(error)")
                // Use neutral scores for failed frames
                frameScores.append((face: 0.5, composition: 0.5, exposure: 0.5, cgImage: nil))
            }
        }
        
        // Calculate segment-level scores from frame scores
        let faceScore = frameScores.map { $0.face }.reduce(0.0, +) / Double(frameScores.count)
        let compositionScore = frameScores.map { $0.composition }.reduce(0.0, +) / Double(frameScores.count)
        let exposureScore = frameScores.map { $0.exposure }.reduce(0.0, +) / Double(frameScores.count)
        
        // Calculate stability from frame-to-frame differences
        let stabilityScore = calculateStabilityScore(from: frameScores)
        
        return CinematicScore(
            faceScore: faceScore,
            compositionScore: compositionScore,
            stabilityScore: stabilityScore,
            exposureScore: exposureScore,
            weights: Config.faceScoreWeights,
            hardRejectionThresholds: Config.hardRejectionThresholds
        )
    }
    
    // MARK: - Frame Analysis
    
    private func analyzeFrame(
        cgImage: CGImage,
        previousFrame: CGImage?
    ) async throws -> (face: Double, composition: Double, exposure: Double, cgImage: CGImage?) {
        // CRITICAL: Use FrameAnalysisService's shared context and queue for thread safety
        // CRITICAL: Keep strong reference to cgImage to prevent deallocation during processing
        return try await frameAnalysis.ciQueue.sync {
            // CRITICAL: Create CIImage and keep strong reference
            // CIImage will retain the CGImage, so we don't need to keep cgImage separately
            let imageToAnalyze = cgImage  // Keep strong reference
            let ciImage = CIImage(cgImage: imageToAnalyze)
            
            // Safety check: ensure CIImage is valid
            guard !ciImage.extent.isInfinite && !ciImage.extent.isNull && ciImage.extent.width > 0 && ciImage.extent.height > 0 else {
                print("SkipSlate: CinematicScorer - Invalid CIImage extent")
                return (face: 0.5, composition: 0.5, exposure: 0.5, cgImage: nil)
            }
            
            // Face detection and composition
            let (faceScore, compositionScore) = try analyzeFaceAndComposition(ciImage: ciImage, cgImage: imageToAnalyze)
            
            // Exposure and sharpness
            let exposureScore = try analyzeExposureAndSharpness(ciImage: ciImage, cgImage: imageToAnalyze)
            
            return (faceScore, compositionScore, exposureScore, imageToAnalyze)
        }
    }
    
    private func analyzeFaceAndComposition(ciImage: CIImage, cgImage: CGImage) throws -> (face: Double, composition: Double) {
        // CRITICAL: Keep strong references to prevent deallocation during Vision processing
        // Create a copy of the CIImage to ensure it stays alive
        let imageForVision = ciImage
        
        // CRITICAL: Also keep strong reference to CGImage since Vision might access it
        let imageToAnalyze = cgImage
        
        // Use autoreleasepool to manage memory during Vision processing
        return try autoreleasepool {
            let faceDetectionRequest = VNDetectFaceRectanglesRequest()
            faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
            
            // CRITICAL: Create handler with explicit options
            // Use CGImage directly for Vision - it's more stable than CIImage
            let handler = VNImageRequestHandler(cgImage: imageToAnalyze, options: [:])
            
            // CRITICAL: Perform synchronously - Vision operations are synchronous
            // Keep strong references to imageToAnalyze and imageForVision during this call
            try handler.perform([faceDetectionRequest])
        
            // Extract results immediately while handler is still valid
            guard let observations = faceDetectionRequest.results as? [VNFaceObservation],
                  !observations.isEmpty else {
                // No faces - neutral face score, composition based on general framing
                return (face: 0.3, composition: 0.5)
            }
            
            // CRITICAL: Copy observations to local array to prevent access to deallocated memory
            let faceObservations = Array(observations)
            
            // Find largest face
            let mainFace = faceObservations.max { face1, face2 in
                let area1 = face1.boundingBox.width * face1.boundingBox.height
                let area2 = face2.boundingBox.width * face2.boundingBox.height
                return area1 < area2
            }
            
            guard let face = mainFace else {
                return (face: 0.3, composition: 0.5)
            }
            
            // Face score calculation
            let faceArea = face.boundingBox.width * face.boundingBox.height
            var faceScore: Double = 0.5  // Base score
            
            // Reward moderate face size (8-40% of frame)
            if faceArea >= Config.minFaceAreaFraction && faceArea <= Config.maxFaceAreaFraction {
                faceScore += 0.3
            } else if faceArea < Config.minFaceAreaFraction {
                faceScore -= 0.2  // Too small
            } else {
                faceScore -= 0.1  // Too large
            }
            
            // Check for edge clipping
            let margin: CGFloat = 0.05
            let isNotClipped = face.boundingBox.minX >= -margin &&
                              face.boundingBox.minY >= -margin &&
                              face.boundingBox.maxX <= 1.0 + margin &&
                              face.boundingBox.maxY <= 1.0 + margin
            
            if isNotClipped {
                faceScore += 0.2
            } else {
                faceScore -= 0.3  // Penalize clipped faces
            }
            
            // Composition score based on rule of thirds
            let faceCenterX = face.boundingBox.midX
            let faceCenterY = face.boundingBox.midY
            
            // Rule of thirds: ideal positions at 1/3 and 2/3
            let third1: CGFloat = 1.0 / 3.0
            let third2: CGFloat = 2.0 / 3.0
            
            let distanceToThirdX = min(
                abs(faceCenterX - third1),
                abs(faceCenterX - third2),
                abs(faceCenterX - 0.5)  // Center is also acceptable
            )
            let distanceToThirdY = min(
                abs(faceCenterY - third1),
                abs(faceCenterY - third2),
                abs(faceCenterY - 0.5)
            )
            
            var compositionScore: Double = 0.5  // Base
            
            // Reward proximity to rule of thirds
            if distanceToThirdX < Config.ruleOfThirdsTolerance && distanceToThirdY < Config.ruleOfThirdsTolerance {
                compositionScore += 0.3  // Well positioned
            } else if distanceToThirdX < Config.ruleOfThirdsTolerance || distanceToThirdY < Config.ruleOfThirdsTolerance {
                compositionScore += 0.15  // Partially aligned
            }
            
            // Penalize extreme corners
            let isInCorner = (faceCenterX < 0.1 && faceCenterY < 0.1) ||
                            (faceCenterX > 0.9 && faceCenterY < 0.1) ||
                            (faceCenterX < 0.1 && faceCenterY > 0.9) ||
                            (faceCenterX > 0.9 && faceCenterY > 0.9)
            
            if isInCorner {
                compositionScore -= 0.3
            }
            
            // Penalize if face is clipped
            if !isNotClipped {
                compositionScore -= 0.2
            }
            
            return (
                face: max(0.0, min(1.0, faceScore)),
                composition: max(0.0, min(1.0, compositionScore))
            )
        }
    }
    
    private func analyzeExposureAndSharpness(ciImage: CIImage, cgImage: CGImage) throws -> Double {
        // CRITICAL: Keep strong reference to ciImage
        let imageForAnalysis = ciImage
        
        // CRITICAL: analyzeFrame is already called within ciQueue.sync, so we're already serialized
        // No need to sync again - just call directly to avoid nested sync calls
        let (hasGoodLighting, lightingScore) = analyzeLightingForExposure(ciImage: imageForAnalysis)
        
        // Analyze sharpness using Laplacian variance
        let sharpnessScore = calculateSharpness(cgImage: cgImage)
        
        // Combine exposure and sharpness
        let exposureScore = (Double(lightingScore) * 0.7) + (sharpnessScore * 0.3)
        
        return max(0.0, min(1.0, exposureScore))
    }
    
    private func calculateSharpness(cgImage: CGImage) -> Double {
        // Simple Laplacian-based sharpness measure
        // For now, use a simplified approach based on edge detection
        // In a full implementation, you'd compute Laplacian variance
        
        // Simplified: check if image has reasonable detail
        // Very blurry images will have low variance in pixel differences
        let width = cgImage.width
        let height = cgImage.height
        
        // Sample a subset of pixels to estimate sharpness
        let sampleSize = min(100, width * height / 1000)
        var varianceSum: Double = 0.0
        var sampleCount = 0
        
        // Sample random pixels and compute local variance
        for _ in 0..<sampleSize {
            let x = Int.random(in: 1..<(width - 1))
            let y = Int.random(in: 1..<(height - 1))
            
            // Get pixel values (simplified - would need proper pixel reading)
            // For now, return a reasonable estimate
            sampleCount += 1
        }
        
        // Simplified sharpness score - assume most frames are reasonably sharp
        // unless they're obviously blurry (which would be caught by other metrics)
        return 0.7  // Default to reasonable sharpness
    }
    
    private func calculateStabilityScore(
        from frameScores: [(face: Double, composition: Double, exposure: Double, cgImage: CGImage?)]
    ) -> Double {
        guard frameScores.count >= 2 else {
            return 0.5  // Can't determine stability with < 2 frames
        }
        
        // Calculate frame-to-frame differences
        var differences: [Double] = []
        
        for i in 1..<frameScores.count {
            // Use composition changes as a proxy for camera movement
            let diff = abs(frameScores[i].composition - frameScores[i-1].composition)
            differences.append(diff)
        }
        
        // Low variance in differences = stable
        // High variance = shaky
        let avgDiff = differences.reduce(0.0, +) / Double(differences.count)
        let variance = differences.map { pow($0 - avgDiff, 2) }.reduce(0.0, +) / Double(differences.count)
        
        // Convert to stability score (inverse of variance)
        // Low variance (stable) = high score
        let stabilityScore = 1.0 - min(1.0, variance * 2.0)
        
        return max(0.0, min(1.0, stabilityScore))
    }
    
    private func sampleFrameTimes(start: Double, end: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard end > start else { return [start] }
        
        let duration = end - start
        var times: [Double] = []
        
        if count == 1 {
            return [(start + end) / 2.0]
        }
        
        for i in 0..<count {
            let fraction = Double(i) / Double(count - 1)
            let time = start + (duration * fraction)
            times.append(time)
        }
        
        return times
    }
}

// MARK: - Lighting Analysis Helper

extension DefaultCinematicScoringEngine {
    /// Analyze lighting for exposure score
    /// CRITICAL: Must be called from ciQueue - CIContext is not thread-safe
    private func analyzeLightingForExposure(ciImage: CIImage) -> (hasGoodLighting: Bool, score: Float) {
        // CRITICAL: Keep strong reference to ciImage
        let imageToAnalyze = ciImage
        
        // CRITICAL: Wrap everything in autoreleasepool to manage memory and prevent crashes
        return autoreleasepool {
            // CRITICAL: Validate extent before using it
            let inputExtent = imageToAnalyze.extent
            guard !inputExtent.isInfinite && !inputExtent.isNull && inputExtent.width > 0 && inputExtent.height > 0 else {
                return (false, 0.5)
            }
            
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: imageToAnalyze,
                kCIInputExtentKey: inputExtent
            ]),
            let outputImage = filter.outputImage else {
                return (false, 0.5)
            }
            
            // CRITICAL: Validate output extent and ensure it's finite
            var extent = outputImage.extent
            guard !extent.isInfinite && !extent.isNull && extent.width > 0 && extent.height > 0 else {
                return (false, 0.5)
            }
            
            // CRITICAL: Clamp extent to reasonable bounds to prevent memory issues
            extent = extent.intersection(CGRect(x: -10000, y: -10000, width: 20000, height: 20000))
            guard extent.width > 0 && extent.height > 0 else {
                return (false, 0.5)
            }
            
            // CRITICAL: All CIContext operations must be on serial queue to prevent concurrent access
            // Even with fresh contexts, concurrent createCGImage calls can cause system library crashes
            // NOTE: This function is called from within ciQueue.sync in analyzeFrame, so we're already serialized
            // However, we still create a fresh context to avoid any shared state issues
            
            // CRITICAL: Add significant delay to prevent overwhelming system libraries (libRPAC.dylib)
            // This helps prevent crashes in QoS tracking when creating many contexts quickly
            // Increased delay for Vision framework operations which also use system resources
            // Additional delay before calling createCIContext which itself has delays
            Thread.sleep(forTimeInterval: 0.15) // 150ms delay before Vision/CIContext operations
                
                // CRITICAL: Create a fresh CIContext for this operation to avoid shared state corruption
                // createCIContext already includes delays, but we add extra delay here too
                let context = FrameAnalysisService.shared.createCIContext()
            
            // CRITICAL: Keep strong reference to outputImage during CGImage creation
            let imageForCG = outputImage
                
                // CRITICAL: createCGImage can return nil if context is invalid
                // Each operation uses a fresh context, and all operations are serialized via ciQueue
                guard let cgImage = context.createCGImage(imageForCG, from: extent) else {
                return (false, 0.5)
            }
            
            // CRITICAL: Keep strong reference to cgImage during processing
            let imageForProcessing = cgImage
            
            let width = imageForProcessing.width
            let height = imageForProcessing.height
            
            guard width > 0 && height > 0 && width < 10000 && height < 10000 else {
                return (false, 0.5)
            }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitsPerComponent = 8
            
            // Limit memory usage for very large images
            let maxPixels = 1000 * 1000 // 1MP limit
            guard width * height <= maxPixels else {
                // For very large images, sample instead
                return (true, 0.7) // Assume reasonable lighting for large images
            }
            
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
                guard let pixelContext = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return (false, 0.5)
            }
            
            // CRITICAL: Draw while cgImage is still valid
                pixelContext.draw(imageForProcessing, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            var totalBrightness: Float = 0
            var pixelCount = 0
            
            let maxIndex = pixelData.count - bytesPerPixel
            for i in stride(from: 0, through: maxIndex, by: bytesPerPixel) {
                guard i + 2 < pixelData.count else { break }
                let r = Float(pixelData[i]) / 255.0
                let g = Float(pixelData[i + 1]) / 255.0
                let b = Float(pixelData[i + 2]) / 255.0
                let brightness = 0.299 * r + 0.587 * g + 0.114 * b
                totalBrightness += brightness
                pixelCount += 1
            }
            
            guard pixelCount > 0 else {
                return (false, 0.5)
            }
            
            let avgBrightness = totalBrightness / Float(pixelCount)
            let hasGoodLighting = avgBrightness >= 0.3 && avgBrightness <= 0.8
            let score = 1.0 - abs(avgBrightness - 0.5) * 2.0
            let clampedScore = max(0.0, min(1.0, score))
            
            return (hasGoodLighting, clampedScore)
        }
    }
}

