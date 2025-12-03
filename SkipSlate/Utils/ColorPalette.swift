//
//  ColorPalette.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct ColorPalette {
    /// AUDIO-ONLY COLOR: A distinctive warm teal blend of teal and orange
    /// Used exclusively for audio-only clips (music tracks)
    static let audioColor = Color(red: 0.40, green: 0.75, blue: 0.60)
    
    static let accentColors: [Color] = [
        Color(red: 0.2, green: 0.6, blue: 1.0),      // Blue
        Color(red: 1.0, green: 0.4, blue: 0.4),      // Red
        Color(red: 0.4, green: 0.8, blue: 0.4),      // Green
        Color(red: 1.0, green: 0.8, blue: 0.2),       // Yellow
        Color(red: 0.8, green: 0.4, blue: 1.0),       // Purple
        Color(red: 1.0, green: 0.6, blue: 0.4),       // Orange
        Color(red: 0.4, green: 0.8, blue: 0.8)       // Cyan
    ]
    
    static func color(for index: Int) -> Color {
        accentColors[index % accentColors.count]
    }
}

