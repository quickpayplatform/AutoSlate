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
import AppKit

struct StockSearchView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var searchQuery: String = "cinematic b-roll"
    @State private var searchResults: [StockClip] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var hasMorePages = false
    @State private var downloadingClipId: String?
    @State private var importedClipIds: Set<String> = [] // Track which stock clips have been imported
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                
                OrangeSelectionTextField(
                    placeholder: "Search stock videos...",
                    text: $searchQuery
                )
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
                .tint(AppColors.tealAccent)
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
                                isImported: importedClipIds.contains(clip.id),
                                projectViewModel: projectViewModel,
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
                        .buttonStyle(TealButtonStyle(isDisabled: false))
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
                .scrollIndicators(.hidden)
            }
            
            // Attribution footer
            HStack {
                Text("Stock videos provided by")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Link("Pexels", destination: URL(string: "https://www.pexels.com")!)
                    .font(.caption)
                    .foregroundColor(AppColors.tealAccent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
        .onAppear {
            // Perform initial search
            if searchResults.isEmpty {
                performSearch()
            }
            checkImportedClips()
        }
        .onChange(of: projectViewModel.clips.count) { _, _ in
            // Re-check imported clips when clips change
            checkImportedClips()
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
    
    private func checkImportedClips() {
        // Check if any search results match imported clips by checking filenames
        // Stock videos are saved with pattern "pexels_\(sourceId).mp4" by StockService
        for clip in searchResults {
            let clipId = clip.id
            let pexelsPattern = "pexels_\(clip.sourceId)" // Matches StockService filename pattern
            
            // Check if any imported clip's filename contains this stock clip's Pexels pattern
            let isImported = projectViewModel.clips.contains { importedClip in
                let fileName = importedClip.fileName.lowercased()
                let urlPath = importedClip.url.lastPathComponent.lowercased()
                // Check for Pexels filename pattern (e.g., "pexels_33856113")
                return fileName.contains(pexelsPattern.lowercased()) || 
                       urlPath.contains(pexelsPattern.lowercased())
            }
            if isImported {
                importedClipIds.insert(clipId)
            }
        }
    }
    
    private func importStockClip(_ clip: StockClip) {
        downloadingClipId = clip.id
        errorMessage = nil // Clear any previous errors
        
        Task {
            do {
                print("SkipSlate: StockSearchView - Starting download for clip ID: \(clip.id), URL: \(clip.downloadUrl)")
                
                // Try multiple download methods for reliability
                var localURL: URL?
                
                // Method 1: Use StockService (backend API)
                do {
                    localURL = try await StockService.shared.downloadStockVideo(from: clip)
                    print("SkipSlate: StockSearchView - Download via StockService successful")
                } catch {
                    print("SkipSlate: StockSearchView - StockService download failed: \(error), trying direct download...")
                    
                    // Method 2: Direct download from downloadUrl as fallback
                    do {
                        let (data, response) = try await URLSession.shared.data(from: clip.downloadUrl)
                        
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else {
                            throw StockServiceError.downloadFailed
                        }
                        
                        // Determine file extension
                        var fileExtension = "mp4"
                        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                            if contentType.contains("quicktime") {
                                fileExtension = "mov"
                            } else if contentType.contains("webm") {
                                fileExtension = "webm"
                            }
                        } else if !clip.downloadUrl.pathExtension.isEmpty {
                            fileExtension = clip.downloadUrl.pathExtension
                        }
                        
                        // Save to temporary file
                        let fileName = "pexels_\(clip.sourceId).\(fileExtension)"
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        try data.write(to: tempURL)
                        localURL = tempURL
                        print("SkipSlate: StockSearchView - Direct download successful")
                    } catch {
                        print("SkipSlate: StockSearchView - Direct download also failed: \(error)")
                        throw error
                    }
                }
                
                guard let finalURL = localURL else {
                    throw StockServiceError.downloadFailed
                }
                
                // Verify file exists and has content
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: finalURL.path) else {
                    throw StockServiceError.downloadFailed
                }
                
                // Check file size (should be > 0)
                if let attributes = try? fileManager.attributesOfItem(atPath: finalURL.path),
                   let fileSize = attributes[.size] as? Int64,
                   fileSize == 0 {
                    throw StockServiceError.downloadFailed
                }
                
                print("SkipSlate: StockSearchView - Download successful, importing file: \(finalURL.lastPathComponent)")
                
                // Import it using the existing import flow
                await MainActor.run {
                    projectViewModel.importMedia(urls: [finalURL])
                    // Mark this stock clip as imported
                    importedClipIds.insert(clip.id)
                    downloadingClipId = nil
                    print("SkipSlate: StockSearchView - Import completed for clip ID: \(clip.id)")
                }
            } catch {
                await MainActor.run {
                    let errorMsg = "Import failed. Try dragging the video URL or file directly onto the card."
                    errorMessage = errorMsg
                    downloadingClipId = nil
                    print("SkipSlate: ❌ StockSearchView - Import failed for clip ID: \(clip.id), error: \(error)")
                }
            }
        }
    }
}

struct StockClipCard: View {
    let clip: StockClip
    let isDownloading: Bool
    let isImported: Bool
    @ObservedObject var projectViewModel: ProjectViewModel
    let onImport: () -> Void
    
