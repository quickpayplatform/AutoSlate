//
//  CinematicSegmentSelector.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation
import AVFoundation

/// Scored candidate segment with cinematic score
struct ScoredSegment {
    let segment: Segment
    let score: CinematicScore
    let clipID: UUID
    let timeRange: CMTimeRange
}

/// Selects segments with diversity and repetition constraints
class CinematicSegmentSelector {
    struct Config {
        static let maxSegmentsPerClip: Int = 3
        static let minTimeSeparation: Double = 2.0  // Minimum seconds between shots from same clip
        static let overlapThreshold: Double = 0.8   // 80% overlap = duplicate
    }
    
    /// Select final segments with diversity constraints
    func selectSegments(
        from scoredCandidates: [ScoredSegment],
        maxTotalSegments: Int? = nil,
        progressCallback: ((String) -> Void)? = nil
    ) -> [Segment] {
        progressCallback?("Filtering \(scoredCandidates.count) candidate segments...")
        
        // 1. Filter out rejected segments
        let nonRejected = scoredCandidates.filter { !$0.score.isRejected }
        
        let rejectedCount = scoredCandidates.count - nonRejected.count
        if rejectedCount > 0 {
            print("SkipSlate: CinematicSelector - Rejected \(rejectedCount) segments:")
            for candidate in scoredCandidates where candidate.score.isRejected {
                print("SkipSlate:   - Clip \(candidate.clipID), \(candidate.segment.sourceStart)-\(candidate.segment.sourceEnd)s: \(candidate.score.rejectionReason ?? "Unknown")")
            }
        }
        
        progressCallback?("\(nonRejected.count) segments passed quality filters")
        
        // 2. Sort by overall score (descending)
        let sorted = nonRejected.sorted { $0.score.overall > $1.score.overall }
        
        // 3. Apply diversity and repetition constraints
        var selected: [Segment] = []
        var segmentsPerClip: [UUID: Int] = [:]
        var usedTimeRanges: [UUID: [CMTimeRange]] = [:]
        
        for candidate in sorted {
            // Check if we've hit the global limit
            if let maxTotal = maxTotalSegments, selected.count >= maxTotal {
                break
            }
            
            // Check clip limit
            let currentCount = segmentsPerClip[candidate.clipID] ?? 0
            if currentCount >= Config.maxSegmentsPerClip {
                print("SkipSlate: CinematicSelector - Skipping segment from clip \(candidate.clipID) (already have \(currentCount) segments)")
                continue
            }
            
            // Check for overlap/duplicate
            if let existingRanges = usedTimeRanges[candidate.clipID] {
                let isDuplicate = existingRanges.contains { existingRange in
                    let overlap = candidate.timeRange.intersection(existingRange)
                    let overlapRatio = overlap.duration.seconds / candidate.timeRange.duration.seconds
                    return overlapRatio > Config.overlapThreshold
                }
                
                if isDuplicate {
                    print("SkipSlate: CinematicSelector - Skipping duplicate segment from clip \(candidate.clipID) (overlaps with existing)")
                    continue
                }
                
                // Check minimum time separation
                let isTooClose = existingRanges.contains { existingRange in
                    let distance = abs(CMTimeSubtract(candidate.timeRange.start, existingRange.start).seconds)
                    return distance < Config.minTimeSeparation
                }
                
                if isTooClose {
                    print("SkipSlate: CinematicSelector - Skipping segment from clip \(candidate.clipID) (too close to existing segment)")
                    continue
                }
            }
            
            // Accept this segment
            selected.append(candidate.segment)
            segmentsPerClip[candidate.clipID, default: 0] += 1
            usedTimeRanges[candidate.clipID, default: []].append(candidate.timeRange)
            
            print("SkipSlate: CinematicSelector - Selected segment from clip \(candidate.clipID) (score: \(String(format: "%.2f", candidate.score.overall)), face: \(String(format: "%.2f", candidate.score.faceScore)), composition: \(String(format: "%.2f", candidate.score.compositionScore)))")
        }
        
        // Log final selection
        print("SkipSlate: CinematicSelector - Final selection: \(selected.count) segments from \(segmentsPerClip.count) clips")
        for (clipID, count) in segmentsPerClip {
            print("SkipSlate:   - Clip \(clipID): \(count) segment(s)")
        }
        
        progressCallback?("Selected \(selected.count) cinematic segments from \(segmentsPerClip.count) clips")
        
        return selected
    }
}


