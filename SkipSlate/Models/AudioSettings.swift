//
//  AudioSettings.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct AudioSettings: Equatable {
    var targetLoudness: Double   // e.g. LUFS target or pseudo-value
    var enableNoiseReduction: Bool
    var enableCompression: Bool
    var masterGainDB: Double
    
    static let `default` = AudioSettings(
        targetLoudness: -16.0,
        enableNoiseReduction: true,
        enableCompression: true,
        masterGainDB: 0.0
    )
}

