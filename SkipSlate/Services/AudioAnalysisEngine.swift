//
//  AudioAnalysisEngine.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  On-device audio analysis engine using AVFoundation and Accelerate
//

import Foundation
import AVFoundation
import Accelerate

enum AudioAnalysisError: Error {
    case noAudioTrack
    case analysisFailed(String)
}

class AudioAnalysisEngine {
    
    struct Envelope {
        let frameDuration: Double       // seconds per value (e.g., 0.02 = 20ms)
        let rmsValues: [Float]          // RMS per frame
    }
    
    struct SpeechSegment {
        let startTime: Double
        let endTime: Double
    }
    
    // MARK: - Build Amplitude Envelope
    
    func buildEnvelope(
        for asset: AVAsset,
        preferredSampleRate: Double = 44100,
        frameDuration: Double = 0.02
    ) async throws -> Envelope {
        // Get audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioAnalysisError.noAudioTrack
        }
        
        // Configure reader
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: preferredSampleRate,
            AVNumberOfChannelsKey: 1  // Mono
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var allSamples: [Float] = []
        let samplesPerFrame = Int(frameDuration * preferredSampleRate)
        
        // Read audio samples
        while reader.status == .reading {
            if let sampleBuffer = output.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    var length: Int = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    
                    let status = CMBlockBufferGetDataPointer(
                        blockBuffer,
                        atOffset: 0,
                        lengthAtOffsetOut: nil,
                        totalLengthOut: &length,
                        dataPointerOut: &dataPointer
                    )
                    
                    if status == noErr, let data = dataPointer {
                        let sampleCount = length / MemoryLayout<Float>.size
                        let samples = data.withMemoryRebound(to: Float.self, capacity: sampleCount) { ptr in
                            Array(UnsafeBufferPointer(start: ptr, count: sampleCount))
                        }
                        allSamples.append(contentsOf: samples)
                    }
                }
            } else {
                break
            }
        }
        
        // Compute RMS per frame
        var rmsValues: [Float] = []
        var frameIndex = 0
        
        while frameIndex * samplesPerFrame < allSamples.count {
            let start = frameIndex * samplesPerFrame
            let end = min(start + samplesPerFrame, allSamples.count)
            let frameSamples = Array(allSamples[start..<end])
            
            // Compute RMS using vDSP
            var rms: Float = 0
            vDSP_rmsqv(frameSamples, 1, &rms, vDSP_Length(frameSamples.count))
            rmsValues.append(rms)
            
            frameIndex += 1
        }
        
        // Normalize to max 1.0
        if let maxRMS = rmsValues.max(), maxRMS > 0 {
            let scale = 1.0 / maxRMS
            rmsValues = rmsValues.map { $0 * scale }
        }
        
        return Envelope(frameDuration: frameDuration, rmsValues: rmsValues)
    }
    
    // MARK: - Detect Speech Segments
    
    func detectSpeechSegments(
        envelope: Envelope,
        minSpeechDuration: Double,
        minSilenceDuration: Double,
        silenceThresholdDB: Float
    ) -> [SpeechSegment] {
        guard !envelope.rmsValues.isEmpty else { return [] }
        
        // Convert RMS to dB
        let epsilon: Float = 1e-10
        let dbValues = envelope.rmsValues.map { rms in
            20 * log10f(max(rms, epsilon))
        }
        
        // Compute baseline (median of non-silent frames)
        let sortedDB = dbValues.sorted()
        let medianDB = sortedDB[sortedDB.count / 2]
        let baseline = medianDB
        
        // Threshold for silence
        let threshold = baseline + silenceThresholdDB
        
        // Mark frames as speech or silence
        var isSpeech: [Bool] = dbValues.map { $0 >= threshold }
        
        // Find speech segments
        var segments: [SpeechSegment] = []
        var inSpeech = false
        var speechStart: Int = 0
        
        for (index, speech) in isSpeech.enumerated() {
            if speech && !inSpeech {
                // Start of speech
                inSpeech = true
                speechStart = index
            } else if !speech && inSpeech {
                // End of speech - check if silence is long enough
                let silenceStart = index
                var silenceCount = 0
                
                // Count consecutive silence frames
                for i in silenceStart..<isSpeech.count {
                    if !isSpeech[i] {
                        silenceCount += 1
                    } else {
                        break
                    }
                }
                
                let silenceDuration = Double(silenceCount) * envelope.frameDuration
                
                if silenceDuration >= minSilenceDuration {
                    // Close the segment
                    let segmentStart = Double(speechStart) * envelope.frameDuration
                    let segmentEnd = Double(index) * envelope.frameDuration
                    let duration = segmentEnd - segmentStart
                    
                    if duration >= minSpeechDuration {
                        segments.append(SpeechSegment(startTime: segmentStart, endTime: segmentEnd))
                    }
                    
                    inSpeech = false
                }
            }
        }
        
        // Close final segment if still in speech
        if inSpeech {
            let segmentStart = Double(speechStart) * envelope.frameDuration
            let segmentEnd = Double(isSpeech.count) * envelope.frameDuration
            let duration = segmentEnd - segmentStart
            
            if duration >= minSpeechDuration {
                segments.append(SpeechSegment(startTime: segmentStart, endTime: segmentEnd))
            }
        }
        
        // Merge segments with tiny gaps (< 0.25s)
        var merged: [SpeechSegment] = []
        var current: SpeechSegment?
        
        for segment in segments {
            if let prev = current {
                let gap = segment.startTime - prev.endTime
                if gap < 0.25 {
                    // Merge
                    current = SpeechSegment(startTime: prev.startTime, endTime: segment.endTime)
                } else {
                    merged.append(prev)
                    current = segment
                }
            } else {
                current = segment
            }
        }
        
        if let final = current {
            merged.append(final)
        }
        
        return merged
    }
    
    // MARK: - Detect Beat Peaks
    
    func detectBeatPeaks(
        envelope: Envelope,
        minBeatSpacing: Double,
        sensitivity: Float
    ) -> [Double] {
        guard envelope.rmsValues.count > 5 else { return [] }
        
        // Compute moving average (simple smoothing)
        let windowSize = 5
        var smoothed: [Float] = []
        
        for i in 0..<envelope.rmsValues.count {
            let start = max(0, i - windowSize / 2)
            let end = min(envelope.rmsValues.count, i + windowSize / 2 + 1)
            let window = Array(envelope.rmsValues[start..<end])
            let avg = window.reduce(0, +) / Float(window.count)
            smoothed.append(avg)
        }
        
        // Compute energy deviation
        var deviations: [Float] = []
        for i in 0..<envelope.rmsValues.count {
            let deviation = envelope.rmsValues[i] - smoothed[i]
            deviations.append(max(0, deviation))  // Only positive deviations
        }
        
        // Normalize deviations to 0-1
        if let maxDev = deviations.max(), maxDev > 0 {
            let scale = 1.0 / maxDev
            deviations = deviations.map { $0 * scale }
        }
        
        // Find peaks
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
        
        // Convert to times
        return peaks.map { Double($0) * envelope.frameDuration }
    }
}

