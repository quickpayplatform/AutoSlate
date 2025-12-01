//
//  SegmentPreviewWindow.swift
//  SkipSlate
//
//  Created by Cursor on 12/28/25.
//

import SwiftUI
import AVFoundation
import AVKit

/// Crash-proof popup video preview window for segments
struct SegmentPreviewWindow: View {
    let segment: Segment
    let clip: MediaClip
    @ObservedObject var projectViewModel: ProjectViewModel
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var timeObserver: Any?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(clip.fileName)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    closePreview()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(AppColors.panelBackground)
            
            Divider()
            
            // Video preview area
            ZStack {
                Color.black
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.tealCircular)
                        .scaleEffect(1.5)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)
                        Text("Preview Error")
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if let player = player {
                    SegmentVideoPlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 800, height: 450)
            
            // Controls
            if let player = player, !isLoading, errorMessage == nil {
                VideoPreviewControls(player: player)
                    .padding()
                    .background(AppColors.panelBackground)
            }
        }
        .frame(width: 800, height: 600)
        .background(AppColors.cardBase)
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // CRASH-PROOF: Delay load slightly to ensure sheet is fully presented
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadPreview()
            }
        }
        .onDisappear {
            cleanup()
            // Clear previewed segment ID when preview closes
            projectViewModel.previewedSegmentID = nil
        }
        .onAppear {
            // Mark this segment as previewed when preview opens
            projectViewModel.previewedSegmentID = segment.id
        }
    }
    
    // MARK: - Crash-Proof Preview Loading
    
    private func loadPreview() {
        // CRASH-PROOF: All operations in autoreleasepool with error handling
        autoreleasepool {
            // Safety check: Validate segment and clip
            guard segment.isClip,
                  let clipID = segment.clipID,
                  clipID == clip.id,
                  segment.duration > 0.01,
                  segment.sourceStart >= 0,
                  segment.sourceEnd > segment.sourceStart else {
                Task { @MainActor in
                    isLoading = false
                    errorMessage = "Invalid segment data"
                }
                return
            }
            
            // Safety check: Validate clip URL exists
            guard FileManager.default.fileExists(atPath: clip.url.path) else {
                Task { @MainActor in
                    isLoading = false
                    errorMessage = "Video file not found"
                }
                return
            }
            
            // Load asset asynchronously with error handling
            Task { @MainActor in
                do {
                    await loadAsset()
                } catch {
                    self.isLoading = false
                    self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                    print("SkipSlate: SegmentPreview error: \(error)")
                }
            }
        }
    }
    
    @MainActor
    private func loadAsset() async {
        // CRASH-PROOF: Validate inputs before creating asset
        guard segment.duration > 0.01,
              segment.sourceStart >= 0,
              segment.sourceEnd > segment.sourceStart,
              segment.sourceEnd <= clip.duration else {
            isLoading = false
            errorMessage = "Segment time range is invalid"
            return
        }
        
        // CRASH-PROOF: Create asset with error handling
        let asset = AVURLAsset(url: clip.url)
        
        // Load asset properties safely
        do {
            // CRASH-PROOF: Validate asset can be loaded
            let duration = try await asset.load(.duration)
            guard duration.isValid && duration.seconds > 0 else {
                isLoading = false
                errorMessage = "Invalid video duration"
                return
            }
            
            // Safety check: Ensure segment times are within asset duration
            let validSourceEnd = min(segment.sourceEnd, duration.seconds)
            let validSourceStart = max(0, min(segment.sourceStart, validSourceEnd - 0.01))
            
            guard validSourceEnd > validSourceStart else {
                isLoading = false
                errorMessage = "Segment time range is invalid"
                return
            }
            
            // CRASH-PROOF: Load tracks safely
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                isLoading = false
                errorMessage = "No video track found"
                return
            }
            
            // CRASH-PROOF: Create player item with time range
            let timeRange = CMTimeRange(
                start: CMTime(seconds: validSourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: validSourceEnd - validSourceStart, preferredTimescale: 600)
            )
            
            // CRASH-PROOF: Create composition for segment
            let composition = AVMutableComposition()
            
            // Add video track safely
            if let videoTrack = tracks.first,
               let compositionVideoTrack = composition.addMutableTrack(
                   withMediaType: .video,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                do {
                    try compositionVideoTrack.insertTimeRange(
                        timeRange,
                        of: videoTrack,
                        at: .zero
                    )
                } catch {
                    isLoading = false
                    errorMessage = "Failed to create preview: \(error.localizedDescription)"
                    return
                }
            }
            
            // Add audio track if available (safely)
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks?.first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                do {
                    try compositionAudioTrack.insertTimeRange(
                        timeRange,
                        of: audioTrack,
                        at: .zero
                    )
                } catch {
                    // Audio is optional, continue without it
                    print("SkipSlate: Could not add audio track to preview: \(error)")
                }
            }
            
            // CRASH-PROOF: Create player item with composition
            let item = AVPlayerItem(asset: composition)
            
            // CRASH-PROOF: Create player with weak reference handling
            let newPlayer = AVPlayer(playerItem: item)
            
            // Cleanup previous player before assigning new one
            cleanup()
            
            self.playerItem = item
            self.player = newPlayer
            
            // CRASH-PROOF: Setup time observer safely
            setupTimeObserver(for: newPlayer)
            
            // CRASH-PROOF: Start playback
            newPlayer.play()
            
            isLoading = false
            
            print("SkipSlate: ✅ Segment preview loaded successfully")
            
        } catch {
            isLoading = false
            errorMessage = "Failed to load video: \(error.localizedDescription)"
            print("SkipSlate: SegmentPreview load error: \(error)")
        }
    }
    
    // MARK: - Crash-Proof Cleanup
    
    private func setupTimeObserver(for player: AVPlayer) {
        // CRASH-PROOF: Remove existing observer first
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // CRASH-PROOF: Create time observer with proper interval
        let interval = CMTime(value: 1, timescale: 30) // 30fps updates
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak player] time in
            // CRASH-PROOF: Weak reference to player to prevent retain cycle
            guard let player = player else {
                return
            }
            
            // Check if playback has ended (loop preview)
            if let duration = player.currentItem?.duration,
               duration.isValid,
               time >= duration {
                // Loop back to start
                player.seek(to: .zero) { _ in
                    player.play()
                }
            }
        }
    }
    
    private func closePreview() {
        cleanup()
        isPresented = false
    }
    
    private func cleanup() {
        // CRASH-PROOF: Cleanup in proper order
        autoreleasepool {
            // Remove time observer safely
            if let player = player,
               let observer = timeObserver {
                player.removeTimeObserver(observer)
                timeObserver = nil
            }
            
            // Pause and cleanup player
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            playerItem = nil
            
            isLoading = true
            errorMessage = nil
        }
        
        print("SkipSlate: SegmentPreview cleaned up")
    }
}

