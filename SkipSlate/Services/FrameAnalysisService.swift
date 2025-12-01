//
//  FrameAnalysisService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation
import Vision
import CoreImage

/// Service for analyzing video frames to detect faces, people, and framing quality
class FrameAnalysisService {
    static let shared = FrameAnalysisService()
    
    // Serial queue to ensure thread-safe CIContext creation
    // CRITICAL: Each CIContext operation will use its own context to avoid shared state corruption
    // CRITICAL: Use .background QoS (lowest priority) to minimize QoS tracking in system libraries (libRPAC.dylib)
    // This prevents crashes in QoS hash tables when creating many CIContext instances
    // CRITICAL: QoS tracking crashes occur when the system tracks too many concurrent operations
    let ciQueue = DispatchQueue(
        label: "com.skipslate.frameanalysis.ci",
        qos: .background,  // Lowest QoS to minimize QoS tracking overhead
        attributes: [],  // Serial queue (default)
        autoreleaseFrequency: .workItem  // Clean up memory after each work item
    )
    
    private init() {
        // No shared CIContext - we'll create per-operation contexts to avoid crashes
    }
    
    /// Create a new CIContext for a single operation
    /// CRITICAL: Each operation gets its own context to prevent memory corruption and crashes
    /// CRITICAL: This should be called from within ciQueue.sync to ensure thread safety
    func createCIContext() -> CIContext {
        // CRITICAL: Add SIGNIFICANT delay before creating context to prevent QoS tracking overload
        // Creating CIContext instances triggers aggressive QoS tracking in libRPAC.dylib
        // The hash table corruption happens when QoS tracking can't keep up with rapid context creation
        // Drastically increased to 500ms to give the system plenty of time to process QoS updates
        Thread.sleep(forTimeInterval: 0.50) // 500ms delay before each context creation
        
        // CRITICAL: Create context with minimal options to reduce system library overhead
        // Use software renderer and disable caching to minimize memory usage and QoS tracking
        let options: [CIContextOption: Any] = [
            .useSoftwareRenderer: true,  // Use CPU renderer to avoid Metal crashes
            .cacheIntermediates: false,  // Don't cache intermediate results to reduce memory
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(), // Explicit color space
            .outputColorSpace: CGColorSpaceCreateDeviceRGB() // Explicit output color space
        ]
        
        // CRITICAL: Wrap in autoreleasepool to ensure immediate cleanup of temporary objects
        // Also add delay AFTER creation to allow QoS tracking to settle
        return autoreleasepool {
            let context = CIContext(options: options)
            // CRITICAL: Longer delay after creation to let QoS tracking fully complete
            // The context creation triggers QoS tracking, so we need to wait for it to settle
            Thread.sleep(forTimeInterval: 0.20) // 200ms delay after context creation to prevent crashes
            return context
        }
    }
    
    /// Result of frame analysis
    struct FrameAnalysis {
        let timestamp: Double
        let hasFace: Bool
        let faceCount: Int
        let primaryFaceCentered: Bool // Is the main face well-centered?
        let faceBounds: CGRect? // Bounds of primary face in normalized coordinates (0-1)
        let framingScore: Float // 0-1, higher = better framing
        let shotQualityScore: Float // 0-1, overall quality score for this frame
        let isStable: Bool // Is the shot stable (not shaky)?
        let hasGoodLighting: Bool // Is the lighting good?
        let hasMotion: Bool // Is there interesting motion/action?
        let isLandscapeShot: Bool // Is this a landscape/wide shot (no faces, but scenic/wide framing)?
    }
    
    /// Progress callback for frame analysis
    typealias FrameProgressCallback = (Int, Int) -> Void // (current, total)
    
    /// Analyze frames from a video asset to detect faces and framing quality
    /// Samples frames at regular intervals (e.g., every 0.5 seconds)
    func analyzeFrames(
        from asset: AVAsset,
        sampleInterval: Double = 0.5,
        progressCallback: FrameProgressCallback? = nil
    ) async throws -> [FrameAnalysis] {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "FrameAnalysisService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        // Calculate actual video size (accounting for rotation)
        let actualSize = naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(actualSize.width), height: abs(actualSize.height))
        
        var analyses: [FrameAnalysis] = []
        
