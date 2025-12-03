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
//  This follows Kdenlive's architecture where tool state is separate from
//  timeline/playback state to prevent cascade effects.
//

import SwiftUI
import AppKit

/// Isolated tool state - completely independent from project/player state
/// This singleton ensures tool changes never trigger composition rebuilds
final class ToolState: ObservableObject {
    
    // MARK: - Singleton
    static let shared = ToolState()
    
    // MARK: - Published Properties
    
    /// Currently selected timeline tool
    /// Changing this ONLY affects cursor and segment interaction behavior
    /// It does NOT affect: video player, preview, composition, playback state
    @Published private(set) var selectedTool: TimelineTool = .cursor
    
    // MARK: - Private Init (Singleton)
    private init() {}
    
    // MARK: - Public Methods
    
    /// Select a new tool - only changes cursor and interaction behavior
    /// This method is intentionally simple to prevent any side effects
    func selectTool(_ tool: TimelineTool) {
        guard tool != selectedTool else { return }  // No change needed
        selectedTool = tool
        updateCursor(for: tool)
    }
    
    /// Update cursor to match the current tool
    private func updateCursor(for tool: TimelineTool) {
        // Use tool's built-in cursor
        tool.cursor.push()
    }
    
    /// Reset to default tool (cursor/select)
    func resetToDefault() {
        selectTool(.cursor)
    }
    
    // MARK: - Tool Query Methods (No side effects)
    
    /// Check if current tool allows segment selection
    var allowsSelection: Bool {
        switch selectedTool {
        case .cursor, .segmentSelector:
            return true
        case .cut, .trim, .move:
            return false
        }
    }
    
    /// Check if current tool allows segment moving
    var allowsMove: Bool {
        switch selectedTool {
        case .cursor, .move:
            return true
        case .cut, .trim, .segmentSelector:
            return false
        }
    }
    
    /// Check if current tool is the blade/razor tool
    var isBladeTool: Bool {
        selectedTool == .cut
    }
    
    /// Check if current tool is the trim tool
    var isTrimTool: Bool {
        selectedTool == .trim
    }
    
    /// Check if current tool allows seeking by clicking on timeline
    var allowsSeek: Bool {
        selectedTool == .cursor
    }
}
