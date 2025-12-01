//
//  HighlightReelSettings.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation

/// Settings specific to Highlight Reel auto-edit mode
struct HighlightReelSettings {
    var targetDuration: CMTime
    var pace: HighlightPace
    var style: HighlightStyle
    var motionIntensity: CGFloat      // 0.0–1.0, for zoom/pan strength
    var transitionIntensity: CGFloat  // 0.0–1.0, for how often to use fancy transitions
    
    static func `default`(targetDuration: CMTime) -> HighlightReelSettings {
        HighlightReelSettings(
            targetDuration: targetDuration,
            pace: .normal,
            style: .montage,
            motionIntensity: 0.6,
            transitionIntensity: 0.5
        )
    }
}

enum HighlightPace {
    case relaxed
    case normal
    case tight
    
    var averageSegmentDuration: ClosedRange<Double> {
        switch self {
        case .relaxed: return 2.0...3.5
        case .normal: return 1.0...2.0
        case .tight: return 0.5...1.2
        }
    }
    
    var minSegmentDuration: Double {
        switch self {
        case .relaxed: return 2.0
        case .normal: return 1.0
        case .tight: return 0.5
        }
    }
    
    var maxSegmentDuration: Double {
        switch self {
        case .relaxed: return 4.0
        case .normal: return 2.5
        case .tight: return 1.5
        }
    }
    
    var photoBaseDuration: ClosedRange<Double> {
        switch self {
        case .relaxed: return 2.0...3.0
        case .normal: return 1.2...2.0
        case .tight: return 0.7...1.5
        }
    }
}

enum HighlightStyle {
    case montage      // Lots of variety, quick, fun
    case hero         // More focused, cinematic, slower cuts, longer hero shots
    case recap        // Chronological, smoother transitions
}

/// Motion transform for Ken Burns effect and video camera moves
struct MotionTransform {
    let startScale: CGFloat    // e.g. 1.0
    let endScale: CGFloat      // e.g. 1.1
    let startOffset: CGPoint   // normalized -0.5..0.5
    let endOffset: CGPoint
}

/// Video moment analysis result
struct VideoMoment {
    let clipID: UUID
    let sourceStart: CMTime
    let duration: CMTime
    let hasFaces: Bool
    let motionLevel: CGFloat // 0–1
    let score: CGFloat       // 0–1
    let shotType: ShotType   // .wide, .medium, .close
}

/// Photo moment analysis result
struct PhotoMoment {
    let clipID: UUID
    let duration: CMTime     // recommended base duration
    let hasFaces: Bool
    let score: CGFloat
    let subjectRect: CGRect  // normalized 0–1 coords
}

enum ShotType {
    case master  // Very wide, establishing shot (no faces or very small faces, wide field of view)
    case wide    // Wide shot (small faces, 0.05-0.08 area)
    case medium  // Medium shot (medium faces, 0.08-0.15 area)
    case close   // Close-up (large faces, >0.15 area)
    
    /// Determine shot type from face area and other visual cues
    static func from(faceArea: CGFloat?, hasFaces: Bool, motionLevel: CGFloat) -> ShotType {
        guard let area = faceArea, hasFaces else {
            // No faces or very low motion = likely master/establishing shot
            return motionLevel < 0.2 ? .master : .wide
        }
        
        if area < 0.03 {
            // Very small faces = master shot
            return .master
        } else if area < 0.08 {
            // Small faces = wide shot
            return .wide
        } else if area < 0.15 {
            // Medium faces = medium shot
            return .medium
        } else {
            // Large faces = close-up
            return .close
        }
    }
}

/// Highlight segment candidate before final selection
struct HighlightSegmentCandidate {
    let clipID: UUID
    let type: SegmentMediaType  // .video, .image
    let sourceStart: CMTime
    let duration: CMTime
    let hasFaces: Bool
    let motionLevel: CGFloat
    let shotType: ShotType?
    let score: CGFloat
    let suggestedBeatIndex: Int
    let motionTransform: MotionTransform?
}

enum SegmentMediaType {
    case video
    case image
}

/// Story phase for highlight reel structure
enum StoryPhase {
    case intro    // ~15% of duration
    case build    // ~40% of duration
    case climax   // ~30% of duration
    case outro    // ~15% of duration
}

/// Music analysis result for highlight reel
struct MusicAnalysis {
    let beatTimes: [CMTime]
    let sectionBoundaries: [CMTime]
    let energyCurve: [EnergySample]
    let duration: CMTime
    let climaxZone: CMTimeRange?  // Highest energy section
    let introZone: CMTimeRange?   // Low energy intro section
}

struct EnergySample {
    let time: CMTime
    let energy: Float  // 0-1 normalized
}

