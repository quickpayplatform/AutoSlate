//
//  Segment.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

enum SegmentTransitionType: String, Codable {
    case none
    case crossfade
    case dipToBlack
    case dipToWhite
}

enum CompositionMode: String, Codable {
    case fit
    case fill
    case fitWithLetterbox
}

enum CompositionAnchor: String, Codable {
    case center
    case top
    case bottom
    case left
    case right
}

/// Transform settings for a segment (scale to fill, pan, etc.)
struct SegmentTransform: Codable, Equatable {
    var scaleToFillFrame: Bool = false  // When true, auto-compute scale/offset for full-frame coverage
    
    // Future: pan/scan controls can be added here
}

struct SegmentEffects: Codable {
    var transitionType: SegmentTransitionType = .none
    var transitionDuration: Double = 0.2  // seconds
    
    // Transform
    var scale: Double = 1.0
    var positionX: Double = 0.0
    var positionY: Double = 0.0
    var rotation: Double = 0.0  // degrees
    
    // Crop
    var cropTop: Double = 0.0
    var cropBottom: Double = 0.0
    var cropLeft: Double = 0.0
    var cropRight: Double = 0.0
    
    // Composition
    var compositionMode: CompositionMode = .fit
    var compositionAnchor: CompositionAnchor = .center
}

/// Kind of timeline segment - clip or gap (black screen)
enum SegmentKind: String, Codable {
    case clip      // Actual media clip
    case gap       // Black gap (no media)
}

struct Segment: Identifiable, Codable {
    let id: UUID
    var kind: SegmentKind = .clip  // Default to clip for backward compatibility
    
    // For clip segments: source clip reference
    var sourceClipID: UUID?  // Optional - nil for gap segments
    var sourceStart: Double    // seconds in source clip (only used for clip segments)
    var sourceEnd: Double      // seconds in source clip (only used for clip segments)
    
    var enabled: Bool
    var colorIndex: Int        // index into accent color palette (only used for clip segments)
    var effects: SegmentEffects = SegmentEffects()  // Only used for clip segments
    var transform: SegmentTransform = SegmentTransform()  // Transform settings (scale to fill, etc.)
    
    // Composition timeline position (explicit start time in the final video)
    // This allows gaps - segments don't automatically shift when others are deleted
    var compositionStartTime: Double = 0.0  // seconds in composition timeline
    
    // For gap segments: explicit duration
    // For clip segments: calculated from sourceStart/sourceEnd
    var gapDuration: Double?  // Optional explicit duration for gap segments
    
    var duration: Double {
        if kind == .gap {
            return gapDuration ?? 0.0
        }
        return sourceEnd - sourceStart
    }
    
    var compositionEndTime: Double {
        compositionStartTime + duration
    }
    
    // MARK: - Helper Properties for Safe Access
    
    /// True if this segment is a gap (no media)
    var isGap: Bool {
        kind == .gap
    }
    
    /// True if this segment is a clip (has media)
    var isClip: Bool {
        kind == .clip
    }
    
    /// Returns the source clip ID if this is a clip segment, nil otherwise
    /// Use this instead of accessing sourceClipID directly
    var clipID: UUID? {
        guard kind == .clip else { return nil }
        return sourceClipID
    }
    
    /// Returns the time range for this segment in the composition timeline
    var compositionTimeRange: (start: Double, end: Double) {
        (start: compositionStartTime, end: compositionEndTime)
    }
    
    // Convenience initializer for clip segments
    init(
        id: UUID = UUID(),
        sourceClipID: UUID,
        sourceStart: Double,
        sourceEnd: Double,
        enabled: Bool = true,
        colorIndex: Int = 0,
        effects: SegmentEffects = SegmentEffects(),
        compositionStartTime: Double = 0.0,
        transform: SegmentTransform = SegmentTransform()
    ) {
        self.id = id
        self.kind = .clip
        self.sourceClipID = sourceClipID
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.enabled = enabled
        self.colorIndex = colorIndex
        self.effects = effects
        self.compositionStartTime = compositionStartTime
        self.gapDuration = nil
        self.transform = transform
    }
    
    // Convenience initializer for gap segments
    init(
        id: UUID = UUID(),
        gapDuration: Double,
        compositionStartTime: Double
    ) {
        self.id = id
        self.kind = .gap
        self.sourceClipID = nil
        self.sourceStart = 0.0
        self.sourceEnd = 0.0
        self.enabled = true
        self.colorIndex = 0
        self.effects = SegmentEffects()
        self.compositionStartTime = compositionStartTime
        self.gapDuration = gapDuration
        self.transform = SegmentTransform()  // Gaps don't need transforms, but initialize for consistency
    }
}

