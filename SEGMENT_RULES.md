# Segment Rules & Architecture

## Overview

This document defines the **core rules and principles** for how segments work in AutoSlate. All agents working on this codebase MUST follow these rules to ensure segments remain simple, efficient, and fully functional.

---

## Core Principle: Segments Are Simple

**A segment is nothing more than a pointer to a portion of a video/audio clip with a position on the timeline.**

That's it. No hidden logic. No complex state. No interference.

---

## The Segment Model

```swift
struct Segment {
    let id: UUID                      // Unique identifier
    var sourceClipID: UUID?           // Which clip this segment comes from
    var sourceStart: Double           // Start time in the SOURCE clip (seconds)
    var sourceEnd: Double             // End time in the SOURCE clip (seconds)
    var compositionStartTime: Double  // Position on the TIMELINE (seconds), -1.0 = not set
    var duration: Double              // Calculated: sourceEnd - sourceStart
    var enabled: Bool                 // Whether this segment is active
    var colorIndex: Int               // Visual color in timeline
    var effects: SegmentEffects       // Transform, composition mode, audio settings
    var kind: SegmentKind             // .clip or .gap
}
```

---

## The 10 Commandments of Segments

### 1. Every Video Has a Segment
- **NEVER** add video content to the preview without a corresponding segment on the timeline
- No hidden layers, no complementary videos, no automatic stacking
- If it's in the preview, it MUST be visible as a segment

### 2. Segments Are Independent
- A segment's position (`compositionStartTime`) is absolute, not relative
- Moving one segment does NOT affect other segments
- No ripple editing by default - gaps are allowed

### 3. The Timeline Is the Source of Truth
- The preview is a **pure mirror** of the timeline
- What you see on the timeline = what you see in preview
- No hidden processing, no secret filters, no automatic adjustments

### 4. Segments Don't Block Each Other
- Multiple segments can exist at the same time on different tracks
- V2 renders on TOP of V1 (higher track number = foreground)
- Audio segments play simultaneously (mixed together)

### 5. Tools Only Affect Segments
- Timeline tools (move, cut, trim, select) ONLY interact with segments
- Tools do NOT pause playback
- Tools do NOT trigger unnecessary rebuilds
- Tools do NOT modify player state

### 6. Playback Is Sacred
- NOTHING should pause the player except the user pressing pause
- Segment operations (move, cut, trim) do NOT pause playback
- The playhead keeps moving regardless of what you're doing to segments

### 7. Composition Rebuilds Are Lazy
- Only rebuild when the project hash changes
- Hash includes: segment positions, durations, source times, track membership
- No duplicate rebuilds for the same state

### 8. Segments Process in Order
- When building AVFoundation composition, segments MUST be sorted by `compositionStartTime`
- This prevents black screens and duration mismatches
- Never process segments in array order - always sort first

### 9. Position 0.0 Is Valid
- `compositionStartTime = 0.0` means "starts at the beginning"
- `compositionStartTime = -1.0` means "not explicitly set" (sentinel value)
- Always check `>= 0`, never `> 0`

### 10. User Has Full Control
- User can move any segment anywhere
- User can place segments on any track
- User can overlap segments
- The app does NOT override user decisions

---

## Video Track Layering

```
V3 ─────────────────  (FOREGROUND - renders on top)
V2 ─────────────────  (MIDDLE)
V1 ─────────────────  (BACKGROUND - base layer)
─────────────────────
A1 ─────────────────  (Audio track 1)
A2 ─────────────────  (Audio track 2 - mixed with A1)
```

- Higher track number = more foreground
- V1 is the base/background layer
- V2+ are overlay layers that cover V1
- This is essential for green screen, picture-in-picture, etc.

---

## What NOT To Do

### ❌ Don't Pause Playback During Operations
```swift
// BAD - Never do this
func moveSegment() {
    playerViewModel.pause()  // ❌ NO!
    // ... move logic
}

// GOOD
func moveSegment() {
    // ... move logic (playback continues)
}
```

