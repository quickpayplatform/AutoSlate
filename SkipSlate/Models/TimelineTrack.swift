//
//  TimelineTrack.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct TimelineTrack: Identifiable, Hashable, Codable {
    enum TrackType: String, Codable {
        case videoPrimary      // main story track
        case videoOverlay      // overlays / B-roll / green screen
        case audio             // music / VO
    }
    
    let id: UUID
    var type: TrackType
    var name: String
    var segments: [Segment.ID]  // References to segments by ID
    
    init(id: UUID = UUID(), type: TrackType, name: String, segments: [Segment.ID] = []) {
        self.id = id
        self.type = type
        self.name = name
        self.segments = segments
    }
}


