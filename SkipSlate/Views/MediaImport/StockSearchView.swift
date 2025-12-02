//
//  StockSearchView.swift
//  SkipSlate
//
//  Created by Cursor on 12/2/25.
//
//  MODULE: Media Import UI - Stock Search Component
//  - Handles stock video search and import from Pexels
//  - Completely independent of preview/playback
//  - Only communicates with ProjectViewModel.importMedia()
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct StockSearchView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var searchQuery: String = "cinematic b-roll"
    @State private var searchResults: [StockClip] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var hasMorePages = false
    @State private var downloadingClipId: String?
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                
                TextField("Search stock videos...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isSearchFocused)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.podcastColor)
                .disabled(isLoading || searchQuery.isEmpty)
            }
            .padding(12)
            .background(AppColors.cardBase)
            .cornerRadius(8)
            
            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 12)
            }
            
            // Results grid
            if isLoading && searchResults.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Searching stock videos...")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else if searchResults.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.secondaryText.opacity(0.5))
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(AppColors.secondaryText)
                    Text("Try a different search query")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(searchResults) { clip in
                            StockClipCard(
                                clip: clip,
                                isDownloading: downloadingClipId == clip.id,
                                onImport: {
                                    importStockClip(clip)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 20)
                    
                    // Load more button
                    if hasMorePages && !isLoading {
                        Button("Load More") {
                            loadMoreResults()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 20)
                    }
                }
            }
            
            // Attribution footer
            HStack {
                Text("Stock videos provided by")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Link("Pexels", destination: URL(string: "https://www.pexels.com")!)
                    .font(.caption)
                    .foregroundColor(AppColors.podcastColor)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
        .onAppear {
            // Perform initial search
            if searchResults.isEmpty {
                performSearch()
            }
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        currentPage = 1
        searchResults = []
        
        Task {
            do {
                let response = try await StockService.shared.searchPexels(
                    query: searchQuery,
                    page: currentPage,
                    perPage: 20
                )
                
                await MainActor.run {
                    searchResults = response.clips
                    hasMorePages = response.next_page != nil
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func loadMoreResults() {
        guard !isLoading && hasMorePages else { return }
        
        isLoading = true
        currentPage += 1
        
        Task {
            do {
                let response = try await StockService.shared.searchPexels(
                    query: searchQuery,
                    page: currentPage,
                    perPage: 20
                )
                
                await MainActor.run {
                    searchResults.append(contentsOf: response.clips)
                    hasMorePages = response.next_page != nil
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func importStockClip(_ clip: StockClip) {
        downloadingClipId = clip.id
        
        Task {
            do {
                // Download the video
                let localURL = try await StockService.shared.downloadStockVideo(from: clip)
                
                // Import it using the existing import flow
                await MainActor.run {
                    projectViewModel.importMedia(urls: [localURL])
                    downloadingClipId = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download video: \(error.localizedDescription)"
                    downloadingClipId = nil
                }
            }
        }
    }
}

struct StockClipCard: View {
    let clip: StockClip
    let isDownloading: Bool
    let onImport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                AsyncImage(url: clip.thumbnailUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(AppColors.cardBase)
                        .overlay(
                            ProgressView()
                        )
                }
                .frame(height: 120)
                .clipped()
                .cornerRadius(8)
                
                // Duration overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(timeString(from: clip.duration))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(6)
                
                // Download overlay
                if isDownloading {
                    ZStack {
                        Color.black.opacity(0.6)
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    .cornerRadius(8)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("\(clip.width)×\(clip.height)")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                
                // Tags
                if !clip.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(clip.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.podcastColor.opacity(0.2))
                                .foregroundColor(AppColors.podcastColor)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            
            // Import button
            Button(action: onImport) {
                HStack {
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Import")
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.podcastColor)
            .disabled(isDownloading)
        }
        .padding(8)
        .background(AppColors.cardBase)
        .cornerRadius(12)
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return String(format: "0:%02d", secs)
        }
    }
}

