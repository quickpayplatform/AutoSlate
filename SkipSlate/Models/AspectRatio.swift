//
//  AspectRatio.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation

enum AspectRatio: String, CaseIterable, Identifiable {
    case ar16x9
    case ar9x16
    case ar1x1
    case ar4x5
    case ar235x1
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ar16x9:
            return "16:9"
        case .ar9x16:
            return "9:16"
        case .ar1x1:
            return "1:1"
        case .ar4x5:
            return "4:5"
        case .ar235x1:
            return "2.35:1"
        }
    }
    
    var ratio: Double {
        switch self {
        case .ar16x9:
            return 16.0 / 9.0
        case .ar9x16:
            return 9.0 / 16.0
        case .ar1x1:
            return 1.0
        case .ar4x5:
            return 4.0 / 5.0
        case .ar235x1:
            return 2.35
        }
    }
}

