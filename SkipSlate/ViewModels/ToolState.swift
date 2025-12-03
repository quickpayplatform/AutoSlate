//
//  ToolState.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//  MODULE: Tool State (ISOLATED - Kdenlive Pattern)
//
//  This class is COMPLETELY ISOLATED from ProjectViewModel and PlayerViewModel.
//  Changing tools has ZERO effect on:
//  - Video playback
//  - Composition rebuilds
//  - Preview state
//
//  Tools ONLY affect:
//  - Cursor appearance
//  - How clicks/drags on segments are interpreted
//

import SwiftUI
import AppKit

/// Isolated tool state - completely independent from project/player state
final class ToolState: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ToolState()
    
    /// Currently selected timeline tool
    @Published private(set) var selectedTool: TimelineTool = .cursor
    
    private init() {}
    
    /// Select a new tool
    func selectTool(_ tool: TimelineTool) {
        guard tool != selectedTool else { return }
        selectedTool = tool
        tool.cursor.push()
    }
    
    /// Check if current tool allows selection
    var allowsSelection: Bool {
        switch selectedTool {
        case .cursor, .segmentSelector:
            return true
        case .cut, .trim, .move:
            return false
        }
    }
    
    /// Check if current tool allows moving
    var allowsMove: Bool {
        switch selectedTool {
        case .cursor, .move:
            return true
        case .cut, .trim, .segmentSelector:
            return false
        }
    }
    
    /// Check if current tool allows seeking
    var allowsSeek: Bool {
        selectedTool == .cursor
    }
}
