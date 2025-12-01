//
//  ResolutionPreset.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct ResolutionPreset: Identifiable, Hashable {
    let width: Int
    let height: Int
    let label: String
    
    var id: String { label }
    
    static let presets: [ResolutionPreset] = [
        // Horizontal formats
        ResolutionPreset(width: 1280, height: 720, label: "720p"),
        ResolutionPreset(width: 1920, height: 1080, label: "1080p"),
        ResolutionPreset(width: 2560, height: 1440, label: "1440p"),
        ResolutionPreset(width: 3840, height: 2160, label: "4K"),
        // Vertical formats (9:16)
        ResolutionPreset(width: 720, height: 1280, label: "720p Vertical"),
        ResolutionPreset(width: 1080, height: 1920, label: "1080p Vertical"),
        ResolutionPreset(width: 1440, height: 2560, label: "1440p Vertical"),
        ResolutionPreset(width: 2160, height: 3840, label: "4K Vertical")
    ]
    
    static func presetsForAspectRatio(_ aspectRatio: AspectRatio) -> [ResolutionPreset] {
        let allPresets = ResolutionPreset.presets
        
        // For v1, return all presets and let export handle aspect ratio conversion
        // In a future version, we could filter or create aspect-ratio-specific presets
        let matching = allPresets.filter { preset in
            let presetRatio = Double(preset.width) / Double(preset.height)
            let targetRatio = aspectRatio.ratio
            // Allow some tolerance
            return abs(presetRatio - targetRatio) < 0.15
        }
        
        // If no matches, return all presets (export will handle conversion)
        return matching.isEmpty ? allPresets : matching
    }
}

