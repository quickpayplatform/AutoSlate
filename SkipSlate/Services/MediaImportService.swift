//
//  MediaImportService.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers
import AppKit

class MediaImportService {
    static let shared = MediaImportService()
    
    private init() {}
    
    func importMedia(from urls: [URL], existingClips: [MediaClip] = [], projectType: ProjectType? = nil) async -> [MediaClip] {
        print("SkipSlate: MediaImportService.importMedia called with \(urls.count) URLs (existing clips: \(existingClips.count), project type: \(projectType?.rawValue ?? "nil"))")
        var clips: [MediaClip] = []
        
        // First, analyze all media files
        for (index, url) in urls.enumerated() {
            print("SkipSlate: Analyzing file \(index + 1)/\(urls.count): \(url.lastPathComponent)")
            if let clip = await analyzeMediaFile(url: url) {
                clips.append(clip)
                print("SkipSlate: Successfully imported: \(clip.fileName) (type: \(clip.type), duration: \(clip.duration)s)")
            } else {
                print("SkipSlate: Failed to import: \(url.lastPathComponent)")
            }
        }
        
        // CRITICAL: Assign UNIQUE colors to each clip - NO wrapping or reuse
        // Each video/image clip gets its own unique color that all its segments will share
        // Audio-only clips use the special audio color
        
        // Collect all existing color indices to avoid conflicts
        var usedColorIndices = Set(existingClips.map { $0.colorIndex })
        
        // Calculate starting color index based on existing clips
        // For video clips, continue from where existing clips left off
        let existingVideoClips = existingClips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly || $0.type == .image }
        var nextColorIndex = existingVideoClips.count
        
        // Track video clip index separately for proper color assignment
        var videoClipIndex = 0
        
        for (index, clip) in clips.enumerated() {
            var updatedClip = clip
            
            if clip.type == .audioOnly {
                // Audio-only clips use a special reserved color index (-1 signals audio color)
                // The actual color is determined by ClipColorPalette.audioColor
                updatedClip.colorIndex = -1
                print("SkipSlate: Audio-only clip '\(clip.fileName)' uses special audio color")
            } else {
                // Video and image clips get unique sequential colors
                // Find next unused color index
                var colorIndex = nextColorIndex + videoClipIndex
                while usedColorIndices.contains(colorIndex) {
                    colorIndex += 1
                }
                
                updatedClip.colorIndex = colorIndex
                usedColorIndices.insert(colorIndex)
                videoClipIndex += 1
                
                print("SkipSlate: Assigned unique color index \(colorIndex) to clip: \(clip.fileName)")
            }
            
            clips[index] = updatedClip
        }
        