// MARK: - Segment Video Player View (Crash-Proof)

struct SegmentVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFrameSteppingButtons = true
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // CRASH-PROOF: Only update if player changed
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - Video Preview Controls (Crash-Proof)

struct VideoPreviewControls: View {
    @ObservedObject private var playerWrapper: PlayerWrapper
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var timeObserver: Any?
    
    init(player: AVPlayer) {
        self.playerWrapper = PlayerWrapper(player: player)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Time display
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
            }
            
            // Play/Pause button
            HStack {
                Spacer()
                
                Button(action: {
                    togglePlayback()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.tealAccent)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .onAppear {
            setupTimeObserver()
            updateDuration()
        }
        .onDisappear {
            cleanupTimeObserver()
        }
    }
    
    private func setupTimeObserver() {
        guard timeObserver == nil else { return }
        
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = playerWrapper.player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak playerWrapper] time in
            guard let playerWrapper = playerWrapper else { return }
            currentTime = CMTimeGetSeconds(time)
            isPlaying = playerWrapper.player.rate > 0
        }
    }
    
    private func cleanupTimeObserver() {
        if let observer = timeObserver {
            playerWrapper.player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func updateDuration() {
        guard let duration = playerWrapper.player.currentItem?.duration,
              duration.isValid else {
            return
        }
        self.duration = CMTimeGetSeconds(duration)
    }
    
    private func togglePlayback() {
        if playerWrapper.player.rate > 0 {
            playerWrapper.player.pause()
        } else {
            playerWrapper.player.play()
        }
        isPlaying = playerWrapper.player.rate > 0
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Player Wrapper (Crash-Proof Observable)

private class PlayerWrapper: ObservableObject {
    let player: AVPlayer
    
    init(player: AVPlayer) {
        self.player = player
    }
}

