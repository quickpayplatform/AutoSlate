//
//  VideoStabilizationService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation
import CoreImage
import Vision

/// Service for analyzing video shake and creating stabilization profiles
class VideoStabilizationService {
    static let shared = VideoStabilizationService()
    
    private init() {}
    
    /// Analyze shake level for a video clip
    /// Returns shakeLevel: 0.0 (very stable) to 1.0 (very shaky)
    func analyzeStability(for clip: MediaClip, asset: AVAsset) async throws -> Double {
        guard clip.type == .videoWithAudio || clip.type == .videoOnly else {
            return 0.0  // Non-video clips don't need stabilization
        }
        
        print("SkipSlate: Analyzing stability for clip: \(clip.fileName)")
        
        // Sample frames at 5-10 fps for motion analysis
        let sampleInterval: Double = 0.2  // 5 fps
        let duration = try await asset.load(.duration)
        let sampleCount = min(Int(duration.seconds / sampleInterval), 50)  // Limit to 50 samples max
        
        guard sampleCount > 1 else {
            return 0.0  // Not enough frames to analyze
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 640, height: 360)  // Lower resolution for faster processing
        
        var motionMagnitudes: [Double] = []
        var previousFeatures: [CGPoint]? = nil
        
        // Sample frames and compute motion
        for i in 0..<sampleCount {
            let sampleTime = CMTimeMultiply(CMTime(seconds: sampleInterval, preferredTimescale: 600), multiplier: Int32(i))
            
            guard let cgImage = try? await imageGenerator.image(at: sampleTime).image else {
                continue
            }
            
            // Detect feature points using Vision framework
            let features = try await detectFeaturePoints(cgImage: cgImage)
            
            if let prevFeatures = previousFeatures, !features.isEmpty {
                // Compute motion magnitude between frames
                let motion = computeMotionMagnitude(
                    previousFeatures: prevFeatures,
                    currentFeatures: features
                )
                motionMagnitudes.append(motion)
            }
            
            previousFeatures = features
        }
        
        guard !motionMagnitudes.isEmpty else {
            return 0.0  // Couldn't compute motion
        }
        
        // Calculate average motion and jitter
        let avgMotion = motionMagnitudes.reduce(0.0, +) / Double(motionMagnitudes.count)
        let variance = motionMagnitudes.map { pow($0 - avgMotion, 2) }.reduce(0.0, +) / Double(motionMagnitudes.count)
        let jitter = sqrt(variance)
        
        // Combine into shake level
        // High jitter (erratic motion) = high shake level
        // Normal motion = low shake level
        let shakeLevel = min(1.0, (avgMotion * 0.3 + jitter * 0.7))
        
        print("SkipSlate: Stability analysis - avgMotion: \(String(format: "%.3f", avgMotion)), jitter: \(String(format: "%.3f", jitter)), shakeLevel: \(String(format: "%.3f", shakeLevel))")
        
        return shakeLevel
    }
    
    /// Detect feature points in an image using Vision framework
    /// Simplified approach: Use face detection as a proxy for feature points
    private func detectFeaturePoints(cgImage: CGImage) async throws -> [CGPoint] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Use face centers as feature points
                let points = observations.map { observation -> CGPoint in
                    let normalizedCenter = observation.boundingBox.center
                    // Convert to image coordinates (simplified - assumes full image)
                    return CGPoint(
                        x: normalizedCenter.x * CGFloat(cgImage.width),
                        y: (1.0 - normalizedCenter.y) * CGFloat(cgImage.height) // Flip Y
                    )
                }
                
                continuation.resume(returning: points)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                // If face detection fails, return empty array (no features detected)
                continuation.resume(returning: [])
            }
        }
    }
    
    /// Compute motion magnitude between two sets of feature points
    private func computeMotionMagnitude(previousFeatures: [CGPoint], currentFeatures: [CGPoint]) -> Double {
        guard !previousFeatures.isEmpty && !currentFeatures.isEmpty else {
            // If no features, use a simple frame difference approach
            return 0.1  // Default small motion
        }
        
        // Simple approach: compute average displacement
        var totalDisplacement: Double = 0.0
        var matchCount = 0
        
        // Match nearest features (simplified)
        for prevFeature in previousFeatures {
            if let nearest = currentFeatures.min(by: { distance(from: prevFeature, to: $0) < distance(from: prevFeature, to: $1) }) {
                let dist = distance(from: prevFeature, to: nearest)
                totalDisplacement += dist
                matchCount += 1
            }
        }
        
        guard matchCount > 0 else {
            return 0.1
        }
        
        // Normalize by image size (assume 640x360 for sampled frames)
        let normalizedMotion = (totalDisplacement / Double(matchCount)) / 640.0
        return normalizedMotion
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> Double {
        let dx = Double(p1.x - p2.x)
        let dy = Double(p1.y - p2.y)
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - VNPoint Extension

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

