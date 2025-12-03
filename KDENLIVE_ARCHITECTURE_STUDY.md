# Kdenlive Architecture Study & AutoSlate Improvement Plan

## Overview

This document analyzes Kdenlive's architecture (a professional open-source NLE) and outlines improvements for AutoSlate's timeline system.

---

## Part 1: Kdenlive Architecture Analysis

### 1.1 Core Architecture Pattern: Model-View-Controller Separation

Kdenlive uses a strict **Model-View-Controller (MVC)** architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                         UI LAYER                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  Timeline   │  │   Monitor   │  │    Bin (Media)      │ │
│  │    View     │  │    View     │  │      View           │ │
│  └──────┬──────┘  └──────┬──────┘  └─────────┬───────────┘ │
└─────────┼────────────────┼───────────────────┼─────────────┘
          │                │                   │
          ▼                ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                      MODEL LAYER                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ TimelineModel│ │ MonitorModel│  │    BinModel         │ │
│  │  - tracks[] │  │  - playhead │  │    - clips[]        │ │
│  │  - clips[]  │  │  - duration │  │    - folders[]      │ │
│  └──────┬──────┘  └──────┬──────┘  └─────────┬───────────┘ │
└─────────┼────────────────┼───────────────────┼─────────────┘
          │                │                   │
          └────────────────┼───────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    MLT ENGINE LAYER                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              MLT Framework (libmlt)                  │   │
│  │  - Producer (video/audio sources)                    │   │
│  │  - Tractor (timeline composition)                    │   │
│  │  - Consumer (output to monitor/export)               │   │
│  │  - Filters (effects, transitions)                    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Key Architectural Concepts

#### A. The "Bin" vs "Timeline" Separation

**Kdenlive's Approach:**
- **Bin** = Source media library (clips exist here independently)
- **Timeline** = Arrangement of clip *references* (not copies)
- A clip in the timeline is just a pointer to the bin clip with in/out points

**Why This Matters:**
- Same source can be used multiple times without duplicating data
- Changes to source affect all instances
- Clear separation of "what media exists" vs "how it's arranged"

#### B. Timeline Model Architecture

```cpp
// Kdenlive's model hierarchy (simplified)
class TimelineModel {
    QVector<TrackModel*> tracks;      // All tracks
    std::unordered_map<int, ClipModel*> clips;  // Clip ID -> Clip
    
    // Core operations
    void requestClipMove(clipId, trackId, position);
    void requestClipInsert(clipId, trackId, position);
    void requestClipResize(clipId, size, fromRight);
}

class TrackModel {
    int trackId;
    TrackType type;  // Video or Audio
    bool isMuted;
    bool isLocked;
    QVector<int> clipIds;  // Just IDs, not actual clips
}

class ClipModel {
    int clipId;
    QString binClipId;  // Reference to source in bin
    int position;       // Position on timeline (frames)
    int inPoint;        // Start point in source
    int outPoint;       // End point in source
    QVector<EffectModel*> effects;
}
```

#### C. The MLT "Tractor" Pattern

MLT uses a "tractor" metaphor for timeline composition:

```
Tractor (Timeline)
├── Multitrack
│   ├── Playlist (Track V3) ─── Producer(clip) ─── Producer(clip)
│   ├── Playlist (Track V2) ─── Producer(clip)
│   ├── Playlist (Track V1) ─── Producer(clip) ─── Producer(clip)
│   ├── Playlist (Track A1) ─── Producer(audio)
│   └── Playlist (Track A2) ─── Producer(audio) ─── Producer(audio)
├── Transitions (between tracks)
└── Filters (global effects)
```

**Key Insight:** The MLT Tractor ONLY rebuilds when structure changes, not during playback. Playback just reads from the pre-built composition.

### 1.3 Monitor/Preview System

```
┌─────────────────────────────────────────────────────────────┐
│                    PREVIEW PIPELINE                         │
│                                                             │
│  Timeline Position ──► MLT Tractor ──► Frame Request        │
│                                              │               │
│                                              ▼               │
│                                        MLT Consumer         │
│                                              │               │
│                                              ▼               │
│                                     Video Frame Buffer      │
│                                              │               │
│                                              ▼               │
│                                      QML/Qt Display         │
└─────────────────────────────────────────────────────────────┘
```

**Critical Pattern: Decoupled Playback**
- The monitor requests frames from MLT at playback speed
- Timeline UI changes DON'T interrupt playback
- Only "significant" changes (clip position, trim) rebuild the tractor