        print("SkipSlate: MediaImportService returning \(clips.count) clips with unique colors")
        return clips
    }
    
    private func analyzeMediaFile(url: URL) async -> MediaClip? {
        print("SkipSlate: Analyzing file: \(url.lastPathComponent)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("SkipSlate: File does not exist at path: \(url.path)")
            return nil
        }
        
        // Check if it's an image file first
        if let imageType = UTType(filenameExtension: url.pathExtension),
           imageType.conforms(to: .image) {
            // It's an image - treat as static video with default duration
            print("SkipSlate: Detected image file: \(url.lastPathComponent)")
            return MediaClip(
                id: UUID(),
                url: url,
                type: .image,
                duration: 3.0, // Default 3 seconds for images
                isSelected: true,
                hasAudioTrack: false  // Images never have audio
            )
        }
        
        // Try to load as video/audio asset
        let asset = AVURLAsset(url: url)
        
        // Load duration
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            print("SkipSlate: Asset duration: \(durationSeconds)s")
            
            // Determine media type - CRITICAL: Ensure tracks are actually loaded
            // First, try to load duration to ensure asset is ready
            let _ = try await asset.load(.duration)
            
            // Now load tracks
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasVideo = videoTracks.count > 0
            let hasAudio = audioTracks.count > 0
            
            print("SkipSlate: Media analysis for '\(url.lastPathComponent)':")
            print("SkipSlate:   - Video tracks: \(videoTracks.count)")
            print("SkipSlate:   - Audio tracks: \(audioTracks.count)")
            print("SkipSlate:   - Has video: \(hasVideo), has audio: \(hasAudio)")
            
            // CRITICAL: Verify audio tracks have non-zero duration
            // IMPROVED: Also check if track is playable/enabled, not just duration
            var hasValidAudio = false
            if hasAudio {
                var validAudioTrackCount = 0
                for (index, track) in audioTracks.enumerated() {
                    do {
                        // Load multiple properties to get a complete picture
                        let trackTimeRange = try await track.load(.timeRange)
                        let trackDuration = trackTimeRange.duration
                        let trackDurationSeconds = CMTimeGetSeconds(trackDuration)
                        let isEnabled = try await track.load(.isEnabled)
                        let isPlayable = try await track.load(.isPlayable)
                        
                        print("SkipSlate:   - Audio track \(index): duration=\(trackDurationSeconds)s, enabled=\(isEnabled), playable=\(isPlayable)")
                        
                        // Track is valid if:
                        // 1. Duration is valid and > 0, OR
                        // 2. Track is enabled and playable (even if duration check fails, track might still work)
                        let hasValidDuration = trackDuration.isValid && trackDurationSeconds > 0
                        let isTrackUsable = isEnabled && isPlayable
                        
                        if hasValidDuration || (isTrackUsable && audioTracks.count > 0) {
                            // If duration is invalid but track is playable, use asset duration as fallback
                            if !hasValidDuration && isTrackUsable {
                                print("SkipSlate:   - ⚠ Audio track \(index) has invalid duration but is playable - using asset duration as fallback")
                                // We'll still mark it as valid and let AVFoundation handle it
                            }
                            validAudioTrackCount += 1
                            hasValidAudio = true
                            print("SkipSlate:   - ✓ Audio track \(index) is VALID")
                        } else {
                            print("SkipSlate:   - ⚠ WARNING: Audio track \(index) appears invalid (duration=\(trackDurationSeconds)s, enabled=\(isEnabled), playable=\(isPlayable))")
                        }
                    } catch {
                        print("SkipSlate:   - ⚠ ERROR loading audio track \(index) properties: \(error)")
                        // If we can't load properties but track exists, assume it might be valid
                        // Some codecs/containers may not expose all properties immediately
                        print("SkipSlate:   - Attempting to use track anyway (may be valid but properties not yet loaded)")
                        validAudioTrackCount += 1
                        hasValidAudio = true
                    }
                }
                
                if hasAudio && !hasValidAudio {
                    print("SkipSlate:   - ⚠⚠⚠ CRITICAL: Asset has \(audioTracks.count) audio track(s) but ALL appear invalid!")
                    print("SkipSlate:   - However, will still mark as hasAudioTrack=true to allow fallback attempt in composition")
                    // FALLBACK: Even if all tracks appear invalid, mark as having audio
                    // This allows PlayerViewModel to attempt loading them anyway
                    hasValidAudio = true
                    print("SkipSlate:   - Using fallback: marking as hasAudioTrack=true to allow composition to try loading")
                } else {
                    print("SkipSlate:   - ✓ Found \(validAudioTrackCount) valid audio track(s) out of \(audioTracks.count) total")
                }
            }
            
            let mediaType: MediaClipType
            if hasVideo && hasValidAudio {
                mediaType = .videoWithAudio
                print("SkipSlate: ✓ Detected as videoWithAudio (has valid audio)")
            } else if hasVideo {
                mediaType = .videoOnly
                print("SkipSlate: ⚠ Detected as videoOnly (no valid audio tracks found)")
            } else if hasValidAudio {
                mediaType = .audioOnly
                print("SkipSlate: ✓ Detected as audioOnly (has valid audio)")
            } else if !hasVideo && hasAudio {
                // CRITICAL: For audio-only files, be more lenient
                // Even if audio tracks appear invalid, if they exist, treat as audioOnly
                // This is important for Highlight Reel which requires music tracks
                print("SkipSlate: ⚠ File has no video but has audio tracks (even if invalid)")
                print("SkipSlate: ⚠ Treating as audioOnly to allow Highlight Reel to use it")
                mediaType = .audioOnly
                hasValidAudio = true // Force to true so it can be used
            } else {
                // Skip files with no video or audio at all
                print("SkipSlate: ✗ File has no video or audio tracks, skipping")
                return nil
            }
            
            let clip = MediaClip(
                id: UUID(),
                url: url,
                type: mediaType,
                duration: durationSeconds,
                isSelected: true,
                hasAudioTrack: hasValidAudio  // Only true if audio tracks have non-zero duration
            )
            
            print("SkipSlate: Created clip: \(clip.fileName)")
            print("SkipSlate:   - Type: \(mediaType)")
            print("SkipSlate:   - Duration: \(durationSeconds)s")
            print("SkipSlate:   - hasAudioTrack: \(hasValidAudio) (audio tracks: \(audioTracks.count), valid: \(hasValidAudio ? "yes" : "no"))")
            return clip
        } catch {
            print("SkipSlate: Error analyzing media file \(url.lastPathComponent): \(error)")
            print("SkipSlate: Error details: \(error.localizedDescription)")
            return nil
        }
    }
}

