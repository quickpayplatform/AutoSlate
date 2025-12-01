//
//  ProjectType.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

enum ProjectType: String, CaseIterable, Identifiable {
    case podcast
    case documentary
    case musicVideo
    case danceVideo
    case highlightReel
    case commercials
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .podcast:
            return "Podcast"
        case .documentary:
            return "Documentary"
        case .musicVideo:
            return "Music Video"
        case .danceVideo:
            return "Dance Video"
        case .highlightReel:
            return "Highlight Reel"
        case .commercials:
            return "Commercials"
        }
    }
}

