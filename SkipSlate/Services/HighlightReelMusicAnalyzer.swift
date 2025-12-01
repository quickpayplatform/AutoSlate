//
//  HighlightReelMusicAnalyzer.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation
import Accelerate

/// Analyzes music tracks for highlight reel editing (beats, sections, energy)
class HighlightReelMusicAnalyzer {
    static let shared = HighlightReelMusicAnalyzer()
    
    private init() {}
    
    /// Analyze music for highlight reel editing
    func analyzeMusicForHighlightReel(asset: AVAsset) async throws -> MusicAnalysis {
        // Build audio envelope
        let audioEngine = AudioAnalysisEngine()
        let envelope = try await audioEngine.buildEnvelope(for: asset, frameDuration: 0.01) // 10ms for precise beat detection
        
        let duration = try await asset.load(.duration)
        
        // Detect beats using energy peaks
        let beatTimes = detectBeats(envelope: envelope, minBeatSpacing: 0.25, sensitivity: 0.4)
        
        // Detect sections based on energy patterns
        let sectionBoundaries = detectSections(envelope: envelope, duration: duration)
        
        // Build energy curve
        let energyCurve = buildEnergyCurve(envelope: envelope, duration: duration)
        
        // Find climax zone (highest energy section)
        let climaxZone = findClimaxZone(energyCurve: energyCurve, duration: duration)
        
        // Find intro zone (low energy at start)
        let introZone = findIntroZone(energyCurve: energyCurve, duration: duration)
        
        return MusicAnalysis(
            beatTimes: beatTimes,
            sectionBoundaries: sectionBoundaries,
            energyCurve: energyCurve,
            duration: duration,
            climaxZone: climaxZone,
            introZone: introZone
        )
    }
    
    // MARK: - Beat Detection
    
    private func detectBeats(
        envelope: AudioAnalysisEngine.Envelope,
        minBeatSpacing: Double,
        sensitivity: Float
    ) -> [CMTime] {
        guard envelope.rmsValues.count > 10 else { return [] }
        
        // Compute moving average for smoothing
        let windowSize = 5
        var smoothed: [Float] = []
        
        for i in 0..<envelope.rmsValues.count {
            let start = max(0, i - windowSize / 2)
            let end = min(envelope.rmsValues.count, i + windowSize / 2 + 1)
            let window = Array(envelope.rmsValues[start..<end])
            let avg = window.reduce(0, +) / Float(window.count)
            smoothed.append(avg)
        }
        
        // Compute energy deviation (difference from smoothed average)
        var deviations: [Float] = []
        for i in 0..<envelope.rmsValues.count {
            let deviation = envelope.rmsValues[i] - smoothed[i]
            deviations.append(max(0, deviation))
        }
        
        // Normalize deviations
        if let maxDev = deviations.max(), maxDev > 0 {
            let scale = 1.0 / maxDev
            deviations = deviations.map { $0 * scale }
        }
        
        // Find peaks (local maxima above sensitivity threshold)
        var peaks: [Int] = []
        let minFramesSpacing = Int(minBeatSpacing / envelope.frameDuration)
        
        for i in 1..<(deviations.count - 1) {
            if deviations[i] > sensitivity &&
               deviations[i] > deviations[i - 1] &&
               deviations[i] > deviations[i + 1] {
                // Check spacing from last peak
                if peaks.isEmpty || (i - peaks.last!) >= minFramesSpacing {
                    peaks.append(i)
                }
            }
        }
        
        // Convert to CMTime
        return peaks.map { CMTime(seconds: Double($0) * envelope.frameDuration, preferredTimescale: 600) }
    }
    
    // MARK: - Section Detection
    