    @State private var isDragOver = false
    
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
                
                // Drag overlay
                if isDragOver {
                    ZStack {
                        Color.black.opacity(0.7)
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            Text("Drop to import")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    .cornerRadius(8)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Resolution - make it teal
                Text("\(clip.width)×\(clip.height)")
                    .font(.caption2)
                    .foregroundColor(AppColors.tealAccent)
                
                // Tags (like "cinematic b-roll") - make them teal
                if !clip.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(clip.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.tealAccent.opacity(0.2))
                                .foregroundColor(AppColors.tealAccent)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            
            // Import button - always orange, change text to "Added" with checkmark when imported
            Button(action: onImport) {
                HStack(spacing: 4) {
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else if isImported {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Added")
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
            .tint(AppColors.orangeAccent) // Always orange
            .disabled(isDownloading || isImported) // Disable if already imported
        }
        .padding(8)
        .background(AppColors.cardBase)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragOver ? AppColors.tealAccent : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL, .url], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isImported && !isDownloading else { return false }
        
        for provider in providers {
            // Try to get URL from drag - handle both file URLs and web URLs
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    guard error == nil else { 
                        print("SkipSlate: StockClipCard - Error loading file URL: \(error?.localizedDescription ?? "unknown")")
                        return 
                    }
                    
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        // It's a file URL - import directly
                        DispatchQueue.main.async {
                            print("SkipSlate: StockClipCard - Importing file from drag: \(url.lastPathComponent)")
                            projectViewModel.importMedia(urls: [url])
                        }
                    } else if let url = item as? URL {
                        DispatchQueue.main.async {
                            print("SkipSlate: StockClipCard - Importing file from drag: \(url.lastPathComponent)")
                            projectViewModel.importMedia(urls: [url])
                        }
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                // Try to get URL string - if it matches this clip's URL, download and import
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, error in
                    guard error == nil else { 
                        print("SkipSlate: StockClipCard - Error loading URL: \(error?.localizedDescription ?? "unknown")")
                        return 
                    }
                    
                    var draggedURL: URL?
                    if let url = item as? URL {
                        draggedURL = url
                    } else if let str = item as? String, let url = URL(string: str) {
                        draggedURL = url
                    }
                    
                    guard let url = draggedURL else { return }
                    
                    // Check if it's this clip's download URL or a related URL
                    let sourceIdString = String(clip.sourceId)
                    let isThisClip = url.absoluteString == clip.downloadUrl.absoluteString || 
                                    url.absoluteString.contains(sourceIdString) ||
                                    url.absoluteString == clip.thumbnailUrl.absoluteString
                    
                    if isThisClip {
                        // It's this clip - trigger the import function which will download it
                        print("SkipSlate: StockClipCard - Detected drag of clip \(clip.id) URL, triggering import")
                        DispatchQueue.main.async {
                            onImport()
                        }
                    } else {
                        // It's a different video URL - try to download and import it
                        print("SkipSlate: StockClipCard - Detected drag of video URL: \(url.absoluteString), attempting download")
                        DispatchQueue.main.async {
                            downloadAndImportVideo(from: url)
                        }
                    }
                }
                return true
            }
        }
        return false
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
                print("SkipSlate: StockClipCard - Downloading video from: \(url.absoluteString)")
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("SkipSlate: StockClipCard - Download failed: HTTP \(response)")
                    return
                }
                
                // Determine file extension
                var fileExtension = "mp4"
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    if contentType.contains("quicktime") {
                        fileExtension = "mov"
                    } else if contentType.contains("webm") {
                        fileExtension = "webm"
                    }
                } else if !url.pathExtension.isEmpty {
                    fileExtension = url.pathExtension
                }
                
                // Save to temporary file
                let fileName = "dragged_video_\(UUID().uuidString.prefix(8)).\(fileExtension)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                
                try data.write(to: tempURL)
                print("SkipSlate: StockClipCard - Downloaded video to: \(tempURL.path)")
                
                // Import the downloaded file
                await MainActor.run {
                    projectViewModel.importMedia(urls: [tempURL])
                }
            } catch {
                print("SkipSlate: StockClipCard - Error downloading video: \(error.localizedDescription)")
            }
        }
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

// MARK: - TextField with Orange Selection Color

/// Custom TextField that sets text selection color to orange
struct OrangeSelectionTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = OrangeSelectionTextFieldHelper()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.textColor = .white
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
    }
}

// Helper class to set selection color
class OrangeSelectionTextFieldHelper: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Set selection color when field becomes first responder
            DispatchQueue.main.async { [weak self] in
                self?.updateSelectionColor()
            }
        }
        return result
    }
    
    func updateSelectionColor() {
        guard let window = self.window,
              let fieldEditor = window.fieldEditor(true, for: self) as? NSTextView else {
            return
        }
        // Convert SwiftUI Color to NSColor (orange accent: #FFB347)
        let orangeColor = NSColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1.0)
        fieldEditor.insertionPointColor = orangeColor
        fieldEditor.selectedTextAttributes = [
            .backgroundColor: orangeColor,
            .foregroundColor: NSColor.white
        ]
    }
    
    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        // Update selection color when editing begins
        DispatchQueue.main.async { [weak self] in
            self?.updateSelectionColor()
        }
    }
}

