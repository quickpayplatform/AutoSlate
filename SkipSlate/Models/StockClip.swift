//
//  StockClip.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation

struct StockClip: Identifiable, Decodable {
    let id: String
    let provider: String
    let sourceId: Int
    let width: Int
    let height: Int
    let duration: Double
    let thumbnailUrl: URL
    let downloadUrl: URL
    let tags: [String]
    let attribution: Attribution
    
    struct Attribution: Decodable {
        let providerName: String
        let url: URL
    }
}

struct StockSearchResponse: Decodable {
    let clips: [StockClip]
    let page: Int
    let per_page: Int
    let total_results: Int
    let next_page: String?
}

