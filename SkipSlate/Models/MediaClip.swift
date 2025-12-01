//
//  MediaClip.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import SwiftUI

struct MediaClip: Identifiable {
    let id: UUID
    let url: URL
    let type: MediaClipType
    let duration: Double
    var isSelected: Bool
    let hasAudioTrack: Bool  // Track whether source file has audio track
    var colorIndex: Int = 0  // Unique color index assigned during analysis
    
    // Stabilization metadata
    var shakeLevel: Double = 0.0  // 0.0 (very stable) to 1.0 (very shaky)
    var stabilizationProfile: StabilizationProfile?  // Stabilization settings for this clip
    
    var fileName: String {
        url.lastPathComponent
    }
}

/// Stabilization profile for a clip
struct StabilizationProfile: Codable {
    let enabled: Bool
    let intensity: Double  // 0.0 – 1.0, where 0.0 = off, 1.0 = maximum smoothing
    
    static func `default`(for shakeLevel: Double) -> StabilizationProfile {
        switch shakeLevel {
        case 0.0..<0.2:
            return StabilizationProfile(enabled: false, intensity: 0.0)  // Very stable, no stabilization needed
        case 0.2..<0.5:
            return StabilizationProfile(enabled: true, intensity: 0.4)  // Mild shake, light stabilization
        case 0.5..<0.8:
            return StabilizationProfile(enabled: true, intensity: 0.7)  // Moderate shake, medium stabilization
        default:
            return StabilizationProfile(enabled: true, intensity: 1.0)  // Very shaky, maximum stabilization
        }
    }
}

enum MediaClipType {
    case videoWithAudio
    case videoOnly
    case audioOnly
    case image  // Static image (will be treated as video with default duration)
}

/// Color palette for clip visualization - ensures each clip gets a unique color
struct ClipColorPalette {
    /// Array of distinct colors for video clips (excluding green which is reserved for audio)
    static let colors: [Color] = [
        Color.blue.opacity(0.7),
        Color.orange.opacity(0.7),
        Color.purple.opacity(0.7),
        Color.pink.opacity(0.7),
        Color.red.opacity(0.7),
        Color.yellow.opacity(0.7),
        Color.cyan.opacity(0.7),
        Color.mint.opacity(0.7),
        Color.indigo.opacity(0.7),
        Color.teal.opacity(0.7),
        Color.brown.opacity(0.7),
        Color(red: 1.0, green: 0.5, blue: 0.0).opacity(0.7), // Orange-red
        Color(red: 0.5, green: 0.0, blue: 1.0).opacity(0.7), // Purple-blue
        Color(red: 1.0, green: 0.0, blue: 0.5).opacity(0.7), // Pink-red
        Color(red: 0.0, green: 0.8, blue: 0.8).opacity(0.7), // Cyan-teal
        Color(red: 0.8, green: 0.0, blue: 0.8).opacity(0.7), // Magenta
        Color(red: 0.5, green: 0.5, blue: 0.0).opacity(0.7), // Olive
        Color(red: 0.0, green: 0.5, blue: 0.5).opacity(0.7), // Dark cyan
        Color(red: 0.5, green: 0.0, blue: 0.5).opacity(0.7), // Dark magenta
        Color(red: 0.8, green: 0.4, blue: 0.0).opacity(0.7)  // Dark orange
    ]
    
    static var colorCount: Int {
        colors.count
    }
    
    /// Get color for a given index (wraps around if index exceeds color count)
    static func color(for index: Int) -> Color {
        guard index >= 0 else { return colors[0] } // Safety check
        return colors[abs(index) % colors.count]
    }
    
    // MARK: - Highlight Reel Specific Colors (12 colors in exact order)
    
    /// Highlight Reel color palette - exactly 12 colors in specific order
    /// Color indices: 0=Red, 1=Blue, 2=Green, 3=Yellow, 4=Orange, 5=Purple, 6=Pink, 7=Teal, 8=Navy, 9=Maroon, 10=Gold, 11=Grey
    static let highlightReelColors: [Color] = [
        Color.red.opacity(0.7),                              // 0: Red
        Color.blue.opacity(0.7),                             // 1: Blue
        Color.green.opacity(0.7),                            // 2: Green
        Color.yellow.opacity(0.7),                           // 3: Yellow
        Color.orange.opacity(0.7),                           // 4: Orange
        Color.purple.opacity(0.7),                           // 5: Purple
        Color.pink.opacity(0.7),                             // 6: Pink
        Color.teal.opacity(0.7),                             // 7: Teal
        Color(red: 0.0, green: 0.0, blue: 0.5).opacity(0.7), // 8: Navy
        Color(red: 0.5, green: 0.0, blue: 0.0).opacity(0.7), // 9: Maroon
        Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.7), // 10: Gold
        Color.gray.opacity(0.7)                              // 11: Grey
    ]
    
    static let highlightReelColorCount: Int = 12
    
    /// Get Highlight Reel color for a given index (0-11)
    /// CRASH-PROOF: Validates index bounds
    static func highlightReelColor(for index: Int) -> Color {
        guard index >= 0 && index < highlightReelColorCount else {
            // Safety fallback: use first color if index is out of bounds
            print("SkipSlate: ⚠️ Highlight Reel color index \(index) out of bounds, using Red")
            return highlightReelColors[0]
        }
        return highlightReelColors[index]
    }
}