### 1.4 Tool System

Kdenlive's tools are **state-based, not action-based**:

```cpp
enum ToolType {
    SelectTool,      // Select/move clips
    RazorTool,       // Cut clips
    SpacerTool,      // Move everything after cursor
    SlipTool,        // Slip clip content
    SlideTool,       // Slide clip position
    RippleTool,      // Ripple edit
    RollTool,        // Roll edit
    MulticamTool     // Multicam editing
};

// Tool ONLY changes cursor behavior and click interpretation
// Tool NEVER directly affects playback or composition
```

---

## Part 2: AutoSlate Current Architecture

### 2.1 Current Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    AutoSlate Current                        │
│                                                             │
│  EnhancedTimelineView                                       │
│       │                                                     │
│       ├── timelineHeader (tools, buttons)                   │
│       ├── timeRulerSection                                  │
│       │       └── TimeRulerView                             │
│       └── timelineContent                                   │
│               └── TimelineTrackView[] (for each track)      │
│                       └── TimelineSegmentView[]             │
│                                                             │
│  ProjectViewModel                                           │
│       └── project.segments (direct storage)                 │
│       └── project.tracks                                    │
│       └── selectedTimelineTool (tool state mixed with data) │
│                                                             │
│  PlayerViewModel                                            │
│       └── AVPlayer                                          │
│       └── rebuildComposition() (rebuilds on ANY change)     │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Problems Identified

| Problem | Current Behavior | Kdenlive Solution |
|---------|-----------------|-------------------|
| Tool selection affects playback | Tool is @Published in ProjectViewModel, triggers view updates | Separate ToolState singleton |
| Composition rebuilds too often | Any segment change rebuilds entire AVComposition | Hash-based rebuild checking, lazy rebuilds |
| No bin/timeline separation | Clips and segments are mixed together | Separate Bin model from Timeline model |
| Timeline not scrollable independently | Horizontal scroll affects header | Fixed headers, scrollable content |
| Track headers scroll horizontally | Inside horizontal ScrollView | Fixed position outside scroll |

---

## Part 3: Improvement Plan for AutoSlate

### 3.1 New Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 NEW AutoSlate Architecture                  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              UI Layer (SwiftUI Views)               │   │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────────────┐ │   │
│  │  │ Timeline  │ │  Monitor  │ │   Media Bin       │ │   │
│  │  │   View    │ │   View    │ │     View          │ │   │
│  │  └─────┬─────┘ └─────┬─────┘ └─────────┬─────────┘ │   │
│  └────────┼─────────────┼─────────────────┼───────────┘   │
│           │             │                 │               │
│  ┌────────▼─────────────▼─────────────────▼───────────┐   │
│  │            Model Layer (ObservableObjects)          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │   │
│  │  │TimelineModel │  │ PlayerModel  │  │ BinModel │  │   │
│  │  │ - tracks     │  │ - currentTime│  │ - clips  │  │   │
│  │  │ - segments   │  │ - isPlaying  │  │          │  │   │
│  │  └──────┬───────┘  └──────┬───────┘  └────┬─────┘  │   │
│  └─────────┼─────────────────┼───────────────┼────────┘   │
│            │                 │               │            │
│  ┌─────────▼─────────────────▼───────────────▼────────┐   │
│  │           Engine Layer (AVFoundation)              │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │         CompositionEngine                   │   │   │
│  │  │  - AVMutableComposition                     │   │   │
│  │  │  - rebuildIfNeeded() ← lazy/hash-based      │   │   │
│  │  │  - currentComposition (cached)              │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └────────────────────────────────────────────────────┘   │
│                                                           │
│  ┌────────────────────────────────────────────────────┐   │
│  │     Isolated State (Singletons - No @Published)    │   │
│  │  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │  ToolState   │  │  ZoomState   │               │   │
│  │  │  (no rebuild)│  │  (no rebuild)│               │   │
│  │  └──────────────┘  └──────────────┘               │   │
│  └────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────┘
```

### 3.2 Key Changes to Implement

#### Change 1: Separate ToolState (Already Done)
```swift
// ToolState.swift - Completely isolated from ProjectViewModel
final class ToolState: ObservableObject {
    static let shared = ToolState()
    @Published var selectedTool: TimelineTool = .cursor
    // Changing tool NEVER triggers composition rebuild
}
```

#### Change 2: Fixed Track Headers (Like Kdenlive)

**Current:** Track headers scroll horizontally with content  
**New:** Track headers are fixed, only content scrolls

```swift
// New TimelineView structure
HStack(spacing: 0) {
    // FIXED: Track headers column (doesn't scroll horizontally)
    VStack(spacing: 0) {
        ForEach(tracks) { track in
            TrackHeaderView(track: track)
        }
    }
    .frame(width: 50)
    
    // SCROLLABLE: Timeline content only
    ScrollView(.horizontal) {
        VStack(spacing: 0) {
            ForEach(tracks) { track in
                TrackContentView(track: track) // Just the clips, no header
            }
        }
    }
}
```

#### Change 3: Lazy Composition Rebuilds

```swift
class CompositionEngine {
    private var currentHash: Int = 0
    private var cachedComposition: AVMutableComposition?
    
