//
//  AppColors.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct AppColors {
    // Global Background
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08) // RGB(18, 18, 20)
    static let panelBackground = Color(red: 0.14, green: 0.14, blue: 0.16) // Slightly lighter for panels
    static let cardBase = Color(red: 0.14, green: 0.14, blue: 0.16) // Card background
    static let panelBorder = Color(white: 0.25) // Subtle border
    
    // Typography - High contrast for readability
    static let primaryText = Color(white: 0.96) // Pure white/near-white for titles, main labels
    static let secondaryText = Color(white: 0.78) // Light gray for subtitles, helper text
    static let tertiaryText = Color(white: 0.6) // Mid-gray for small hints, captions
    
    // Project Type Accent Colors
    static let podcastColor = Color(hex: "#2D8CFF")
    static let documentaryColor = Color(hex: "#9D5CFF")
    static let musicVideoColor = Color(hex: "#FF4F8B")
    static let danceVideoColor = Color(hex: "#2AD49F")
    static let highlightReelColor = Color(hex: "#FF6B35") // Orange-red for highlight reels
    static let commercialsColor = Color(hex: "#FFB347") // Orange for commercials
    
    // Auto Edit Theme Colors (matching AutoEditTheme)
    static let tealAccent = Color(red: 0.12, green: 0.84, blue: 0.76) // #1ED6C1
    static let orangeAccent = Color(red: 1.00, green: 0.70, blue: 0.28) // #FFB347
    
    static func accentColor(for type: ProjectType) -> Color {
        switch type {
        case .podcast:
            return podcastColor
        case .documentary:
            return documentaryColor
        case .musicVideo:
            return musicVideoColor
        case .danceVideo:
            return danceVideoColor
        case .highlightReel:
            return highlightReelColor
        case .commercials:
            return commercialsColor
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

