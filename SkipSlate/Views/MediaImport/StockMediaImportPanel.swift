//
//  StockMediaImportPanel.swift
//
//  MODULE: Media Import UI - Stock Media Import Panel
//  - Wraps StockSearchView for stock media import
//  - Encapsulates stock media import UI
//  - Does NOT touch PlayerViewModel
//  - Can be restyled without affecting video preview
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StockMediaImportPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var isDragOver = false

    var body: some View {
        ZStack {
            StockSearchView(projectViewModel: projectViewModel)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            
            // Drag overlay hint
            if isDragOver {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 64))
                        .foregroundColor(AppColors.tealAccent)
                    Text("Drop video files or URLs here")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text("Drag from browser or Finder")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background.opacity(0.95))
            }
        }
        .onDrop(of: [.fileURL, .url], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var fileURLs: [URL] = []
        var remoteURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            // Handle file URLs (from Finder) - import directly
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    
                    guard error == nil else {
                        print("SkipSlate: StockMediaImportPanel - Error loading file URL: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        fileURLs.append(url)
                    } else if let url = item as? URL {
                        fileURLs.append(url)
                    } else if let str = item as? String, let url = URL(string: str) {
                        fileURLs.append(url)
                    }
                }
            }
            // Handle web URLs (from browser) - download first, then import
            else if provider.hasItemConformingToTypeIdentifier("public.url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, error in
                    defer { group.leave() }
                    
                    guard error == nil else {
                        print("SkipSlate: StockMediaImportPanel - Error loading URL: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    var url: URL?
                    if let urlItem = item as? URL {
                        url = urlItem
                    } else if let str = item as? String, let urlItem = URL(string: str) {
                        url = urlItem
                    }
                    
                    guard let videoURL = url else { return }
                    
                    // Check if it's a video URL (by extension or domain)
                    let isVideoURL = videoURL.pathExtension.lowercased() == "mp4" || 
                                    videoURL.pathExtension.lowercased() == "mov" ||
                                    videoURL.pathExtension.lowercased() == "webm" ||
                                    videoURL.pathExtension.lowercased() == "m4v" ||
                                    videoURL.absoluteString.contains("pexels.com/video") ||
                                    videoURL.absoluteString.contains("pexels.com/videos") ||
                                    videoURL.absoluteString.contains("video") ||
                                    videoURL.absoluteString.contains(".mp4") ||
                                    videoURL.absoluteString.contains(".mov")
                    
                    if isVideoURL {
                        remoteURLs.append(videoURL)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            // Import local files immediately
            if !fileURLs.isEmpty {
                print("SkipSlate: StockMediaImportPanel - Importing \(fileURLs.count) local file(s) from drag & drop")
                projectViewModel.importMedia(urls: fileURLs)
            }
            
            // Download and import remote URLs
            if !remoteURLs.isEmpty {
                print("SkipSlate: StockMediaImportPanel - Downloading \(remoteURLs.count) remote video URL(s) from drag & drop")
                for url in remoteURLs {
                    downloadAndImportVideo(from: url)
                }
            }
        }
        
        return true
    }
    
    private func downloadAndImportVideo(from url: URL) {
        // Check if it's already a local file
        if url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
            projectViewModel.importMedia(urls: [url])
            return
        }
        
        // It's a remote URL - download it first
        Task {
            do {
                print("SkipSlate: StockMediaImportPanel - Downloading video from: \(url.absoluteString)")
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("SkipSlate: StockMediaImportPanel - Download failed: HTTP \(response)")
                    return
                }
                
                // Determine file extension
                var fileExtension = "mp4"
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    if contentType.contains("quicktime") {
                        fileExtension = "mov"
                    } else if contentType.contains("webm") {
                        fileExtension = "webm"
                    } else if contentType.contains("mp4") {
                        fileExtension = "mp4"
                    }
                } else if !url.pathExtension.isEmpty {
                    fileExtension = url.pathExtension
                }
                
                // Save to temporary file
                let fileName = "dragged_video_\(UUID().uuidString.prefix(8)).\(fileExtension)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                
                try data.write(to: tempURL)
                print("SkipSlate: StockMediaImportPanel - Downloaded video to: \(tempURL.path)")
                
                // Verify file was written
                guard FileManager.default.fileExists(atPath: tempURL.path) else {
                    print("SkipSlate: StockMediaImportPanel - Downloaded file does not exist at: \(tempURL.path)")
                    return
                }
                
                // Import the downloaded file
                await MainActor.run {
                    projectViewModel.importMedia(urls: [tempURL])
                }
            } catch {
                print("SkipSlate: StockMediaImportPanel - Error downloading video: \(error.localizedDescription)")
            }
        }
    }
}
