# Music Beat Detection & BPM Features

## Current Implementation ✅

### 1. **Beat Detection** (`AudioAnalysisEngine.detectBeatPeaks`)
**Location:** `SkipSlate/Services/AudioAnalysisEngine.swift`

**What it does:**
- Analyzes audio envelope (RMS energy over time)
- Detects beat peaks using energy deviation from smoothed average
- Returns array of beat times in seconds

**How it works:**
- Builds amplitude envelope from audio track
- Computes moving average for smoothing
- Finds energy deviations (peaks above baseline)
- Filters peaks by sensitivity threshold and minimum spacing
- Returns beat times where cuts should occur

**Used in:**
- Music Video auto-edit mode
- Dance Video auto-edit mode  
- Highlight Reel auto-edit mode

### 2. **Beat-Synced Cuts** (`AutoEditService`)
**Location:** `SkipSlate/Services/AutoEditService.swift`

**What it does:**
- Matches video cuts to detected beat times
- Creates segments that align with music beats
- Alternates between video clips and images at beat points

**Example:**
```swift
// Detects beats from music track
let beatPeaks = audioEngine.detectBeatPeaks(...)

// Creates cuts at each beat
for peak in beatPeaks {
    // Create segment ending at this beat
    let segment = Segment(...)
    segments.append(segment)
}
```

### 3. **Music Analysis for Highlight Reels** (`HighlightReelMusicAnalyzer`)
**Location:** `SkipSlate/Services/HighlightReelMusicAnalyzer.swift`

**What it does:**
- Detects beats with higher precision (10ms frames)
- Identifies music sections (intro, verse, chorus, etc.)
- Builds energy curve to find climax zones
- Matches visual moments to music energy

## Missing Features ❌

### 1. **BPM (Beats Per Minute) Calculation**
**Status:** Not implemented

**What's needed:**
- Calculate average time between beats
- Convert to BPM: `BPM = 60 / averageBeatInterval`
- Display BPM in UI
- Use BPM to validate beat detection accuracy

### 2. **BPM-Based Beat Grid**
**Status:** Not implemented

**What's needed:**
- If BPM is known, create regular beat grid
- Snap detected beats to grid
- Fill in missing beats based on BPM
- More accurate than pure energy-based detection

### 3. **Music Identification**
**Status:** Not implemented

**What's needed:**
- Detect if audio is music vs. speech
- Identify tempo characteristics
- Classify music genre (affects beat detection parameters)

## Files Involved

1. **`AudioAnalysisEngine.swift`** - Core beat detection algorithm
2. **`AutoEditService.swift`** - Uses beats to create cuts
3. **`HighlightReelMusicAnalyzer.swift`** - Advanced music analysis
4. **`AutoEditSettings.swift`** - Beat detection parameters (sensitivity, spacing)

## How to Add BPM Detection

To add BPM calculation, you would:

1. **Add BPM calculation to `AudioAnalysisEngine`:**
```swift
func calculateBPM(from beatTimes: [Double]) -> Double? {
    guard beatTimes.count >= 2 else { return nil }
    
    // Calculate intervals between beats
    var intervals: [Double] = []
    for i in 1..<beatTimes.count {
        intervals.append(beatTimes[i] - beatTimes[i - 1])
    }
    
    // Use median interval (more robust than mean)
    let sortedIntervals = intervals.sorted()
    let medianInterval = sortedIntervals[sortedIntervals.count / 2]
    
    // Convert to BPM
    return 60.0 / medianInterval
}
```

2. **Add BPM to music analysis results**
3. **Display BPM in UI** (Audio editing screen)
4. **Use BPM to improve beat detection** (create beat grid)

## Current Beat Detection Parameters

- **Min Beat Spacing:** 0.15-0.25 seconds (prevents too-frequent beats)
- **Sensitivity:** 0.6-0.8 (higher = more beats detected)
- **Frame Duration:** 0.02 seconds (20ms) for standard, 0.01 seconds (10ms) for highlight reels

## Summary

✅ **Beat detection exists** - cuts are matched to music beats  
✅ **Works for Music Video, Dance Video, and Highlight Reel modes**  
❌ **BPM calculation not implemented** - would improve accuracy  
❌ **No beat grid** - relies purely on energy-based detection  

The current implementation works well for most music, but adding BPM would make it more accurate and allow for beat grid snapping.

