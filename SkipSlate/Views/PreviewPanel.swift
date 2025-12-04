//
//  PreviewPanel.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Preview/Playback UI
//  - Displays video preview using PlayerViewModel's AVPlayer
//  - Observes PlayerViewModel for playback state (isPlaying, currentTime, duration)
//  - Does NOT modify project data or segments
//  - Does NOT know about media import or timeline editing logic
//  - Communication: PreviewPanel → observes projectViewModel.playerVM → displays playback
//

import SwiftUI
import AVKit
import AVFoundation

struct PreviewPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    // CRITICAL: Also observe PlayerViewModel directly to ensure updates when composition changes
    // This ensures the preview updates correctly after auto-edit completes and composition is rebuilt
    @ObservedObject private var playerViewModel: PlayerViewModel
    
    init(projectViewModel: ProjectViewModel) {
        self.projectViewModel = projectViewModel
        // Access playerVM to ensure it exists and observe it for changes
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Video preview - use the shared player directly
            GeometryReader { geometry in
                // CRITICAL: Show black if no segments exist (nothing to preview)
                // Only show the video player if there are segments AND the player is ready
                let hasSegments = !projectViewModel.segments.isEmpty
                
                if hasSegments, let player = playerViewModel.player, playerViewModel.duration > 0 {
                    VideoPlayerView(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.black)
                } else {
                    // No segments = pure black screen with no text
                    // This represents "nothing on the timeline = nothing in preview"
                    Color.black
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            
            // Transport controls - only show if there are segments
            if !projectViewModel.segments.isEmpty {
                TransportControls(playerViewModel: playerViewModel)
                    .padding()
                    .background(AppColors.panelBackground)
            }
        }
    }
}

/// Minimal preview container that uses the shared player from ViewModel
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> PlayerHostingView {
        let hostingView = PlayerHostingView()
        
        // Add double-click gesture for play/pause
        let doubleClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick))
        doubleClickGesture.numberOfClicksRequired = 2
        hostingView.addGestureRecognizer(doubleClickGesture)
        
        context.coordinator.hostingView = hostingView
        
        // Set player immediately - this is the ONLY player instance
        hostingView.playerLayer.player = player
        print("SkipSlate: VideoPlayerView - Set player on PlayerHostingView")
        
        return hostingView
    }
    
    func updateNSView(_ nsView: PlayerHostingView, context: Context) {
        // Always ensure the player is set (in case it was nil before)
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
            print("SkipSlate: VideoPlayerView - Updated player on PlayerHostingView")
        }
        context.coordinator.hostingView = nsView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var hostingView: PlayerHostingView?
        
        @objc func handleDoubleClick() {
            if let view = hostingView, let player = view.playerLayer.player {
                if player.rate > 0 {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }
    }
}

struct TransportControls: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Timeline scrubber
            HStack {
                Text(timeString(from: playerViewModel.currentTime))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 60, alignment: .trailing)
                
                Slider(
                    value: Binding(
                        get: { playerViewModel.currentTime },
                        set: { newValue in
                            // Pause during scrubbing for better UX
                            let wasPlaying = playerViewModel.isPlaying
                            if wasPlaying {
                                playerViewModel.pause()
                            }
                            // Seek with small tolerance for snappy response
                            playerViewModel.seek(to: newValue)
                        }
                    ),
                    in: 0...max(playerViewModel.duration, 1.0)
                )
                .tint(AppColors.tealAccent)
                
                Text(timeString(from: playerViewModel.duration))
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 60, alignment: .leading)
            }
            
            // Play/Pause button
            HStack {
                Spacer()
                
                Button(action: {
                    if playerViewModel.isPlaying {
                        playerViewModel.pause()
                    } else {
                        playerViewModel.play()
                    }
                }) {
                    Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.primaryText)
                        .frame(width: 40, height: 40)
                        .background(AppColors.orangeAccent)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

