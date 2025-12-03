//
//  PexelsService.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//


import Foundation
import Combine

// MARK: - Pexels API Models

struct PexelsVideo: Codable, Identifiable {
    let id: Int
    let width: Int
    let height: Int
    let duration: Int // Duration in seconds
    let image: String // Preview image URL
    let videoFiles: [PexelsVideoFile]
    let videoPictures: [PexelsVideoPicture]
    
    enum CodingKeys: String, CodingKey {
        case id, width, height, duration, image
        case videoFiles = "video_files"
        case videoPictures = "video_pictures"
    }
}

struct PexelsVideoFile: Codable {
    let id: Int
    let quality: String
    let fileType: String
    let width: Int?
    let height: Int?
    let link: String
    let fps: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, quality, width, height, link, fps
        case fileType = "file_type"
    }
}

struct PexelsVideoPicture: Codable {
    let id: Int
    let picture: String
    let nr: Int
}

struct PexelsPhoto: Codable, Identifiable {
    let id: Int
    let width: Int
    let height: Int
    let url: String
    let photographer: String
    let photographerUrl: String
    let photographerId: Int
    let avgColor: String
    let src: PexelsPhotoSource
    let liked: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, width, height, url, photographer, liked
        case photographerUrl = "photographer_url"
        case photographerId = "photographer_id"
        case avgColor = "avg_color"
        case src
    }
}

struct PexelsPhotoSource: Codable {
    let original: String
    let large2x: String
    let large: String
    let medium: String
    let small: String
    let portrait: String
    let landscape: String
    let tiny: String
}

struct PexelsVideoSearchResponse: Codable {
    let page: Int
    let perPage: Int
    let totalResults: Int
    let videos: [PexelsVideo]
    let nextPage: String?
    
    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case totalResults = "total_results"
        case videos
        case nextPage = "next_page"
    }
}

struct PexelsPhotoSearchResponse: Codable {
    let page: Int
    let perPage: Int
    let totalResults: Int
    let photos: [PexelsPhoto]
    let nextPage: String?
    
    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case totalResults = "total_results"
        case photos
        case nextPage = "next_page"
    }
}

// MARK: - Pexels Service

class PexelsService {
    static let shared = PexelsService()
    
    private var apiKey: String?
    private let baseURL = "https://api.pexels.com/v1"
    
    private init() {
        loadAPIKey()
    }
    
    // MARK: - API Key Management
    
