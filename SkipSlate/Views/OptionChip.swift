//
//  OptionChip.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct OptionChip: View {
    let label: String
    let isSelected: Bool
    let isSecondaryAccent: Bool  // false = teal, true = orange
    
    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(
                Group {
                    if isSelected && !isSecondaryAccent {
                        AutoEditTheme.teal
                    } else if isSelected && isSecondaryAccent {
                        Color.clear
                    } else {
                        AutoEditTheme.panel
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected
                            ? (isSecondaryAccent ? AutoEditTheme.orange : AutoEditTheme.teal)
                            : AutoEditTheme.border,
                        lineWidth: 1
                    )
            )
            .cornerRadius(14)
    }
}

struct ColorLookSwatch: View {
    let preset: ColorLookPreset
    let isSelected: Bool
    
    private var gradient: LinearGradient {
        switch preset {
        case .neutral:
            return LinearGradient(
                colors: [Color(white: 0.2), Color(white: 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .clean:
            return LinearGradient(
                colors: [Color(red: 0.1, green: 0.3, blue: 0.4), Color(red: 0.2, green: 0.5, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .filmic:
            return LinearGradient(
                colors: [Color(red: 0.3, green: 0.2, blue: 0.1), Color(red: 0.2, green: 0.4, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .punchy:
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.2, blue: 0.1), Color(red: 0.5, green: 0.3, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Color preview
            RoundedRectangle(cornerRadius: 12)
                .fill(gradient)
                .frame(width: 80, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? AutoEditTheme.orange : AutoEditTheme.border,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(color: isSelected ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 8)
            
            // Label
            Text(preset.rawValue.capitalized)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : AutoEditTheme.secondaryText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? AutoEditTheme.panel.opacity(0.5) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected ? AutoEditTheme.orange : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

