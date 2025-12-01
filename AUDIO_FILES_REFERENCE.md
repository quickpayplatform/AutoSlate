# Audio Playback Files Reference

This document lists all files involved in audio playback in SkipSlate, to help with debugging audio issues.

## Core Audio Files

### 1. **PlayerViewModel.swift**
**Location:** `SkipSlate/ViewModels/PlayerViewModel.swift`
**Purpose:** Main player controller that manages AVPlayer and applies audio mix
**Key Methods:**
- `buildComposition()` - Inserts audio tracks into AVMutableComposition
- `updatePlayer()` - Applies audioMix to AVPlayerItem
- `createAudioMixWithTransitions()` - Creates audio mix with crossfades
- `play()` - Starts playback (sets volume to 1.0, unmutes)

**Key Properties:**
- `player: AVPlayer?` - The main player instance
- `playerItem: AVPlayerItem?` - The current item being played
- `currentAudioSettings: AudioSettings` - Current audio processing settings

### 2. **TransitionService.swift**
**Location:** `SkipSlate/Services/TransitionService.swift`
**Purpose:** Creates audio mix with crossfade transitions between segments
**Key Method:**
- `createAudioMixWithTransitions(for:segments:)` - Creates AVAudioMix with volume ramps for transitions

**Important:** Sets default volume to 1.0 at time zero to ensure audio plays even without transitions.

### 3. **AudioService.swift**
**Location:** `SkipSlate/Services/AudioService.swift`
**Purpose:** Applies audio processing (gain, noise reduction, compression)
**Key Method:**
- `createAudioMix(for:settings:)` - Creates AVAudioMix with master gain applied

### 4. **PreviewPanel.swift**
**Location:** `SkipSlate/Views/PreviewPanel.swift`
**Purpose:** UI component that displays the video player
**Key Components:**
- `VideoPlayerView` - NSViewRepresentable wrapper for PlayerHostingView
- `TransportControls` - Play/pause controls and time display

### 5. **PlayerHostingView.swift**
**Location:** `SkipSlate/Views/PlayerHostingView.swift`
**Purpose:** NSView subclass that hosts AVPlayerLayer
**Key Properties:**
- `playerLayer: AVPlayerLayer` - The layer that renders video/audio

## Audio Flow

1. **Composition Building** (`PlayerViewModel.buildComposition()`):
   - Creates `AVMutableComposition`
   - Adds audio track: `composition.addMutableTrack(withMediaType: .audio)`
   - For each segment, inserts audio time ranges: `audioTrack.insertTimeRange(...)`

2. **Audio Mix Creation** (`PlayerViewModel.updatePlayer()`):
   - First tries: `TransitionService.createAudioMixWithTransitions()` (with crossfades)
   - Falls back to: `AudioService.createAudioMix()` (with gain/processing)
   - Applies to: `playerItem.audioMix = audioMix`

3. **Player Setup** (`PlayerViewModel.updatePlayer()`):
   - Sets `player.volume = 1.0`
   - Sets `player.isMuted = false`
   - Replaces item: `player.replaceCurrentItem(with: playerItem)`

4. **Playback** (`PlayerViewModel.play()`):
   - Verifies `player.currentItem != nil`
   - Sets volume and unmutes again (safety)
   - Calls `player.play()`

## Common Issues & Debugging

### Issue: No Audio Playing
**Check:**
1. Are audio tracks inserted? (Log: "Composition has X audio track(s)")
2. Is audioMix applied? (Log: "Applied audio mix with transitions" or "Applied audio mix from AudioService")
3. Is player volume > 0? (Log: "volume: 1.0, muted: false")
4. Does source clip have audio? (Check MediaClip.type - should be `.videoWithAudio` or `.audioOnly`)

### Issue: Audio Cuts Out
**Check:**
1. Are volume ramps overlapping? (TransitionService should prevent overlaps)
2. Are segments enabled? (Only enabled segments have audio inserted)
3. Is composition duration correct? (Audio tracks must match video duration)

### Issue: Audio Out of Sync
**Check:**
1. Are audio time ranges correct? (`segment.sourceStart` and `segment.duration`)
2. Are audio tracks inserted at correct composition times? (`currentTime` in `buildComposition`)

## Debug Logging

The code includes extensive logging. Look for:
- `"SkipSlate: Composition has X audio track(s)"` - Confirms tracks exist
- `"SkipSlate: Successfully inserted audio segment"` - Confirms insertion
- `"SkipSlate: Applied audio mix with transitions"` - Confirms mix applied
- `"SkipSlate: Player started, volume: X, muted: Y"` - Confirms player state

## Related Models

### AudioSettings.swift
**Location:** `SkipSlate/Models/AudioSettings.swift`
**Purpose:** Stores audio processing preferences (gain, noise reduction, compression)

### MediaClip.swift
**Location:** `SkipSlate/Models/MediaClip.swift`
**Purpose:** Represents imported media files
**Key Property:** `type: MediaClipType` - Indicates if clip has audio (`.videoWithAudio`, `.audioOnly`)

### Segment.swift
**Location:** `SkipSlate/Models/Segment.swift`
**Purpose:** Represents a segment of a clip in the timeline
**Key Properties:**
- `sourceStart: Double` - Start time in source clip
- `duration: Double` - Duration of segment
- `enabled: Bool` - Whether segment is included in composition