    private func loadAPIKey() {
        // CRASH-PROOF: Load API key from environment variable or .env file
        // First try environment variable
        if let envKey = ProcessInfo.processInfo.environment["PEXELS_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
            print("SkipSlate: PexelsService - Loaded API key from environment variable")
            return
        }
        
        // Try loading from .env file in project root
        if let envPath = Bundle.main.path(forResource: ".env", ofType: nil) ??
                         Bundle.main.resourcePath?.appending("/.env") {
            do {
                let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
                let lines = envContent.components(separatedBy: .newlines)
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") || trimmed.isEmpty {
                        continue
                    }
                    
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                        
                        if key == "PEXELS_API_KEY" {
                            apiKey = value
                            print("SkipSlate: PexelsService - Loaded API key from .env file")
                            break
                        }
                    }
                }
            } catch {
                print("SkipSlate: ⚠️ PexelsService - Could not load .env file: \(error)")
            }
        }
        
        // Fallback: Try to load from UserDefaults (for manual configuration)
        if apiKey == nil {
            apiKey = UserDefaults.standard.string(forKey: "PexelsAPIKey")
            if apiKey != nil {
                print("SkipSlate: PexelsService - Loaded API key from UserDefaults")
            }
        }
        
        if apiKey == nil {
            print("SkipSlate: ⚠️ PexelsService - No API key found. Pexels features will be disabled.")
            print("SkipSlate: PexelsService - Set PEXELS_API_KEY environment variable or add to .env file")
        }
    }
    
    func setAPIKey(_ key: String) {
        apiKey = key
        UserDefaults.standard.set(key, forKey: "PexelsAPIKey")
        print("SkipSlate: PexelsService - API key set successfully")
    }
    
    var isConfigured: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    // MARK: - Search Videos
    
    func searchVideos(
        query: String,
        page: Int = 1,
        perPage: Int = 15,
        orientation: String? = nil,
        size: String? = nil
    ) async throws -> PexelsVideoSearchResponse {
        guard isConfigured, let apiKey = apiKey else {
            throw PexelsError.apiKeyNotConfigured
        }
        
        // CRASH-PROOF: Validate query
        guard !query.isEmpty else {
            throw PexelsError.invalidQuery
        }
        
        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)/videos/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        if let orientation = orientation {
            queryItems.append(URLQueryItem(name: "orientation", value: orientation))
        }
        
        if let size = size {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw PexelsError.invalidURL
        }
        
        // Create request with API key
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        // CRASH-PROOF: Perform request with error handling
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PexelsError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw PexelsError.unauthorized
                } else if httpResponse.statusCode == 429 {
                    throw PexelsError.rateLimitExceeded
                } else {
                    throw PexelsError.httpError(httpResponse.statusCode)
                }
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(PexelsVideoSearchResponse.self, from: data)
            
            print("SkipSlate: PexelsService - Found \(searchResponse.videos.count) videos for query '\(query)'")
            return searchResponse
            
        } catch let error as PexelsError {
            throw error
        } catch {
            print("SkipSlate: ❌ PexelsService - Video search error: \(error)")
            throw PexelsError.networkError(error)
        }
    }
    
    // MARK: - Search Photos
    
    func searchPhotos(
        query: String,
        page: Int = 1,
        perPage: Int = 15,
        orientation: String? = nil,
        size: String? = nil,
        color: String? = nil,
        locale: String? = nil
    ) async throws -> PexelsPhotoSearchResponse {
        guard isConfigured, let apiKey = apiKey else {
            throw PexelsError.apiKeyNotConfigured
        }
        
        // CRASH-PROOF: Validate query
        guard !query.isEmpty else {
            throw PexelsError.invalidQuery
        }
        
        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        if let orientation = orientation {
            queryItems.append(URLQueryItem(name: "orientation", value: orientation))
        }
        
        if let size = size {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        
        if let color = color {
            queryItems.append(URLQueryItem(name: "color", value: color))
        }
        
        if let locale = locale {
            queryItems.append(URLQueryItem(name: "locale", value: locale))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw PexelsError.invalidURL
        }
        
        // Create request with API key
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        // CRASH-PROOF: Perform request with error handling
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PexelsError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw PexelsError.unauthorized
                } else if httpResponse.statusCode == 429 {
                    throw PexelsError.rateLimitExceeded
                } else {
                    throw PexelsError.httpError(httpResponse.statusCode)
                }
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(PexelsPhotoSearchResponse.self, from: data)
            
            print("SkipSlate: PexelsService - Found \(searchResponse.photos.count) photos for query '\(query)'")
            return searchResponse
            
        } catch let error as PexelsError {
            throw error
        } catch {
            print("SkipSlate: ❌ PexelsService - Photo search error: \(error)")
            throw PexelsError.networkError(error)
        }
    }
    
    // MARK: - Download Video/Photo
    
    func downloadVideo(from url: URL) async throws -> URL {
        // CRASH-PROOF: Download video to temporary location
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PexelsError.downloadFailed
        }
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        try data.write(to: tempURL)
        print("SkipSlate: PexelsService - Downloaded video to: \(tempURL.path)")
        
        return tempURL
    }
    
    func downloadPhoto(from url: URL, quality: String = "large") async throws -> URL {
        // CRASH-PROOF: Download photo to temporary location
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PexelsError.downloadFailed
        }
        
        // Determine file extension from URL
        let fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        
        try data.write(to: tempURL)
        print("SkipSlate: PexelsService - Downloaded photo to: \(tempURL.path)")
        
        return tempURL
    }
}

// MARK: - Pexels Errors

enum PexelsError: LocalizedError {
    case apiKeyNotConfigured
    case invalidQuery
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimitExceeded
    case httpError(Int)
    case networkError(Error)
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Pexels API key is not configured. Please set PEXELS_API_KEY in your .env file or environment variables."
        case .invalidQuery:
            return "Invalid search query. Query cannot be empty."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from Pexels API."
        case .unauthorized:
            return "Unauthorized. Please check your Pexels API key."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .downloadFailed:
            return "Failed to download media file."
        }
    }
}

