//
//  StockService.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation

enum StockServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case downloadFailed
    case backendNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from backend."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .downloadFailed:
            return "Failed to download video file."
        case .backendNotConfigured:
            return "Backend URL is not configured."
        }
    }
}

class StockService {
    static let shared = StockService()
    
    // Backend base URL - defaults to localhost:4000 for development
    // Can be overridden via environment variable or UserDefaults
    private var backendBaseURL: String {
        // Try environment variable first
        if let envURL = ProcessInfo.processInfo.environment["AUTO_SLATE_API_BASE_URL"], !envURL.isEmpty {
            return envURL
        }
        
        // Try UserDefaults
        if let userDefaultsURL = UserDefaults.standard.string(forKey: "AutoSlateBackendURL"), !userDefaultsURL.isEmpty {
            return userDefaultsURL
        }
        
        // Default to localhost
        return "http://localhost:4000"
    }
    
    private init() {}
    
    // MARK: - Search Stock Videos
    
    func searchPexels(
        query: String,
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> StockSearchResponse {
        guard !query.isEmpty else {
            throw StockServiceError.invalidURL
        }
        
        // Build URL
        var components = URLComponents(string: "\(backendBaseURL)/api/stock/pexels/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        guard let url = components.url else {
            throw StockServiceError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StockServiceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                // Try to parse error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? String {
                    print("SkipSlate: StockService - Backend error: \(error)")
                }
                throw StockServiceError.httpError(httpResponse.statusCode)
            }
            
            // Decode response
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(StockSearchResponse.self, from: data)
            
            print("SkipSlate: StockService - Found \(searchResponse.clips.count) stock clips for query '\(query)'")
            return searchResponse
            
        } catch let error as StockServiceError {
            throw error
        } catch {
            print("SkipSlate: ❌ StockService - Search error: \(error)")
            throw StockServiceError.networkError(error)
        }
    }
    
    // MARK: - Download Stock Video
    
    func downloadStockVideo(from clip: StockClip) async throws -> URL {
        print("SkipSlate: StockService - Downloading video from: \(clip.downloadUrl)")
        
        // Download video
        let (data, response) = try await URLSession.shared.data(from: clip.downloadUrl)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StockServiceError.downloadFailed
        }
        
        // Determine file extension from URL or content type
        var fileExtension = "mp4"
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            if contentType.contains("quicktime") {
                fileExtension = "mov"
            } else if contentType.contains("webm") {
                fileExtension = "webm"
            }
        } else if clip.downloadUrl.pathExtension.isEmpty == false {
            fileExtension = clip.downloadUrl.pathExtension
        }
        
        // Save to temporary file with descriptive name
        let fileName = "pexels_\(clip.sourceId).\(fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        
        try data.write(to: tempURL)
        print("SkipSlate: StockService - Downloaded video to: \(tempURL.path)")
        
        return tempURL
    }
    
    // MARK: - Configuration
    
    func setBackendURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "AutoSlateBackendURL")
        print("SkipSlate: StockService - Backend URL set to: \(url)")
    }
    
    var isBackendConfigured: Bool {
        return !backendBaseURL.isEmpty
    }
}

