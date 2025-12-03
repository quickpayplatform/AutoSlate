//
//  SegmentIDTransfer.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import SwiftUI
import UniformTypeIdentifiers

/// Transferable type for dragging segment IDs from Media tab to Timeline
struct SegmentIDTransfer: Codable, Transferable {
    let segmentID: UUID
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .segmentID)
    }
}

extension UTType {
    static let segmentID = UTType(exportedAs: "com.skipslate.segment-id")
}


