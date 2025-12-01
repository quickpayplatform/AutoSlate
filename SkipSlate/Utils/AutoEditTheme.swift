//
//  AutoEditTheme.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct AutoEditTheme {
    // Base colors
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.09)         // windowBackground
    static let panel = Color(red: 0.10, green: 0.11, blue: 0.13)      // panelBackground
    static let border = Color(red: 0.15, green: 0.16, blue: 0.20)     // panelBorder
    
    // Text colors
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.77, green: 0.80, blue: 0.84)
    
    // Accent colors
    static let teal = Color(red: 0.12, green: 0.84, blue: 0.76)       // #1ED6C1
    static let orange = Color(red: 1.00, green: 0.70, blue: 0.28)    // #FFB347
    
    // Support colors
    static let hairlineDivider = Color(red: 0.17, green: 0.18, blue: 0.23) // #2B2F3A
}

extension View {
    func autoEditSectionTitle() -> some View {
        self.font(.system(size: 16, weight: .semibold))
            .foregroundColor(AutoEditTheme.primaryText)
    }
    
    func autoEditLabel() -> some View {
        self.font(.system(size: 14))
            .foregroundColor(AutoEditTheme.primaryText)
    }
    
    func autoEditHint() -> some View {
        self.font(.system(size: 12))
            .foregroundColor(AutoEditTheme.secondaryText)
    }
}

