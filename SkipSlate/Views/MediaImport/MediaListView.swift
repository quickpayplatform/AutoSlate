//
//  MediaListView.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/2/25.
//
//  MODULE: Media Import UI - Media List Component
//  - Displays list of imported media clips
//  - Completely independent of preview/playback
//  - Only displays project.clips data
//  - Can be restyled without affecting video preview
//

import SwiftUI

struct MediaListView: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
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
        // Use ProjectViewModel's proper method if available, otherwise direct modification
        // NOTE: This should ideally go through a ProjectViewModel method to ensure proper state management
        var updatedProject = projectViewModel.project
        updatedProject.clips.removeAll { $0.id == clip.id }
        // CRITICAL: Only update project, do NOT trigger composition rebuild
        // Composition rebuild should only happen when segments change, not when clips change
        projectViewModel.project = updatedProject
    }
}
