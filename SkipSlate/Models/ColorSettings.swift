//
//  ColorSettings.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

struct ColorSettings: Equatable {
    var exposure: Double   // default 0.0 EV
    var contrast: Double   // default 1.0
    var saturation: Double // default 1.0
    var colorHue: Double = 0.0      // 0-360 degrees for color grading
    var colorSaturation: Double = 0.0 // 0-1 for color grading intensity
    
    static let `default` = ColorSettings(
        exposure: 0.0,
        contrast: 1.0,
        saturation: 1.0,
        colorHue: 0.0,
        colorSaturation: 0.0
    )
}

