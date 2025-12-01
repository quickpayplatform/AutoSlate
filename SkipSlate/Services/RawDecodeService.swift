//
//  RawDecodeService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation

class RawDecodeService {
    static let shared = RawDecodeService()
    
    private init() {}
    
    func canDecodeRawFormat(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        
        // Check for known RAW formats
        let rawExtensions = ["braw", "r3d", "ari", "arx", "mxf"]
        guard rawExtensions.contains(ext) else {
            return true // Not a RAW format, assume decodable
        }
        
        // Try to create AVAsset and check if it can be loaded
        let asset = AVURLAsset(url: url)
        
        // For v1, we'll attempt to load and see if it works
        // In a real implementation, you might check for vendor SDKs here
        return true // Stub: attempt to decode
    }
    
    func checkRawSupport(url: URL) -> (supported: Bool, message: String?) {
        let ext = url.pathExtension.lowercased()
        
        if ext == "braw" || ext == "r3d" {
            // Try to load the asset
            let asset = AVURLAsset(url: url)
            
            // For v1, we'll attempt to use AVFoundation
            // If system can't decode, it will fail during import
            return (true, nil) // Stub: let AVFoundation handle it
        }
        
        return (true, nil)
    }
}