### ❌ Don't Add Hidden Content
```swift
// BAD - Never do this
func buildComposition() {
    // Add complementary video behind  // ❌ NO!
    // Add automatic overlay           // ❌ NO!
}

// GOOD
func buildComposition() {
    // Only add what's in timeline segments
    for segment in sortedSegments {
        insertSegment(segment)
    }
}
```

### ❌ Don't Override User Position
```swift
// BAD - Never do this
func moveSegment(to time: Double) {
    segment.compositionStartTime = snapToGrid(time)  // ❌ Don't force snap
    segment.compositionStartTime = max(0, time)       // ❌ Don't clamp
}

// GOOD
func moveSegment(to time: Double) {
    segment.compositionStartTime = time  // User's choice, respect it
}
```

### ❌ Don't Process Segments Out of Order
```swift
// BAD - Never do this
for segmentID in track.segments {  // ❌ Array order is wrong
    insertSegment(segmentID)
}

// GOOD
let sortedIDs = track.segments.sorted { 
    segmentStarts[$0]! < segmentStarts[$1]! 
}
for segmentID in sortedIDs {  // ✓ Chronological order
    insertSegment(segmentID)
}
```

---

## Effects & Segments

Effects are stored IN the segment, not separately:

```swift
struct SegmentEffects {
    // Transform
    var scale: Double = 1.0
    var positionX: Double = 0.0
    var positionY: Double = 0.0
    var rotation: Double = 0.0
    
    // Composition
    var compositionMode: CompositionMode = .fit
    var compositionAnchor: CompositionAnchor = .center
    
    // Audio
    var audioVolume: Double = 1.0
    var audioFadeInDuration: Double = 0.0
    var audioFadeOutDuration: Double = 0.0
    
    // Transitions (applied at segment boundaries)
    var transitionIn: TransitionType = .none
    var transitionOut: TransitionType = .none
    var transitionDuration: Double = 0.5
}
```

When implementing effects:
1. Read the effect values from `segment.effects`
2. Apply transforms in `TransitionService.calculateCompleteTransform()`
3. Apply audio in `TransitionService.createAudioMix()`
4. Do NOT store effect state outside the segment

---

## Composition Building Flow

```
1. User makes edit (move, cut, trim, etc.)
           ↓
2. ProjectViewModel updates segment data
           ↓
3. ProjectViewModel calls immediateRebuild()
           ↓
4. Check hash - if unchanged, skip rebuild
           ↓
5. PlayerViewModel.buildComposition()
   a. Sort segments by compositionStartTime  ← CRITICAL
   b. For each track, insert segments in order
   c. Build video composition instructions
   d. Build audio mix
           ↓
6. PlayerViewModel.updatePlayer()
   a. Replace player item
   b. Seek to previous time
   c. Restore play state if was playing
           ↓
7. Preview updates to reflect timeline
```

---

## Key Files

| File | Responsibility |
|------|---------------|
| `Segment.swift` | Segment model definition |
| `ProjectViewModel.swift` | Segment CRUD operations, track management |
| `PlayerViewModel.swift` | Composition building, playback |
| `TransitionService.swift` | Video/audio composition, transforms, layering |
| `TimelineTrackView.swift` | Segment UI rendering |
| `EnhancedTimelineView.swift` | Timeline container, drag handling |

---

## Testing Checklist

Before any PR that touches segments:

- [ ] Move segment to new position → Preview updates correctly
- [ ] Move segment to position 0.0 → No black screen
- [ ] Move segment between tracks → Preview reflects new layer
- [ ] Cut segment → Gap appears, preview shows black in gap
- [ ] Trim segment → Duration changes, preview reflects trim
- [ ] Move during playback → Playhead keeps moving
- [ ] Multiple segments same time → V2 on top of V1
- [ ] Delete segment → Preview shows black/underlying layer

---

## Summary

**Segments are simple. Keep them simple.**

- A segment = a pointer to video + a position on timeline
- The timeline is the source of truth
- The preview mirrors the timeline exactly
- Nothing is hidden, nothing is automatic
- User has full control

Follow these rules and segments will work perfectly.

