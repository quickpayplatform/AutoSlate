//
//  TimelineTrack.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation

/// Kind of track (video or audio)
enum TrackKind: String, Codable {
    case video
    case audio
}

struct TimelineTrack: Identifiable, Hashable, Codable {
    // Legacy TrackType for backward compatibility
    enum TrackType: String, Codable {
        case videoPrimary      // main story track
        case videoOverlay      // overlays / B-roll / green screen
        case audio             // music / VO
    }
    
    let id: UUID
    var kind: TrackKind        // New: video or audio
    var index: Int             // 0-based index within its kind (V0, V1, A0, A1, etc.)
    var segments: [Segment.ID]  // References to segments by ID
    var isMuted: Bool = false  // Used for audio, safe to keep for video too
    var isLocked: Bool = false
    
    // Legacy properties for backward compatibility
    var type: TrackType {
        get {
            switch kind {
            case .video:
                return index == 0 ? .videoPrimary : .videoOverlay
            case .audio:
                return .audio
            }
        }
        set {
            switch newValue {
            case .videoPrimary:
                kind = .video
                index = 0
            case .videoOverlay:
                kind = .video
                index = max(1, index) // Preserve index if >= 1, otherwise set to 1
            case .audio:
                kind = .audio
            }
        }
    }
    
    var name: String {
        get {
            switch kind {
            case .video:
                return "V\(index + 1)"
            case .audio:
                return "A\(index + 1)"
            }
        }
        set {
            // Parse name to extract kind and index if needed
            // For now, just store it (backward compatibility)
        }
    }
    
    init(id: UUID = UUID(), kind: TrackKind, index: Int, segments: [Segment.ID] = [], isMuted: Bool = false, isLocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.index = index
        self.segments = segments
        self.isMuted = isMuted
        self.isLocked = isLocked
    }
    
    // Legacy initializer for backward compatibility
    init(id: UUID = UUID(), type: TrackType, name: String, segments: [Segment.ID] = []) {
        self.id = id
        switch type {
        case .videoPrimary:
            self.kind = .video
            self.index = 0
        case .videoOverlay:
            self.kind = .video
            // Try to parse index from name (e.g., "V2" -> index 1)
            if name.hasPrefix("V"), let num = Int(name.dropFirst()) {
                self.index = max(1, num - 1)
            } else {
                self.index = 1
            }
        case .audio:
            self.kind = .audio
            // Try to parse index from name (e.g., "A1" -> index 0)
            if name.hasPrefix("A"), let num = Int(name.dropFirst()) {
                self.index = max(0, num - 1)
            } else {
                self.index = 0
            }
        }
        self.segments = segments
        self.isMuted = false
        self.isLocked = false
    }
}


