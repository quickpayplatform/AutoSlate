# Segment Storage Architecture - Why Deletion Is Complex

## The Problem: Dual Storage System

Segments are stored in **TWO separate places** with a many-to-many relationship:

### 1. Central Segment Pool
```swift
Project.segments: [Segment]
```
- A flat array containing ALL segments in the project
- Each segment has a unique `UUID` as its identifier
- Contains the actual segment data (clip reference, timing, effects, etc.)

### 2. Track References
```swift
TimelineTrack.segments: [Segment.ID]  // Array of UUIDs
```
- Each track (V1, V2, A1, etc.) contains an array of **segment IDs** (UUIDs)
- These IDs **reference** segments from the central pool
- The same segment ID can appear on multiple tracks (e.g., a video segment might be on V1 AND its audio on A1)

## Visual Representation

```
Project
├── segments: [Segment]  ← CENTRAL POOL
│   ├── Segment(id: UUID-1, ...)
│   ├── Segment(id: UUID-2, ...)
│   └── Segment(id: UUID-3, ...)
│
└── tracks: [TimelineTrack]
    ├── V1 (videoPrimary)
    │   └── segments: [UUID-1, UUID-2]  ← REFERENCES to central pool
    ├── V2 (videoOverlay)
    │   └── segments: [UUID-3]
    └── A1 (audio)
        └── segments: [UUID-1, UUID-3]  ← Same segment can be on multiple tracks!
```

## Why This Architecture Exists

1. **Multi-Track Support**: A single media clip can create segments on multiple tracks (video on V1, audio on A1)
2. **Flexibility**: Segments can be moved between tracks without duplicating data
3. **Efficiency**: Segment data is stored once, referenced multiple times

## Why Deletion Is Complex

When you delete a segment, you must:

### 1. Update the Central Pool
```swift
project.segments.remove(at: index)  // Remove from central array
```

### 2. Remove References from ALL Tracks
```swift
for track in project.tracks {
    track.segments.removeAll { $0 == deletedSegmentID }
}
```
- Must check **every track** for references to that segment ID
- A segment might be referenced on V1, V2, AND A1 simultaneously
- Missing a reference creates "dangling pointers" (track references a non-existent segment)

### 3. Update Selection State
```swift
selectedSegment = nil
selectedSegmentIDs.remove(deletedSegmentID)
```

### 4. Handle Timeline Timing
- Segments use `compositionStartTime` (absolute positioning, not sequential)
- Deleting must preserve timeline gaps (convert clip to gap segment)
- Must maintain timeline continuity

### 5. Rebuild Dependent Systems
After deletion, you must rebuild:
- **PlayerViewModel**: AVComposition must be rebuilt
- **ExportService**: Export composition must be rebuilt
- **TimelineTrackView**: UI must refresh
- **InspectorPanel**: If deleted segment was selected

### 6. Coordinate Multiple Systems
These systems all depend on segments:
- `PlayerViewModel.buildComposition()` - Creates AVFoundation composition
- `ExportService.buildComposition()` - Creates export composition
- `TimelineTrackView` - Renders timeline UI
- `TransitionService` - Handles transitions between segments
- `AutoEditService` - Creates new segments
- Selection state (`selectedSegment`, `selectedSegmentIDs`)

## Current Delete Implementation

The current `deleteSegments(withIDs:)` function:

1. ✅ Converts clip segments to gap segments (preserves timeline timing)
2. ✅ Updates track references to new gap segment IDs
3. ✅ Clears selection state
4. ✅ Triggers composition rebuild

**BUT** the complexity comes from ensuring ALL of these happen correctly every time, and that no system is left with stale references.

## The Real Challenge

The challenge isn't just the deletion logic - it's ensuring that:
1. All systems are notified of changes
2. No stale references remain
3. UI updates correctly
4. Compositions rebuild properly
5. Selection state stays in sync
6. Timeline rendering reflects changes immediately

This requires careful coordination across multiple ViewModels, Views, and Services.

## Potential Simplifications

If deletion continues to be problematic, consider:

1. **Single Source of Truth**: Make segments track-specific (no central pool)
   - Trade-off: Duplicate data if segment appears on multiple tracks

2. **Event System**: Implement a notification system for segment changes
   - All systems subscribe to segment change events
   - Automatically update when segments are deleted

3. **Immutability**: Never modify segments in place
   - Always create new Project with updated segments
   - Forces all systems to react to changes

4. **Simplified Model**: Remove multi-track support for now
   - Single track = single array of segments
   - Much simpler deletion logic

## Current Status

Deletion **is implemented** in `ProjectViewModel.deleteSegments(withIDs:)`, but the complexity of the dual storage system makes it fragile and prone to bugs if any step is missed or executed out of order.
