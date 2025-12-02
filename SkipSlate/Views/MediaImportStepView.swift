//
//  MediaImportStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  DESIGN RULE: Media Import Module
//  - This view ONLY manages importing media files and adding them to project.clips
//  - It MUST NOT access PlayerViewModel, AVPlayer, or AVMutableComposition
//  - It communicates with ProjectViewModel via: projectViewModel.importMedia(urls:)
//  - Composition rebuild happens automatically when segments are created (during auto-edit)
//  - This ensures media import UI changes don't break video preview
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MediaImportStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var isDragOver = false
    @State private var showImportToast = false
    @State private var importToastMessage = ""
    @State private var selectedTab: ImportTab = .myMedia
    
    var body: some View {
        VStack(spacing: 0) {
            // App Logo in top-left
            HStack {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .compositingGroup()
                    .padding(.leading, 20)
                    .padding(.top, 12)
                Spacer()
            }
            
            // Step indicator
            GlobalStepIndicator(currentStep: .media)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 30) {
                    // Title
                    VStack(spacing: 12) {
                        Text("Import your media")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Add video and audio files Auto Slate will use to build your edit.")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.top, 40)
                    
                    // Tab selector
                    HStack(spacing: 0) {
                        TabButton(
                            title: "My Media",
                            isSelected: selectedTab == .myMedia,
                            action: { selectedTab = .myMedia }
                        )
                        
                        TabButton(
                            title: "Stock",
                            isSelected: selectedTab == .stock,
                            action: { selectedTab = .stock }
                        )
                        
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                    
                    // Main content area
                    if selectedTab == .myMedia {
                        HStack(spacing: 30) {
                            // Left: Drop zone
                            dropZoneView
                                .frame(maxWidth: .infinity)
                            
                            // Right: Media list
                            mediaListView
                                .frame(width: 350)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    } else {
                        // Stock search view
                        StockSearchView(projectViewModel: projectViewModel)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                    }
                }
            }
            .background(AppColors.background)
            
            Divider()
            
            // Navigation
            HStack {
                Button("Back") {
                    appViewModel.previousStep()
                }
                .buttonStyle(.bordered)
                .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Button("Next") {
                    appViewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectViewModel.clips.isEmpty)
                .tint(projectViewModel.clips.isEmpty ? .gray : AppColors.podcastColor)
            }
            .padding(30)
            .background(AppColors.panelBackground)
        }
        .background(AppColors.background)
        .onChange(of: projectViewModel.clips.count) { oldValue, newValue in
            if newValue > oldValue {
                let count = newValue - oldValue
                showImportToast(message: "Imported \(count) file\(count == 1 ? "" : "s")")
            }
        }
    }
    
    private var dropZoneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 64))
                .foregroundColor(isDragOver ? AppColors.podcastColor : AppColors.secondaryText.opacity(0.5))
            
            Text("Drag & drop media files here")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)
            
            Text("or click 'Browse…' to select from your Mac")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
            
            Button("Browse…") {
                importMedia()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.podcastColor)
            .padding(.top, 8)
            
            Text("Supported: MOV, MP4, BRAW, R3D, WAV, MP3, M4A, etc.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText.opacity(0.7))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDragOver ? AppColors.podcastColor.opacity(0.1) : AppColors.cardBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isDragOver ? AppColors.podcastColor : AppColors.secondaryText.opacity(0.2),
                            style: StrokeStyle(lineWidth: isDragOver ? 3 : 2, dash: [10, 5])
                        )
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var mediaListView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Imported Media")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)
            
            if projectViewModel.clips.isEmpty {
                VStack(spacing: 12) {
                    Text("No media yet")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.subheadline)
                    
                    Text("Drag files into the drop zone or click Browse…")
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(projectViewModel.clips) { clip in
                            MediaImportItemRow(clip: clip, projectViewModel: projectViewModel)
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppColors.cardBase)
        .cornerRadius(12)
    }
    
    private func importMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie,
            .audio, .mp3, .wav,
            .image, .jpeg, .png, .gif, .tiff, .heic, .heif
        ]
        
        print("SkipSlate: MediaImportStepView - Opening file picker")
        
        // Use async/await for modern macOS
        if let window = NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    print("SkipSlate: MediaImportStepView - User selected \(panel.urls.count) file(s)")
                    self.projectViewModel.importMedia(urls: panel.urls)
                } else {
                    print("SkipSlate: MediaImportStepView - User cancelled file picker")
                }
            }
        } else {
            // Fallback to runModal if no window available
            let response = panel.runModal()
            if response == .OK {
                print("SkipSlate: MediaImportStepView - User selected \(panel.urls.count) file(s) (fallback)")
                projectViewModel.importMedia(urls: panel.urls)
            } else {
                print("SkipSlate: MediaImportStepView - User cancelled file picker (fallback)")
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("SkipSlate: MediaImportStepView - handleDrop called with \(providers.count) providers")
        var loadedURLs: [URL] = []
        let group = DispatchGroup()
        
        for (index, provider) in providers.enumerated() {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("SkipSlate: Error loading item \(index): \(error)")
                        return
                    }
                    
                    if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            print("SkipSlate: Loaded URL from data: \(url.lastPathComponent)")
                            loadedURLs.append(url)
                        }
                    } else if let url = item as? URL {
                        print("SkipSlate: Loaded URL directly: \(url.lastPathComponent)")
                        loadedURLs.append(url)
                    } else if let str = item as? String, let url = URL(string: str) {
                        print("SkipSlate: Loaded URL from string: \(url.lastPathComponent)")
                        loadedURLs.append(url)
                    } else {
                        print("SkipSlate: Could not extract URL from item \(index), type: \(type(of: item))")
                    }
                }
            } else {
                print("SkipSlate: Provider \(index) does not conform to public.file-url")
            }
        }
        
        group.notify(queue: .main) {
            print("SkipSlate: MediaImportStepView - Drop completed, loaded \(loadedURLs.count) URLs")
            if !loadedURLs.isEmpty {
                self.projectViewModel.importMedia(urls: loadedURLs)
            } else {
                print("SkipSlate: MediaImportStepView - No URLs loaded from drop")
            }
        }
        
        return true
    }
    
    private func showImportToast(message: String) {
        importToastMessage = message
        showImportToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showImportToast = false
            }
        }
    }
}

struct MediaImportItemRow: View {
    let clip: MediaClip
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(AppColors.podcastColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.fileName)
                    .font(.caption)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                HStack {
                    Text("\(timeString(from: clip.duration))")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(typeString)
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            Spacer()
            
            Button(action: {
                removeClip(clip)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(AppColors.panelBackground)
        .cornerRadius(8)
    }
    
    private var iconName: String {
        switch clip.type {
        case .videoWithAudio, .videoOnly:
            return "video.fill"
        case .audioOnly:
            return "waveform"
        case .image:
            return "photo.fill"
        }
    }
    
    private var typeString: String {
        switch clip.type {
        case .videoWithAudio: return "Video+Audio"
        case .videoOnly: return "Video"
        case .audioOnly: return "Audio"
        case .image: return "Image"
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func removeClip(_ clip: MediaClip) {
        var updatedProject = projectViewModel.project
        updatedProject.clips.removeAll { $0.id == clip.id }
        projectViewModel.project = updatedProject
    }
}

// MARK: - Import Tab

enum ImportTab {
    case myMedia
    case stock
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(isSelected ? AppColors.podcastColor.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stock Search View

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

// MARK: - Stock Clip Card

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