    func getComposition(for segments: [Segment]) -> AVMutableComposition {
        let newHash = computeHash(segments)
        
        // Only rebuild if actually changed
        if newHash != currentHash {
            cachedComposition = buildComposition(from: segments)
            currentHash = newHash
        }
        
        return cachedComposition!
    }
    
    private func computeHash(_ segments: [Segment]) -> Int {
        var hasher = Hasher()
        for segment in segments {
            hasher.combine(segment.id)
            hasher.combine(segment.compositionStartTime)
            hasher.combine(segment.duration)
            hasher.combine(segment.sourceStart)
        }
        return hasher.finalize()
    }
}
```

#### Change 4: Segment Reference Model (Like Kdenlive's Bin)

```swift
// Clips live in a "bin" - the source material
class MediaBin: ObservableObject {
    @Published var clips: [MediaClip] = []
}

// Segments reference clips, don't duplicate them
struct Segment {
    let id: UUID
    let clipReference: UUID  // Points to clip in bin
    var inPoint: Double      // Where to start in source
    var outPoint: Double     // Where to end in source
    var timelinePosition: Double  // Position on timeline
    var trackId: UUID
}

// Timeline just arranges references
class TimelineModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var segments: [Segment] = []  // References, not full clips
}
```

#### Change 5: Debounced Playhead Updates

```swift
// Only update playhead at 30fps, not every frame
class PlayerModel: ObservableObject {
    private var displayLink: CADisplayLink?
    @Published var displayedTime: Double = 0  // Updated at 30fps for UI
    var preciseTime: Double = 0  // Updated continuously for playback
    
    func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateDisplay))
        displayLink?.preferredFramesPerSecond = 30
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updateDisplay() {
        // Only publish to UI at 30fps
        displayedTime = preciseTime
    }
}
```

---

## Part 4: Implementation Phases

### Phase 1: Foundation (Immediate)
- [x] Create isolated ToolState singleton
- [ ] Fix timeline/track header alignment
- [ ] Implement hash-based composition rebuild

### Phase 2: Structure (Next)
- [ ] Separate TimelineModel from ProjectViewModel
- [ ] Create CompositionEngine class
- [ ] Implement fixed track headers layout

### Phase 3: Polish (Later)
- [ ] Add debounced playhead updates
- [ ] Implement proper undo/redo with snapshots
- [ ] Add keyboard shortcuts for tools

---

## Part 5: File Changes Required

| File | Changes |
|------|---------|
| `TimelineModel.swift` | NEW - Separate timeline data model |
| `CompositionEngine.swift` | NEW - Manages AVComposition building |
| `EnhancedTimelineView.swift` | Restructure for fixed headers |
| `TimelineTrackView.swift` | Split into header + content |
| `ProjectViewModel.swift` | Remove timeline-specific code |
| `PlayerViewModel.swift` | Use CompositionEngine, debounce updates |
| `ToolState.swift` | Already exists, verify isolation |

---

## Summary

The key insight from Kdenlive is **separation of concerns**:

1. **UI State** (tools, zoom) - Never affects playback
2. **Timeline Model** (tracks, segments) - Structural data only
3. **Playback Engine** (composition, player) - Rebuilds lazily
4. **Monitor** (preview) - Reads from cached composition

AutoSlate's current architecture mixes all of these together in `ProjectViewModel`, causing cascade effects where changing a tool triggers composition rebuilds.

By adopting Kdenlive's patterns, AutoSlate can achieve:
- Smooth tool switching (no playback interruption)
- Responsive timeline editing
- Professional-grade preview performance

