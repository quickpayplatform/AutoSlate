//
//  AutoEditSettings.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct AutoEditSettings {
    var targetLengthSeconds: Double?  // nil means "use all content"
    var pace: Pace
    var style: AutoEditStyle
    var removeNoise: Bool
    var normalizeLoudness: Bool
    var baseColorLook: ColorLookPreset
    var qualityThreshold: Float  // 0.0-1.0, minimum quality score to keep (default: 0.5)
    
    // Quick Mode - skips AI frame analysis, creates segments based on beats/duration
    var quickMode: Bool
    
    // Effects & Transitions
    var transitionTypes: [TransitionType]  // Multiple transitions can be selected
    var transitionDuration: Double  // in seconds (0.1 - 1.0)
    var enableFadeToBlack: Bool
    var fadeToBlackDuration: Double  // in seconds (0.5 - 3.0)
    var effects: [VideoEffect]
    
    // Legacy support - computed property for backward compatibility
    var transitionType: TransitionType {
        get { transitionTypes.first ?? .crossfade }
        set { transitionTypes = [newValue] }
    }
    
    static let `default` = AutoEditSettings(
        targetLengthSeconds: nil,
        pace: .normal,
        style: .conversation,
        removeNoise: true,
        normalizeLoudness: true,
        baseColorLook: .neutral,
        qualityThreshold: 0.5,
        quickMode: false,
        transitionTypes: [.crossfade],
        transitionDuration: 0.25,
        enableFadeToBlack: true,
        fadeToBlackDuration: 2.0,
        effects: []
    )
}

enum Pace: String, CaseIterable {
    case relaxed
    case normal
    case tight
}

enum AutoEditStyle: String, CaseIterable {
    // New simplified styles
    case sports
    case events
    case story
    case quickCuts
    case dynamic
    
    // Legacy styles (kept for compatibility)
    // Podcast / Talking Head
    case viralVertical          // podcast.viral_vertical
    case wideConversation       // podcast.wide_conversation
    case carouselSnippet        // podcast.carousel_snippet
    case conversation
    case monologue
    case clipHighlights
    
    // Documentary
    case interviewDriven        // doc.interview_driven
    case observationalVerite     // doc.observational_cinema_verite
    case trailerCut             // doc.trailer_cut
    case storyFirst
    case interviewHighlights
    case fastPacedDoc
    
    // Music Video
    case shortformHypeVertical  // music_video.shortform_hype_vertical
    case cinematicStory16x9     // music_video.cinematic_story_16x9
    case lyricVisualizer        // music_video.lyric_visualizer
    case performance
    case montageMV
    case beatHeavyMV
    
    // Dance
    case fullRoutineSync        // dance.full_routine_sync
    case hypeEditVertical       // dance.hype_edit_vertical
    case cinematicStoryPiece    // dance.cinematic_story_piece
    case fullPerformances
    case danceHighlights
    case beatCutsDance
    
    // Highlight Reel
    case sportsHypeShort         // highlight.sports_hype_short
    case eventRecapHuman        // highlight.event_recaphuman
    case timelineStory          // highlight.timeline_story
    case dynamicHighlights
    case storyArc
    
    // MARK: - Display Labels
    
    var displayLabel: String {
        switch self {
        // New simplified styles
        case .sports: return "Sports"
        case .events: return "Events"
        case .story: return "Story"
        case .quickCuts: return "Quick Cuts"
        case .dynamic: return "Dynamic"
        
        // Legacy styles
        // Podcast
        case .viralVertical: return "Viral Vertical Clip"
        case .wideConversation: return "Wide Conversation"
        case .carouselSnippet: return "Carousel Snippet"
        case .conversation: return "Conversation"
        case .monologue: return "Monologue"
        case .clipHighlights: return "Clip Highlights"
        
        // Documentary
        case .interviewDriven: return "Interview-Driven Doc"
        case .observationalVerite: return "Observational / Cinema Verite"
        case .trailerCut: return "Documentary Trailer Cut"
        case .storyFirst: return "Story First"
        case .interviewHighlights: return "Interview Highlights"
        case .fastPacedDoc: return "Fast-Paced Doc"
        
        // Music Video
        case .shortformHypeVertical: return "Shortform Hype Vertical"
        case .cinematicStory16x9: return "Cinematic Story 16:9"
        case .lyricVisualizer: return "Lyric Visualizer"
        case .performance: return "Performance"
        case .montageMV: return "Montage"
        case .beatHeavyMV: return "Beat Heavy"
        
        // Dance
        case .fullRoutineSync: return "Full Routine Sync"
        case .hypeEditVertical: return "Hype Edit Vertical"
        case .cinematicStoryPiece: return "Cinematic Story Piece"
        case .fullPerformances: return "Full Performances"
        case .danceHighlights: return "Dance Highlights"
        case .beatCutsDance: return "Beat Cuts"
        
        // Highlight Reel
        case .sportsHypeShort: return "Sports Hype Short"
        case .eventRecapHuman: return "Event Recap (Human Moments)"
        case .timelineStory: return "Timeline Story"
        case .dynamicHighlights: return "Dynamic Highlights"
        case .storyArc: return "Story Arc"
        }
    }
    
    // MARK: - Category Helpers
    
    var category: ProjectType? {
        switch self {
        // New styles - work for all project types
        case .sports, .events, .story, .quickCuts, .dynamic:
            return nil // No specific category - works for all
        // Legacy styles
        case .viralVertical, .wideConversation, .carouselSnippet,
             .conversation, .monologue, .clipHighlights:
            return .podcast
        case .interviewDriven, .observationalVerite, .trailerCut,
             .storyFirst, .interviewHighlights, .fastPacedDoc:
            return .documentary
        case .shortformHypeVertical, .cinematicStory16x9, .lyricVisualizer,
             .performance, .montageMV, .beatHeavyMV:
            return .musicVideo
        case .fullRoutineSync, .hypeEditVertical, .cinematicStoryPiece,
             .fullPerformances, .danceHighlights, .beatCutsDance:
            return .danceVideo
        case .sportsHypeShort, .eventRecapHuman, .timelineStory,
             .dynamicHighlights, .storyArc:
            return .highlightReel
        }
    }
    
    // MARK: - Style Options by Project Type
    
    static func styles(for projectType: ProjectType) -> [AutoEditStyle] {
        // Return the 5 new simplified styles for all project types
        return [.sports, .events, .story, .quickCuts, .dynamic]
    }
    
    // Default style for each project type
    static func defaultStyle(for projectType: ProjectType) -> AutoEditStyle {
        // Default to sports for all project types
        return .sports
    }
}

enum ColorLookPreset: String, CaseIterable {
    case neutral
    case clean
    case filmic
    case punchy
}

// MARK: - Transitions & Effects

enum TransitionType: String, CaseIterable {
    case none
    case crossfade
    case zoomIn
    case zoomOut
    case slideLeft
    case slideRight
    case dipToBlack
    
    var displayLabel: String {
        switch self {
        case .none: return "None (Hard Cut)"
        case .crossfade: return "Crossfade"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .dipToBlack: return "Dip to Black"
        }
    }
}

enum VideoEffect: String, CaseIterable {
    case none
    case subtleZoom
    case kenBurns
    case parallax
    case speedRamp
    
    var displayLabel: String {
        switch self {
        case .none: return "None"
        case .subtleZoom: return "Subtle Zoom"
        case .kenBurns: return "Ken Burns"
        case .parallax: return "Parallax"
        case .speedRamp: return "Speed Ramp"
        }
    }
}

