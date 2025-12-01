# Shot Quality Detection & Good vs Bad Footage Features

## Current Implementation ✅

### 1. **Frame Analysis Service** (`FrameAnalysisService`)
**Location:** `SkipSlate/Services/FrameAnalysisService.swift`

**What it does:**
- Analyzes video frames to calculate a **shot quality score** (0-1)
- Detects multiple quality factors:
  - **Face detection & framing** (40% weight)
  - **Lighting quality** (30% weight)
  - **Motion/action** (20% weight)
  - **Stability** (10% weight)
- Identifies behind-the-scenes footage (dark, no faces, unstable)

**Quality Metrics:**
```swift
struct FrameAnalysis {
    let shotQualityScore: Float // 0-1, overall quality
    let hasFace: Bool
    let framingScore: Float // 0-1, how well faces are framed
    let isStable: Bool // Not shaky
    let hasGoodLighting: Bool // Good exposure/brightness
    let hasMotion: Bool // Interesting motion/action
}
```

**How Quality Score is Calculated:**
- **Face/Framing (40%)**: If faces are present and well-centered, adds high score. If no faces but good lighting, adds moderate score. If no faces AND poor lighting, heavily penalized (likely BTS).
- **Lighting (30%)**: Analyzes brightness and contrast. Very dark shots (< 0.2) are heavily penalized.
- **Motion (20%)**: Interesting motion adds score, but excessive shaky motion reduces score.
- **Stability (10%)**: Stable shots get full score, unstable shots get very low score.
- **BTS Penalty**: If dark + no faces + unstable, score is multiplied by 0.3 (heavy penalty).

### 2. **Shot Quality Filtering** (`AutoEditService.prioritizeHighQualityShots`)
**Location:** `SkipSlate/Services/AutoEditService.swift` (lines 600-644)

**What it does:**
- Analyzes frames from video clips
- Scores each speech segment based on average quality score
- **Keeps top 80% of segments by quality** (filters out worst 20%)
- Used in **Podcast** and **Documentary** auto-edit modes

**How it works:**
```swift
// 1. Analyze frames to get quality scores
let frameAnalyses = try await frameAnalysis.analyzeFrames(...)

// 2. Score each speech segment
for speechSeg in speechSegments {
    let score = frameAnalysis.scoreTimeRange(
        start: speechSeg.startTime,
        end: speechSeg.endTime,
        analyses: frameAnalyses
    )
    scoredSegments.append((speechSeg, score))
}

// 3. Sort by score (highest first)
scoredSegments.sort { $0.score > $1.score }

// 4. Keep top 80%
let keepCount = max(1, Int(Double(scoredSegments.count) * 0.8))
let topSegments = Array(scoredSegments.prefix(keepCount))
```

### 3. **High Quality Range Detection** (`FrameAnalysisService.findHighQualityRanges`)
**Location:** `SkipSlate/Services/FrameAnalysisService.swift` (lines 554-594)

**What it does:**
- Finds continuous time ranges where quality score is above threshold (default: 0.5)
- Returns `[CMTimeRange]` of high-quality sections
- Can be used to identify "good footage" segments

**Usage:**
```swift
let highQualityRanges = frameAnalysis.findHighQualityRanges(
    analyses: frameAnalyses,
    minQualityScore: 0.5, // Minimum quality threshold
    minDuration: 0.5 // Minimum duration in seconds
)
```

### 4. **Time Range Scoring** (`FrameAnalysisService.scoreTimeRange`)
**Location:** `SkipSlate/Services/FrameAnalysisService.swift` (lines 596-617)

**What it does:**
- Scores a specific time range based on average quality
- Adds consistency bonus (low variance = stable quality)
- Returns 0-1 score for any time range

## Where It's Used

### ✅ **Currently Active:**
1. **Podcast Mode** - Filters segments by shot quality
2. **Documentary Mode** - Prioritizes high-quality shots

