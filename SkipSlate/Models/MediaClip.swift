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
/// INFINITE COLORS: Each clip gets a unique color, no wrapping or reuse
struct ClipColorPalette {
    /// AUDIO-ONLY COLOR: A distinctive warm teal blend of teal and orange
    /// Used exclusively for audio-only clips (music tracks)
    static let audioColor = Color(red: 0.40, green: 0.75, blue: 0.60)
    
    /// Base colors for the first 20 clips - handpicked for maximum distinction
    /// After these, colors are generated algorithmically using Golden Ratio hue spacing
    private static let baseColors: [Color] = [
        Color.red,                              // 0: Red
        Color.blue,                             // 1: Blue
        Color.green,                            // 2: Green
        Color.orange,                           // 3: Orange
        Color.purple,                           // 4: Purple
        Color.yellow,                           // 5: Yellow
        Color.pink,                             // 6: Pink
        Color.teal,                             // 7: Teal
        Color.cyan,                             // 8: Cyan
        Color.indigo,                           // 9: Indigo
        Color.mint,                             // 10: Mint
        Color.brown,                            // 11: Brown
        Color(red: 1.0, green: 0.84, blue: 0.0), // 12: Gold
        Color(red: 0.5, green: 0.0, blue: 0.0), // 13: Maroon
        Color(red: 0.0, green: 0.0, blue: 0.5), // 14: Navy
        Color(red: 0.8, green: 0.0, blue: 0.8), // 15: Magenta
        Color(red: 1.0, green: 0.5, blue: 0.0), // 16: Orange-red
        Color(red: 0.5, green: 0.0, blue: 1.0), // 17: Purple-blue
        Color(red: 0.0, green: 0.6, blue: 0.4), // 18: Sea green
        Color(red: 0.6, green: 0.4, blue: 0.2)  // 19: Sienna
    ]
    
    /// Golden ratio for generating evenly distributed hues
    private static let goldenRatio: Double = 0.618033988749895
    
    /// Number of base colors (for backward compatibility)
    static var colorCount: Int {
        baseColors.count
    }
    
    /// Legacy constant for backward compatibility - no longer limits actual colors
    static let highlightReelColorCount: Int = 12
    
    /// Generate a unique color for any index - INFINITE colors supported
    /// Uses base colors for indices 0-19, then generates algorithmically
    static func color(for index: Int) -> Color {
        guard index >= 0 else { return baseColors[0] }
        
        // Use handpicked base colors for first 20 indices
        if index < baseColors.count {
            return baseColors[index]
        }
        
        // For indices beyond base colors, generate using Golden Ratio hue distribution
        // This ensures each color is visually distinct from its neighbors
        return generateColor(for: index)
    }
    
    /// Get color for Highlight Reel - now uses the unified infinite color system
    /// Kept for backward compatibility
    static func highlightReelColor(for index: Int) -> Color {
        return color(for: index)
    }
    
    /// Generate a unique color using Golden Ratio hue distribution
    /// This produces visually distinct colors even for very high indices
    private static func generateColor(for index: Int) -> Color {
        // Start from a different hue for indices beyond base colors
        let adjustedIndex = index - baseColors.count
        
        // Use golden ratio to spread hues evenly
        var hue = Double(adjustedIndex) * goldenRatio
        hue = hue.truncatingRemainder(dividingBy: 1.0)
        
        // Vary saturation and brightness slightly to increase distinction
        let saturationVariance = Double((adjustedIndex % 3)) * 0.1 // 0.0, 0.1, or 0.2
        let brightnessVariance = Double((adjustedIndex % 4)) * 0.05 // 0.0, 0.05, 0.10, or 0.15
        
        let saturation = 0.7 + saturationVariance // Range: 0.7 - 0.9
        let brightness = 0.85 - brightnessVariance // Range: 0.70 - 0.85
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    /// Cache for generated colors to avoid recalculating
    private static var colorCache: [Int: Color] = [:]
    
    /// Get or generate a cached color for an index
    static func cachedColor(for index: Int) -> Color {
        if let cached = colorCache[index] {
            return cached
        }
        let newColor = color(for: index)
        colorCache[index] = newColor
        return newColor
    }
}

