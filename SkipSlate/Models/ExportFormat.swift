//
//  ExportFormat.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .mp4:
            return "MP4 (H.264)"
        case .mov:
            return "MOV (H.264)"
        }
    }
    
    var fileType: AVFileType {
        switch self {
        case .mp4:
            return .mp4
        case .mov:
            return .mov
        }
    }
}