### ❌ **Not Currently Used:**
- **Music Video Mode** - Uses beat detection only, no quality filtering
- **Dance Video Mode** - Uses beat detection only, no quality filtering
- **Highlight Reel Mode** - Uses visual analysis but not this specific quality filtering

## Missing Features / UI Visibility ❌

### 1. **No Visual Quality Indicators**
**Status:** Not implemented

**What's needed:**
- Show quality score badges on clips in Media panel
- Color-code segments in timeline (green = high quality, red = low quality)
- Display quality metrics in Inspector panel

### 2. **No Manual Quality Filtering**
**Status:** Not implemented

**What's needed:**
- Toggle to "Show only high-quality shots"
- Quality threshold slider in Auto Edit settings
- Manual filter button in Media panel

### 3. **No Quality Preview**
**Status:** Not implemented

**What's needed:**
- Preview quality scores before auto-edit
- Show quality graph over time
- Highlight low-quality sections in timeline

### 4. **No Quality-Based Sorting**
**Status:** Not implemented

**What's needed:**
- Sort clips by quality score in Media panel
- Filter out clips below quality threshold
- Show quality distribution chart

## Files Involved

1. **`FrameAnalysisService.swift`** - Core quality analysis
   - `analyzeFrame()` - Analyzes single frame
   - `calculateQualityScore()` - Computes 0-1 quality score
   - `findHighQualityRanges()` - Finds good footage ranges
   - `scoreTimeRange()` - Scores specific time ranges

2. **`AutoEditService.swift`** - Uses quality for filtering
   - `prioritizeHighQualityShots()` - Filters segments by quality
   - Used in `autoEditPodcast()` and `autoEditDocumentary()`

3. **`HighlightReelVisualAnalyzer.swift`** - Uses quality scores for highlight reels
   - Uses `shotQualityScore` from frame analysis
   - Prioritizes high-quality moments

## How Quality Detection Works

### Step 1: Frame Sampling
- Samples frames at regular intervals (default: every 0.5 seconds)
- Limits to 300 frames max to prevent memory issues
- Extracts frames using `AVAssetImageGenerator`

### Step 2: Per-Frame Analysis
For each frame:
1. **Face Detection** (Vision framework)
   - Detects faces and calculates framing score
   - Checks if faces are centered, well-sized, not cut off

2. **Lighting Analysis** (Core Image)
   - Calculates average brightness
   - Checks for good exposure (not too dark/too bright)

3. **Motion Analysis** (Core Image)
   - Compares frame to previous frame
   - Detects interesting motion vs. shaky camera

4. **Stability Check**
   - Analyzes frame-to-frame consistency
   - Identifies shaky/handheld footage

### Step 3: Quality Score Calculation
Combines all factors with weighted scoring:
- Face/Framing: 40%
- Lighting: 30%
- Motion: 20%
- Stability: 10%
- BTS Penalty: Multiplies by 0.3 if dark + no faces + unstable

### Step 4: Range Identification
- Groups consecutive high-quality frames into time ranges
- Filters out ranges shorter than minimum duration
- Returns list of "good footage" time ranges

## Behind-the-Scenes Detection

The system specifically identifies BTS (behind-the-scenes) footage by detecting:
- **Very dark lighting** (< 0.25 score)
- **No faces present**
- **Unstable/shaky camera**

When all three are true, the quality score is heavily penalized (multiplied by 0.3), effectively filtering out BTS footage from auto-edit results.

## Summary

✅ **Shot quality detection exists** - Calculates 0-1 quality scores  
✅ **Automatically filters bad footage** - Keeps top 80% in Podcast/Documentary modes  
✅ **Detects BTS footage** - Heavily penalizes dark, no-face, unstable shots  
✅ **Works on-device** - Uses Vision framework and Core Image  
❌ **No UI visibility** - Quality scores not shown to user  
❌ **Limited to Podcast/Documentary** - Not used in Music/Dance/Highlight modes  
❌ **No manual controls** - Can't adjust quality threshold or preview scores  

The feature works automatically in the background but could be more visible and configurable in the UI.