    private func detectSections(
        envelope: AudioAnalysisEngine.Envelope,
        duration: CMTime
    ) -> [CMTime] {
        // Simple approach: divide into 4-5 sections based on energy changes
        let sampleCount = envelope.rmsValues.count
        guard sampleCount > 0 else { return [] }
        
        // Find energy change points
        var boundaries: [CMTime] = [.zero]
        
        // Look for significant energy changes (potential section boundaries)
        let windowSize = Int(5.0 / envelope.frameDuration) // 5 second windows
        var previousEnergy: Float = 0
        
        for i in stride(from: windowSize, to: sampleCount - windowSize, by: windowSize) {
            let window = Array(envelope.rmsValues[i..<min(i + windowSize, sampleCount)])
            let avgEnergy = window.reduce(0, +) / Float(window.count)
            
            // If energy changes significantly, mark as boundary
            if abs(avgEnergy - previousEnergy) > 0.15 && previousEnergy > 0 {
                let time = CMTime(seconds: Double(i) * envelope.frameDuration, preferredTimescale: 600)
                boundaries.append(time)
            }
            
            previousEnergy = avgEnergy
        }
        
        boundaries.append(duration)
        return boundaries
    }
    
    // MARK: - Energy Curve
    
    private func buildEnergyCurve(
        envelope: AudioAnalysisEngine.Envelope,
        duration: CMTime
    ) -> [EnergySample] {
        // Smooth RMS values for energy curve
        let windowSize = 10
        var smoothed: [Float] = []
        
        for i in 0..<envelope.rmsValues.count {
            let start = max(0, i - windowSize / 2)
            let end = min(envelope.rmsValues.count, i + windowSize / 2 + 1)
            let window = Array(envelope.rmsValues[start..<end])
            let avg = window.reduce(0, +) / Float(window.count)
            smoothed.append(avg)
        }
        
        // Normalize to 0-1
        if let maxEnergy = smoothed.max(), maxEnergy > 0 {
            let scale = 1.0 / maxEnergy
            smoothed = smoothed.map { $0 * scale }
        }
        
        // Sample at regular intervals (every 0.1 seconds)
        var samples: [EnergySample] = []
        let sampleInterval = 0.1
        var currentTime: Double = 0
        
        while currentTime < duration.seconds {
            let frameIndex = Int(currentTime / envelope.frameDuration)
            if frameIndex < smoothed.count {
                let energy = smoothed[frameIndex]
                samples.append(EnergySample(
                    time: CMTime(seconds: currentTime, preferredTimescale: 600),
                    energy: energy
                ))
            }
            currentTime += sampleInterval
        }
        
        return samples
    }
    
    // MARK: - Zone Detection
    
    private func findClimaxZone(
        energyCurve: [EnergySample],
        duration: CMTime
    ) -> CMTimeRange? {
        guard !energyCurve.isEmpty else { return nil }
        
        // Find highest energy window (30% of duration)
        let zoneDuration = duration.seconds * 0.3
        let windowSize = Int(zoneDuration / 0.1) // Assuming 0.1s samples
        
        var maxEnergy: Float = 0
        var maxStartIndex = 0
        
        for i in 0..<(energyCurve.count - windowSize) {
            let window = Array(energyCurve[i..<min(i + windowSize, energyCurve.count)])
            let avgEnergy = window.map { $0.energy }.reduce(0, +) / Float(window.count)
            
            if avgEnergy > maxEnergy {
                maxEnergy = avgEnergy
                maxStartIndex = i
            }
        }
        
        if maxStartIndex < energyCurve.count {
            let start = energyCurve[maxStartIndex].time
            let endTime = min(
                CMTimeAdd(start, CMTime(seconds: zoneDuration, preferredTimescale: 600)),
                duration
            )
            return CMTimeRange(start: start, duration: CMTimeSubtract(endTime, start))
        }
        
        return nil
    }
    
    private func findIntroZone(
        energyCurve: [EnergySample],
        duration: CMTime
    ) -> CMTimeRange? {
        guard !energyCurve.isEmpty else { return nil }
        
        // Find low energy section at start (15% of duration)
        let introDuration = duration.seconds * 0.15
        let windowSize = Int(introDuration / 0.1)
        
        guard windowSize <= energyCurve.count else { return nil }
        
        let introWindow = Array(energyCurve.prefix(windowSize))
        let avgEnergy = introWindow.map { $0.energy }.reduce(0, +) / Float(introWindow.count)
        
        // If intro is low energy (< 0.4), return it
        if avgEnergy < 0.4 {
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: introDuration, preferredTimescale: 600)
            )
        }
        
        return nil
    }
}

