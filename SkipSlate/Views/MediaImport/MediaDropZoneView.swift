
//  MediaDropZoneView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Media Import UI - Drop Zone Component
//  - Handles drag & drop and file browser for media import
//  - Completely independent of preview/playback
//  - Only communicates with ProjectViewModel.importMedia()
//  - Can be restyled without affecting video preview
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MediaDropZoneView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var isDragOver = false
    
    var body: some View {
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
        
        print("SkipSlate: MediaDropZoneView - Opening file picker")
        
        // Use async/await for modern macOS
        if let window = NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    print("SkipSlate: MediaDropZoneView - User selected \(panel.urls.count) file(s)")
                    self.projectViewModel.importMedia(urls: panel.urls)
                } else {
                    print("SkipSlate: MediaDropZoneView - User cancelled file picker")
                }
            }
        } else {
            // Fallback to runModal if no window available
            let response = panel.runModal()
            if response == .OK {
                print("SkipSlate: MediaDropZoneView - User selected \(panel.urls.count) file(s) (fallback)")
                projectViewModel.importMedia(urls: panel.urls)
            } else {
                print("SkipSlate: MediaDropZoneView - User cancelled file picker (fallback)")
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        print("SkipSlate: MediaDropZoneView - handleDrop called with \(providers.count) providers")
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
            print("SkipSlate: MediaDropZoneView - Drop completed, loaded \(loadedURLs.count) URLs")
            if !loadedURLs.isEmpty {
                self.projectViewModel.importMedia(urls: loadedURLs)
            } else {
                print("SkipSlate: MediaDropZoneView - No URLs loaded from drop")
            }
        }
        
        return true
    }
}
