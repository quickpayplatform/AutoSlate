//
//  Project.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct Project {
    var id: UUID
    var name: String
    var type: ProjectType
    var aspectRatio: AspectRatio
    var resolution: ResolutionPreset
    var clips: [MediaClip]
    var segments: [Segment]
    var tracks: [TimelineTrack]  // Multi-track timeline
    var audioSettings: AudioSettings
    var colorSettings: ColorSettings
    var autoEditSettings: AutoEditSettings?
    var letterboxSettings: LetterboxSettings = .default
    
    init(
        id: UUID = UUID(),
        name: String,
        type: ProjectType,
        aspectRatio: AspectRatio,
        resolution: ResolutionPreset,
        clips: [MediaClip] = [],
        segments: [Segment] = [],
        tracks: [TimelineTrack]? = nil,
        audioSettings: AudioSettings = .default,
        colorSettings: ColorSettings = .default,
        autoEditSettings: AutoEditSettings? = nil,
        letterboxSettings: LetterboxSettings = .default
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.clips = clips
        self.segments = segments
        
        // Initialize tracks if not provided - create default tracks
        if let tracks = tracks {
            self.tracks = tracks
        } else {
            // CRITICAL: Create exactly one video track (V1) and one audio track (A1)
            // Auto-edit will use V1 only. Users can add V2, V3, etc. manually for overlays.
            self.tracks = [
                TimelineTrack(kind: .video, index: 0, segments: []),  // V1 - base video track
                TimelineTrack(kind: .audio, index: 0, segments: [])   // A1 - audio track
            ]
        }
        
        self.audioSettings = audioSettings
        self.colorSettings = colorSettings
        self.autoEditSettings = autoEditSettings
        self.letterboxSettings = letterboxSettings
    }
}

// MARK: - Letterbox Settings

enum LetterboxMode: String, Codable, CaseIterable {
    case none           // No letterbox
    case alwaysOn       // Static letterbox bars (always visible)
    case fadeIn         // Letterbox fades in from top at start
    case fadeOut        // Letterbox fades out to black at end
    
    var displayLabel: String {
        switch self {
        case .none: return "None"
        case .alwaysOn: return "Always On"
        case .fadeIn: return "Fade In"
        case .fadeOut: return "Fade Out"
        }
    }
}

struct LetterboxSettings: Codable, Equatable {
    var mode: LetterboxMode = .none
    var height: Double = 0.15  // Height of letterbox bars (0.0-0.5, as fraction of screen height)
    var fadeDuration: Double = 2.0  // Duration of fade in/out animation (seconds)
    
    static let `default` = LetterboxSettings()
}

