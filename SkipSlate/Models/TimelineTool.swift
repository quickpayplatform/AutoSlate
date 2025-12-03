//
//  TimelineTool.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation
import AppKit

/// Timeline editing tools
enum TimelineTool: String, CaseIterable, Identifiable {
    case cursor = "cursor"
    case segmentSelector = "segmentSelector"
    case move = "move"
    case cut = "cut"
    case trim = "trim"
    
    var id: String { rawValue }
    
    /// Display name for the tool
    var name: String {
        switch self {
        case .cursor: return "Cursor"
        case .segmentSelector: return "Select"
        case .move: return "Move"
        case .cut: return "Cut"
        case .trim: return "Trim"
        }
    }
    
    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .cursor: return "arrow.up.and.down.and.arrow.left.and.right"
        case .segmentSelector: return "hand.tap"
        case .move: return "hand.draw"
        case .cut: return "scissors"
        case .trim: return "arrow.left.and.right"
        }
    }
    
    /// Help text for the tool
    var helpText: String {
        switch self {
        case .cursor: return "Select and move playhead"
        case .segmentSelector: return "Select segments"
        case .move: return "Drag segments to move them in timeline"
        case .cut: return "Cut segments at click position"
        case .trim: return "Trim segment start/end points"
        }
    }
    
    /// NSCursor for the tool
    var cursor: NSCursor {
        switch self {
        case .cursor: return .arrow
        case .segmentSelector: return .pointingHand
        case .move: return .openHand
        case .cut: return .crosshair
        case .trim: return .resizeLeftRight
        }
    }
}
