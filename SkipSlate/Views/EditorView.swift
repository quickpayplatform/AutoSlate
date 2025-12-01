//
//  EditorView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var isDragOver = false
    @State private var showImportToast = false
    @State private var importToastMessage = ""
    @State private var previousClipCount = 0
    @State private var timelineHeight: CGFloat = 200  // Height of timeline panel
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top toolbar
                EditorToolbar(projectViewModel: projectViewModel)
                
                // Main content area with resizable timeline
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top: Preview and Inspector
                        HStack(spacing: 0) {
                            // Left: Preview
                            PreviewPanel(projectViewModel: projectViewModel)
                                .frame(width: 600)
                            
                            Divider()
                            
                            // Right: Inspector
                            InspectorPanel(projectViewModel: projectViewModel)
                                .frame(width: 300)
                        }
                        .frame(height: max(400, geometry.size.height - timelineHeight))
                        
                        // Resize handle between preview and timeline
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(height: 4)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.resizeUpDown.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let delta = -value.translation.height
                                        let newHeight = max(150, min(geometry.size.height - 400, timelineHeight + delta))
                                        timelineHeight = newHeight
                                    }
                            )
                        
                        // Bottom: Timeline
                        TimelineView(projectViewModel: projectViewModel)
                            .frame(height: timelineHeight)
                    }
                }
            }
            .background(AppColors.background)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }
            .onChange(of: projectViewModel.clips.count) { oldValue, newValue in
                // Show toast when new clips are added
                if newValue > oldValue {
                    let count = newValue - oldValue
                    showImportToast(message: "Imported \(count) file\(count == 1 ? "" : "s") into this project")
                }
            }
            
            // Drag overlay
            if isDragOver && projectViewModel.clips.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.podcastColor, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppColors.podcastColor.opacity(0.1))
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 48))
                                .foregroundColor(AppColors.podcastColor)
                            Text("Drag & drop video or audio files here")
                                .font(.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("or click 'Import Media' above")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    )
                    .padding(40)
                    .animation(.spring(), value: isDragOver)
            }
            
            // Empty state drop zone
            if projectViewModel.clips.isEmpty && !isDragOver {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.secondaryText.opacity(0.5))
                    Text("Drag & drop video or audio files here")
                        .font(.headline)
                        .foregroundColor(AppColors.secondaryText)
                    Text("or click 'Import Media' above")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Toast notification
            if showImportToast {
                VStack {
                    Spacer()
                    HStack {
                        Text(importToastMessage)
                            .font(.subheadline)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(AppColors.panelBackground)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    }
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var loadedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("Error loading item: \(error)")
                        return
                    }
                    
                    if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            loadedURLs.append(url)
                        }
                    } else if let url = item as? URL {
                        loadedURLs.append(url)
                    } else if let str = item as? String, let url = URL(string: str) {
                        loadedURLs.append(url)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            if !loadedURLs.isEmpty {
                projectViewModel.importMedia(urls: loadedURLs)
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

struct EditorToolbar: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        HStack {
            TextField("Project Name", text: Binding(
                get: { projectViewModel.projectName },
                set: { projectViewModel.projectName = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            
            Spacer()
            
            Button("Import Media") {
                importMedia()
            }
            .buttonStyle(.bordered)
            
            Button("Auto Edit") {
                projectViewModel.runAutoEdit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(projectViewModel.clips.isEmpty || projectViewModel.isAutoEditing)
            
            if projectViewModel.isAutoEditing {
                ProgressView()
                    .progressViewStyle(.tealCircular)
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text(projectViewModel.autoEditStatus)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button("Export") {
                exportMedia()
            }
            .buttonStyle(.bordered)
            .disabled(projectViewModel.segments.isEmpty || projectViewModel.isExporting)
            
            if projectViewModel.isExporting {
                ProgressView(value: projectViewModel.exportProgress)
                    .frame(width: 100)
            }
        }
        .padding()
        .background(AppColors.panelBackground)
    }
    
    private func importMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .audio,
            .mp3,
            .wav,
            .image,  // Photos/images
            .jpeg,
            .png,
            .gif,
            .tiff,
            .heic,
            .heif
        ]
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                projectViewModel.importMedia(urls: urls)
            }
        }
    }
    
    private func exportMedia() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(projectViewModel.projectName).mp4"
        
        if panel.runModal() == .OK, let url = panel.url {
            projectViewModel.export(to: url, format: .mp4)
        }
    }
}