        // Sample frames at regular intervals
        // CRITICAL: Reduced max frames significantly to prevent QoS tracking crashes
        // Creating too many CIContext instances overwhelms libRPAC.dylib's hash table
        // 50 frames max = fewer context creations = less chance of hash table corruption
        let maxFrames = 50  // Drastically reduced from 200 to prevent crashes
        var adjustedSampleInterval = sampleInterval
        var sampleCount = Int(duration.seconds / adjustedSampleInterval)
        
        // If we'd exceed max frames, increase sample interval
        if sampleCount > maxFrames {
            adjustedSampleInterval = duration.seconds / Double(maxFrames)
            sampleCount = maxFrames
            print("SkipSlate: Video is long (\(duration.seconds)s), adjusting sample interval to \(adjustedSampleInterval)s to limit to \(maxFrames) frames")
        }
        
        let frameDuration = CMTime(seconds: adjustedSampleInterval, preferredTimescale: 600)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1920, height: 1080) // Limit image size to reduce memory
        
        for i in 0..<sampleCount {
            let sampleTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            
            // Report progress every frame or every 5 frames for long videos
            if i % max(1, sampleCount / 20) == 0 || i == sampleCount - 1 {
                progressCallback?(i + 1, sampleCount)
                if sampleCount > 10 {
                    print("SkipSlate: Analyzing frame \(i + 1)/\(sampleCount)...")
                }
            }
            
            // Add error handling for frame extraction
            // Extract frame and analyze - keep strong reference to result
            do {
                // CRITICAL: Keep strong reference to imageResult to prevent CGImage deallocation
                let imageResult = try await imageGenerator.image(at: sampleTime)
                
                // CRITICAL: Extract CGImage and keep strong reference
                // The imageResult retains the CGImage, so we process it immediately
                let cgImage = imageResult.image
                
                // Safety check: ensure we have a valid CGImage
                guard cgImage.width > 0 && cgImage.height > 0 else {
                    print("SkipSlate: Invalid CGImage dimensions at \(sampleTime.seconds)s")
                    continue
                }
                
                // CRITICAL: Process immediately while imageResult is still in scope
                // This ensures the CGImage stays valid during analysis
                
                // Analyze frame with error handling and memory management
                // CRITICAL: Process frames sequentially on serial queue to prevent concurrent CIContext access
                // CRITICAL: Use sync to ensure frames are processed one at a time, no overlap
                // CRITICAL: Keep strong reference to cgImage to prevent deallocation during processing
                do {
                    // CRITICAL: Use sync to block until this frame is completely done before next frame starts
                    // Keep strong reference to cgImage and self to prevent deallocation
                    // Wrap in autoreleasepool to ensure proper memory cleanup and prevent crashes
                    let analysis: FrameAnalysis = try autoreleasepool {
                        return try ciQueue.sync {
            // CRITICAL: Add SIGNIFICANT delay to prevent overwhelming system libraries (libRPAC.dylib)
            // This helps prevent crashes in QoS tracking when processing many frames
            // Vision framework also uses CIContext internally, so we need MUCH larger delays
            // Increased to 250ms to drastically reduce QoS tracking pressure and prevent hash table corruption
            Thread.sleep(forTimeInterval: 0.25) // 250ms delay between frames to prevent QoS crashes
                            
                        // Keep strong reference to cgImage during processing
                        let imageToAnalyze = cgImage
                            
                            // Additional safety: validate image before processing
                            guard imageToAnalyze.width > 0 && imageToAnalyze.height > 0,
                                  imageToAnalyze.width < 10000 && imageToAnalyze.height < 10000 else {
                                throw NSError(domain: "FrameAnalysisService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CGImage dimensions"])
                            }
                            
                        return try self.analyzeFrame(imageToAnalyze, timestamp: sampleTime.seconds, videoSize: videoSize)
                        }
                    }
                    analyses.append(analysis)
                } catch {
                    print("SkipSlate: Error analyzing frame at \(sampleTime.seconds)s: \(error)")
                    // Continue with next frame instead of crashing
                    continue
                }
                
                // Force memory cleanup every 2 frames to prevent buildup (very frequent cleanup)
                if (i + 1) % 2 == 0 {
                    autoreleasepool {
                        // This helps release Core Image resources periodically
                    }
                    // CRITICAL: MUCH longer delay every 2 frames to prevent QoS tracking overload
                    // This gives the system time to process QoS tracking updates before more operations
                    // Drastically increased delay to allow libRPAC.dylib hash table to fully settle
                    Thread.sleep(forTimeInterval: 1.0) // 1000ms (1 second) delay every 2 frames to prevent libRPAC.dylib crashes
                }
            } catch {
                print("SkipSlate: Error extracting frame at \(sampleTime.seconds)s: \(error)")
                // Continue with next frame instead of crashing
                continue
            }
        }
        
        print("SkipSlate: Completed frame analysis: \(analyses.count)/\(sampleCount) frames analyzed")
        
        return analyses
    }
    
    /// Analyze a single frame for faces, framing, and overall shot quality
    /// CRITICAL: This function MUST be called from ciQueue.sync to ensure thread safety
    /// All CIContext operations in this function assume they're running on ciQueue
    /// This function is synchronous - Vision framework operations are synchronous
    private func analyzeFrame(_ cgImage: CGImage, timestamp: Double, videoSize: CGSize) throws -> FrameAnalysis {
        // Safety check: ensure valid CGImage
        guard cgImage.width > 0 && cgImage.height > 0 else {
            print("SkipSlate: Invalid CGImage in analyzeFrame: \(cgImage.width)x\(cgImage.height)")
            return FrameAnalysis(
                timestamp: timestamp,
                hasFace: false,
                faceCount: 0,
                primaryFaceCentered: false,
                faceBounds: nil,
                framingScore: 0.0,
                shotQualityScore: 0.0,
                isStable: true,
                hasGoodLighting: false,
                hasMotion: false,
                isLandscapeShot: false
            )
        }
        
        // CRITICAL: Create CIImage synchronously and keep strong reference
        // Ensure the CGImage stays alive by creating CIImage immediately
        // CIImage will retain the CGImage, so we don't need to keep cgImage separately
        let ciImage = CIImage(cgImage: cgImage)
        
        // Safety check: ensure CIImage is valid
        guard !ciImage.extent.isInfinite && !ciImage.extent.isNull && ciImage.extent.width > 0 && ciImage.extent.height > 0 else {
            print("SkipSlate: Invalid CIImage extent: \(ciImage.extent)")
            return FrameAnalysis(
                timestamp: timestamp,
                hasFace: false,
                faceCount: 0,
                primaryFaceCentered: false,
                faceBounds: nil,
                framingScore: 0.0,
                shotQualityScore: 0.0,
                isStable: true,
                hasGoodLighting: false,
                hasMotion: false,
                isLandscapeShot: false
            )
        }
        
        // Analyze multiple quality factors with error handling
        // These are synchronous operations, so we can use autoreleasepool safely
        let (hasGoodLighting, lightingScore): (Bool, Float)
        do {
            (hasGoodLighting, lightingScore) = try autoreleasepool {
                return analyzeLighting(ciImage: ciImage)
            }
        } catch {
            print("SkipSlate: Error in lighting analysis: \(error)")
            (hasGoodLighting, lightingScore) = (false, 0.5)
        }
        
        // Motion analysis is now synchronous - Core Image operations are synchronous
        let (hasMotion, motionScore) = autoreleasepool {
            return analyzeMotion(ciImage: ciImage, timestamp: timestamp)
        }
        
        let isStable = true // TODO: Implement stability analysis (compare with previous frame)
        
        // Use Vision framework for face detection
        // CRITICAL: Use CGImage directly (we already have it) to avoid Vision creating internal CIContext instances
        // This prevents Vision framework from needing to convert CIImage, which creates additional CIContext operations
        // and can cause QoS tracking crashes in libRPAC.dylib
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        // CRITICAL: Keep strong reference to original CGImage for Vision
        // Using CGImage directly avoids Vision framework creating internal CIContext instances
        let cgImageForVision = cgImage // Use the original CGImage we already have
        let handler = VNImageRequestHandler(cgImage: cgImageForVision, options: [:])
        
        do {
            // CRITICAL: Add SIGNIFICANT delay before Vision operation to prevent QoS tracking overload
            // Vision framework internally uses CIContext and triggers QoS tracking, so we need MUCH longer delays
            // libRPAC.dylib crashes happen when QoS hash table gets overwhelmed with rapid Vision operations
            // Increased to 500ms to give system plenty of time to process QoS updates
            Thread.sleep(forTimeInterval: 0.50) // 500ms delay before Vision to prevent libRPAC.dylib crashes
            
            // Perform Vision operation with error handling
            try handler.perform([faceDetectionRequest])
            
            // CRITICAL: Add delay AFTER Vision operation completes to let QoS tracking settle
            // The Vision operation triggers QoS tracking, so we need to wait for it to complete
            Thread.sleep(forTimeInterval: 0.30) // 300ms delay after Vision to let QoS tracking complete
        } catch {
            print("SkipSlate: Face detection error: \(error)")
            // Detect landscape shot (no faces detected due to error)
            let isLandscapeShot = detectLandscapeShot(ciImage: ciImage, videoSize: videoSize)
            // Calculate quality score without faces
            let qualityScore = calculateQualityScore(
                hasFace: false,
                framingScore: 0.0,
                lightingScore: lightingScore,
                motionScore: motionScore,
                isStable: isStable
            )
            return FrameAnalysis(
                timestamp: timestamp,
                hasFace: false,
                faceCount: 0,
                primaryFaceCentered: false,
                faceBounds: nil,
                framingScore: 0.0,
                shotQualityScore: qualityScore,
                isStable: isStable,
                hasGoodLighting: hasGoodLighting,
                hasMotion: hasMotion,
                isLandscapeShot: isLandscapeShot
            )
        }
        
        guard let observations = faceDetectionRequest.results as? [VNFaceObservation],
              !observations.isEmpty else {
            // No faces detected - check if this is a landscape shot
            let isLandscapeShot = detectLandscapeShot(ciImage: ciImage, videoSize: videoSize)
            // Calculate quality score without faces
            let qualityScore = calculateQualityScore(
                hasFace: false,
                framingScore: 0.0,
                lightingScore: lightingScore,
                motionScore: motionScore,
                isStable: isStable
            )
            return FrameAnalysis(
                timestamp: timestamp,
                hasFace: false,
                faceCount: 0,
                primaryFaceCentered: false,
                faceBounds: nil,
                framingScore: 0.0,
                shotQualityScore: qualityScore,
                isStable: isStable,
                hasGoodLighting: hasGoodLighting,
                hasMotion: hasMotion,
                isLandscapeShot: isLandscapeShot
            )
        }
        
        // Find the largest face (likely the primary subject)
        let primaryFace = observations.max { face1, face2 in
            let area1 = face1.boundingBox.width * face1.boundingBox.height
            let area2 = face2.boundingBox.width * face2.boundingBox.height
            return area1 < area2
        }
        
        guard let face = primaryFace else {
            // Calculate quality score without primary face
            let qualityScore = calculateQualityScore(
                hasFace: true,
                framingScore: 0.3,
                lightingScore: lightingScore,
                motionScore: motionScore,
                isStable: isStable
            )
            return FrameAnalysis(
                timestamp: timestamp,
                hasFace: true,
                faceCount: observations.count,
                primaryFaceCentered: false,
                faceBounds: nil,
                framingScore: 0.3, // Low score if faces detected but can't determine primary
                shotQualityScore: qualityScore,
                isStable: isStable,
                hasGoodLighting: hasGoodLighting,
                hasMotion: hasMotion,
                isLandscapeShot: false // Has faces, so not a landscape shot
            )
        }
        
        // Check if face is well-centered (more lenient thresholds)
        // Face should be in center 70% of frame (15% margin on each side) - more lenient
        let faceCenterX = face.boundingBox.midX
        let faceCenterY = face.boundingBox.midY
        
        let isCenteredX = faceCenterX >= 0.15 && faceCenterX <= 0.85
        let isCenteredY = faceCenterY >= 0.15 && faceCenterY <= 0.85
        
        // Check if face is large enough (not too small, not cut off) - more lenient
        let faceArea = face.boundingBox.width * face.boundingBox.height
        let isGoodSize = faceArea >= 0.03 && faceArea <= 0.5 // Between 3% and 50% of frame (more lenient)
        
        // Check if face is cut off at edges - allow small cutoffs
        let margin: CGFloat = 0.05 // Allow 5% margin for edge cutoffs
        let isNotCutOff = face.boundingBox.minX >= -margin &&
                         face.boundingBox.minY >= -margin &&
                         face.boundingBox.maxX <= 1.0 + margin &&
                         face.boundingBox.maxY <= 1.0 + margin
        
        let primaryFaceCentered = isCenteredX && isCenteredY && isGoodSize && isNotCutOff
        
        // Calculate framing score (0-1)
        var framingScore: Float = 0.5 // Base score for having a face
        
        if isCenteredX { framingScore += 0.15 }
        if isCenteredY { framingScore += 0.15 }
        if isGoodSize { framingScore += 0.1 }
        if isNotCutOff { framingScore += 0.1 }
        
        framingScore = min(framingScore, 1.0)
        
        // Calculate overall quality score
        let qualityScore = calculateQualityScore(
            hasFace: true,
            framingScore: framingScore,
            lightingScore: lightingScore,
            motionScore: motionScore,
            isStable: isStable
        )
        
        return FrameAnalysis(
            timestamp: timestamp,
            hasFace: true,
            faceCount: observations.count,
            primaryFaceCentered: primaryFaceCentered,
            faceBounds: face.boundingBox,
            framingScore: framingScore,
            shotQualityScore: qualityScore,
            isStable: isStable,
            hasGoodLighting: hasGoodLighting,
            hasMotion: hasMotion,
            isLandscapeShot: false // Has faces, so not a landscape shot
        )
    }
    
    /// Detect if a shot is a landscape/scenic shot (wide framing, no faces, good composition)
    /// CRITICAL: Must be called from ciQueue
    private func detectLandscapeShot(ciImage: CIImage, videoSize: CGSize) -> Bool {
        // Landscape shots have:
        // 1. Wide aspect ratio (16:9 or wider)
        // 2. No faces (already checked before calling this)
        // 3. Good depth of field (background in focus, not close-up)
        // 4. Good lighting
        // 5. Wide framing (not close-up of body parts like feet)
        // 6. Color variation (scenic shots have more variation than close-ups)
        
        let aspectRatio = videoSize.width / videoSize.height
        let isWideFormat = aspectRatio >= 1.5 // 16:9 or wider
        
        guard isWideFormat else {
            return false // Not wide enough to be a landscape shot
        }
        
        // Check color variation - landscape shots typically have more color diversity
        // Close-ups of feet/body parts tend to have less color variation
        return autoreleasepool {
            // Sample pixels across the image to check for color variation
            // Landscape shots have more variation in color across the frame
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: ciImage.extent
            ]),
            let outputImage = filter.outputImage else {
                return false
            }
            
            let extent = outputImage.extent
            guard !extent.isInfinite && !extent.isNull && extent.width > 0 && extent.height > 0 else {
                return false
            }
            
            // For now, use a simple heuristic: wide format + reasonable extent = likely landscape
            // More sophisticated: could analyze color histogram or edge distribution
            // Landscape shots typically have the full frame in view (not cropped/zoomed)
            let frameArea = ciImage.extent.width * ciImage.extent.height
            let videoArea = videoSize.width * videoSize.height
            let coverageRatio = frameArea / (videoArea > 0 ? videoArea : 1.0)
            
            // Landscape shots typically show most/all of the frame (coverage > 0.8)
            // Close-ups of body parts would have lower coverage
            return coverageRatio > 0.7 && isWideFormat
        }
    }
    
    // MARK: - Quality Analysis Helpers
    
    /// Analyze lighting quality (brightness, contrast, exposure)
    /// CRITICAL: This must be called from ciQueue - CIContext is not thread-safe
    private func analyzeLighting(ciImage: CIImage) -> (hasGoodLighting: Bool, score: Float) {
        // Get average brightness using Core Image
        // CRITICAL: All CIContext operations must be on the serial queue
        // CRITICAL: Wrap in autoreleasepool to manage memory and prevent crashes
        return autoreleasepool {
            // Use shared CIContext to avoid Metal cache conflicts
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: ciImage.extent
            ]),
            let outputImage = filter.outputImage else {
                return (false, 0.5)
            }
            
            // CRITICAL: Create a fresh CIContext for this operation to avoid shared state corruption
            // Each operation gets its own context to prevent memory corruption crashes
            // CRITICAL: Add delay before context creation to prevent QoS tracking overload
            Thread.sleep(forTimeInterval: 0.10) // 100ms delay before creating context for lighting analysis
            let context = createCIContext()
            
            // CRITICAL: Keep strong reference to outputImage and extent to prevent deallocation
            let extent = outputImage.extent
            guard !extent.isInfinite && !extent.isNull && extent.width > 0 && extent.height > 0 else {
                print("SkipSlate: Invalid outputImage extent in lighting analysis: \(extent)")
                return (false, 0.5)
            }
            
            // CRITICAL: Safety checks before createCGImage to prevent crashes
            // Validate extent dimensions to prevent invalid memory access
            guard extent.width > 0 && extent.height > 0,
                  extent.width < 10000 && extent.height < 10000,
                  !extent.isInfinite && !extent.isNull else {
                print("SkipSlate: Invalid extent for CGImage creation: \(extent)")
                return (false, 0.5)
            }
            
            // CRITICAL: createCGImage can crash if CIContext is invalid or Metal resources are corrupted
            // Use optional binding and validate the result
            // Each operation uses a fresh context to prevent memory corruption
            // CRITICAL: Add delay before createCGImage to prevent QoS tracking overload
            Thread.sleep(forTimeInterval: 0.10) // 100ms delay before createCGImage to prevent crashes
            guard let cgImage = context.createCGImage(outputImage, from: extent) else {
                print("SkipSlate: Failed to create CGImage in lighting analysis")
                return (false, 0.5)
            }
            
            // Additional safety: validate created CGImage
            guard cgImage.width > 0 && cgImage.height > 0 else {
                print("SkipSlate: Created CGImage has invalid dimensions: \(cgImage.width)x\(cgImage.height)")
                return (false, 0.5)
            }
            
            // CRITICAL: Keep strong reference to cgImage while processing
            // Read pixel data to get average brightness
            let width = cgImage.width
            let height = cgImage.height
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitsPerComponent = 8
            
            // Safety check for valid dimensions
            guard width > 0 && height > 0 else {
                print("SkipSlate: Invalid image dimensions: \(width)x\(height)")
                return (false, 0.5)
            }
            
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
            guard let context2 = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                print("SkipSlate: Failed to create CGContext for lighting analysis")
                return (false, 0.5)
            }
            
            context2.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Calculate average brightness (luminance)
            var totalBrightness: Float = 0
            var pixelCount = 0
            
            // Safety check: ensure we don't go out of bounds
            let maxIndex = pixelData.count - bytesPerPixel
            for i in stride(from: 0, through: maxIndex, by: bytesPerPixel) {
                guard i + 2 < pixelData.count else { break }
                let r = Float(pixelData[i]) / 255.0
                let g = Float(pixelData[i + 1]) / 255.0
                let b = Float(pixelData[i + 2]) / 255.0
                // Luminance formula
                let brightness = 0.299 * r + 0.587 * g + 0.114 * b
                totalBrightness += brightness
                pixelCount += 1
            }
            
            guard pixelCount > 0 else {
                print("SkipSlate: No pixels processed in lighting analysis")
                return (false, 0.5)
            }
            
            let avgBrightness = totalBrightness / Float(pixelCount)
            
            // Good lighting: brightness between 0.3 and 0.8 (not too dark, not overexposed)
            let hasGoodLighting = avgBrightness >= 0.3 && avgBrightness <= 0.8
            
            // Score: higher for values closer to 0.5 (optimal)
            let score = 1.0 - abs(avgBrightness - 0.5) * 2.0
            let clampedScore = max(0.0, min(1.0, score))
            
            return (hasGoodLighting, clampedScore)
        }
    }
    
    /// Analyze motion/action in the frame
    /// CRITICAL: This must be synchronous - autoreleasepool doesn't work with async
    private func analyzeMotion(ciImage: CIImage, timestamp: Double) -> (hasMotion: Bool, score: Float) {
        // For now, use edge detection as a proxy for interesting content/motion
        // More edges = more detail/action
        // CRITICAL: Perform all Core Image operations synchronously within autoreleasepool
        return autoreleasepool {
            guard let filter = CIFilter(name: "CIEdges", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputIntensityKey: 1.0
            ]),
            let edgeImage = filter.outputImage else {
                return (false, 0.5)
            }
            
            // CRITICAL: Create a fresh CIContext for this operation to avoid shared state corruption
            // Each operation gets its own context to prevent memory corruption crashes
            // CRITICAL: Add delay before context creation to prevent QoS tracking overload
            Thread.sleep(forTimeInterval: 0.10) // 100ms delay before creating context for motion analysis
            let context = createCIContext()
            
            // CRITICAL: Keep strong reference to edgeImage and extent to prevent deallocation
            let extent = edgeImage.extent
            guard !extent.isInfinite && !extent.isNull && extent.width > 0 && extent.height > 0 else {
                print("SkipSlate: Invalid edgeImage extent in motion analysis: \(extent)")
                return (false, 0.5)
            }
            
            // CRITICAL: Safety checks before createCGImage to prevent crashes
            // Validate extent dimensions to prevent invalid memory access
            guard extent.width > 0 && extent.height > 0,
                  extent.width < 10000 && extent.height < 10000,
                  !extent.isInfinite && !extent.isNull else {
                print("SkipSlate: Invalid extent for CGImage creation in motion: \(extent)")
                return (false, 0.5)
            }
            
            // CRITICAL: createCGImage can crash if CIContext is invalid or Metal resources are corrupted
            // Use optional binding and validate the result
            // Each operation uses a fresh context to prevent memory corruption
            // CRITICAL: Add delay before createCGImage to prevent QoS tracking overload
            Thread.sleep(forTimeInterval: 0.10) // 100ms delay before createCGImage to prevent crashes
            guard let cgImage = context.createCGImage(edgeImage, from: extent) else {
                print("SkipSlate: Failed to create CGImage in motion analysis")
                return (false, 0.5)
            }
            
            // Additional safety: validate created CGImage
            guard cgImage.width > 0 && cgImage.height > 0 else {
                print("SkipSlate: Created CGImage has invalid dimensions in motion: \(cgImage.width)x\(cgImage.height)")
                return (false, 0.5)
            }
            
            // CRITICAL: Keep strong reference to cgImage while processing
            // Read pixel data synchronously - this must complete before autoreleasepool exits
            let width = cgImage.width
            let height = cgImage.height
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bytesPerPixel = 1
            let bytesPerRow = bytesPerPixel * width
            let bitsPerComponent = 8
            
            // Safety check for valid dimensions
            guard width > 0 && height > 0 else {
                print("SkipSlate: Invalid image dimensions for motion: \(width)x\(height)")
                return (false, 0.5)
            }
            
            var pixelData = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                print("SkipSlate: Failed to create CGContext for motion analysis")
                return (false, 0.5)
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Count edge pixels (non-black pixels indicate edges)
            var edgePixelCount = 0
            let threshold: UInt8 = 50 // Threshold for "edge" pixels
            
            for pixel in pixelData {
                if pixel > threshold {
                    edgePixelCount += 1
                }
            }
            
            guard !pixelData.isEmpty else {
                print("SkipSlate: Empty pixel data in motion analysis")
                return (false, 0.5)
            }
            
            let edgeRatio = Float(edgePixelCount) / Float(pixelData.count)
            
            // Good motion/action: moderate edge density (0.1 to 0.4)
            // Too low = static/boring, too high = chaotic/noisy
            let hasMotion = edgeRatio >= 0.1 && edgeRatio <= 0.4
            
            // Score: peak at 0.25 (optimal edge density)
            let optimalRatio: Float = 0.25
            let score = 1.0 - abs(edgeRatio - optimalRatio) * 2.0
            let clampedScore = max(0.0, min(1.0, score))
            
            // Return result - all Core Image work is done, memory can be released
            return (hasMotion, clampedScore)
        }
    }
    
    /// Calculate overall shot quality score from multiple factors
    private func calculateQualityScore(
        hasFace: Bool,
        framingScore: Float,
        lightingScore: Float,
        motionScore: Float,
        isStable: Bool
    ) -> Float {
        var score: Float = 0.0
        
        // Face/framing is most important (40%)
        if hasFace {
            score += framingScore * 0.4
        } else {
            // Even without faces, can have good shots (landscape, B-roll)
            // But penalize heavily if no faces AND poor lighting (likely behind-the-scenes)
            if lightingScore < 0.3 {
                score += 0.05 // Very low score for dark, no-face shots (likely BTS)
            } else {
                score += 0.2 // Base score for non-face content with good lighting
            }
        }
        
        // Lighting is important (30%) - penalize dark/underexposed shots more
        if lightingScore < 0.2 {
            score += lightingScore * 0.15 // Heavily penalize very dark shots
        } else {
            score += lightingScore * 0.3
        }
        
        // Motion/action adds interest (20%)
        // But too much motion might indicate shaky/handheld BTS footage
        if motionScore > 0.8 && !isStable {
            score += motionScore * 0.1 // Reduce score for excessive shaky motion
        } else {
            score += motionScore * 0.2
        }
        
        // Stability matters (10%) - unstable shots are likely BTS
        if !isStable {
            score += 0.02 // Very low score for unstable shots
        } else {
            score += 0.1
        }
        
        // Additional penalty for behind-the-scenes indicators:
        // - Very dark AND no faces AND unstable = likely BTS
        if lightingScore < 0.25 && !hasFace && !isStable {
            score *= 0.3 // Heavy penalty for BTS characteristics
        }
        
        return min(score, 1.0)
    }
    
    /// Find time ranges where faces are well-framed
    func findWellFramedRanges(
        analyses: [FrameAnalysis],
        minFramingScore: Float = 0.6,
        minDuration: Double = 1.0
    ) -> [CMTimeRange] {
        var ranges: [CMTimeRange] = []
        var currentRangeStart: Double?
        
        for analysis in analyses {
            if analysis.framingScore >= minFramingScore && analysis.primaryFaceCentered {
                if currentRangeStart == nil {
                    currentRangeStart = analysis.timestamp
                }
            } else {
                if let start = currentRangeStart {
                    let duration = analysis.timestamp - start
                    if duration >= minDuration {
                        ranges.append(CMTimeRange(
                            start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: duration, preferredTimescale: 600)
                        ))
                    }
                    currentRangeStart = nil
                }
            }
        }
        
        // Close final range if still open
        if let start = currentRangeStart, let lastAnalysis = analyses.last {
            let duration = lastAnalysis.timestamp - start
            if duration >= minDuration {
                ranges.append(CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: duration, preferredTimescale: 600)
                ))
            }
        }
        
        return ranges
    }
    
    /// Find time ranges with high-quality shots (based on overall quality score)
    func findHighQualityRanges(
        analyses: [FrameAnalysis],
        minQualityScore: Float = 0.5,
        minDuration: Double = 0.5
    ) -> [CMTimeRange] {
        var ranges: [CMTimeRange] = []
        var currentRangeStart: Double?
        
        for analysis in analyses {
            if analysis.shotQualityScore >= minQualityScore {
                if currentRangeStart == nil {
                    currentRangeStart = analysis.timestamp
                }
            } else {
                if let start = currentRangeStart {
                    let duration = analysis.timestamp - start
                    if duration >= minDuration {
                        ranges.append(CMTimeRange(
                            start: CMTime(seconds: start, preferredTimescale: 600),
                            duration: CMTime(seconds: duration, preferredTimescale: 600)
                        ))
                    }
                    currentRangeStart = nil
                }
            }
        }
        
        // Close final range if still open
        if let start = currentRangeStart, let lastAnalysis = analyses.last {
            let duration = lastAnalysis.timestamp - start
            if duration >= minDuration {
                ranges.append(CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: duration, preferredTimescale: 600)
                ))
            }
        }
        
        return ranges
    }
    
    /// Score a time range based on shot quality
    func scoreTimeRange(
        start: Double,
        end: Double,
        analyses: [FrameAnalysis]
    ) -> Float {
        let rangeAnalyses = analyses.filter { analysis in
            analysis.timestamp >= start && analysis.timestamp <= end
        }
        
        guard !rangeAnalyses.isEmpty else { return 0.0 }
        
        // Average quality score for this range
        let avgScore = rangeAnalyses.map { $0.shotQualityScore }.reduce(0, +) / Float(rangeAnalyses.count)
        
        // Bonus for consistency (low variance = stable quality)
        let scores = rangeAnalyses.map { $0.shotQualityScore }
        let variance = calculateVariance(scores)
        let consistencyBonus = (1.0 - min(variance, 0.3)) * 0.1 // Up to 10% bonus
        
        return min(avgScore + consistencyBonus, 1.0)
    }
    
    private func calculateVariance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0.0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }
}

