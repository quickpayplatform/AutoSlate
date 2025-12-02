# SkipSlate Architecture Notes

**Last Updated:** December 2025  
**Purpose:** Document the cleaned-up architecture, module boundaries, and guidelines for adding new features.

---

## Overview

SkipSlate uses a modular MVVM architecture with clear separation between:
- **Media Import** (local files, stock footage)
- **Auto Edit** (audio analysis, segment generation)
- **Timeline** (segment management, multi-track editing)
- **Preview/Playback** (AVPlayer, composition rendering)
- **Export** (final video rendering)

---

## Module Boundaries

### 1. Media Import Module

**Components:**
- `MediaImportStepView` - Main UI for importing media
- `MediaImportService` - Handles file import and validation
- `StockService` / `PexelsService` - Stock footage search and download

**Responsibilities:**
- File selection and validation
- Creating `MediaClip` entries
- Adding clips to `ProjectViewModel.project.clips`
- **MUST NOT:** Access `PlayerViewModel`, `AVPlayer`, or `AVMutableComposition` directly

**Interface:**
```swift
// Media import communicates via ProjectViewModel only
projectViewModel.importMedia(urls: [URL])
projectViewModel.addImportedClips([MediaClip])  // If needed
```

**Rules:**
- ✅ Can read `projectViewModel.project.clips`
- ✅ Can call `projectViewModel.importMedia(urls:)`
- ❌ **NEVER** call `projectViewModel.playerVM` or any player methods
- ❌ **NEVER** call `rebuildComposition()` directly

---

### 2. Timeline Module

**Components:**
- `EnhancedTimelineView` - Primary timeline UI
- `TimelineView` - Alternative timeline (may be deprecated)
- `TimelineTrackView` - Individual track rendering
- `TimeRulerView` - Time ruler with timestamps

**Responsibilities:**
- Displaying segments on tracks
- Drag-and-drop segment reordering
- Segment selection and editing
- Playhead positioning
- **MUST NOT:** Know about Pexels-specific details or media import UI

**Interface:**
```swift
// Timeline reads from ProjectViewModel
projectViewModel.project.tracks
projectViewModel.project.segments
projectViewModel.selectedSegment

// Timeline updates via ProjectViewModel methods
projectViewModel.moveSegment(segmentID, to: time)
projectViewModel.splitSegment(segment, at: time)
projectViewModel.updateSegmentTiming(...)
```

**Rules:**
- ✅ Can read project data (tracks, segments, clips)
- ✅ Can call `ProjectViewModel` methods to modify segments
- ✅ Can call `projectViewModel.playerVM.seek(to:)` for playhead control
- ❌ **NEVER** access media import UI components
- ❌ **NEVER** know about stock provider specifics

---

### 3. Preview/Playback Module

**Components:**
- `PreviewPanel` - Video preview UI
- `PlayerHostingView` - NSView wrapper for AVPlayerLayer
- `PlayerViewModel` - AVPlayer and composition management

**Responsibilities:**
- Managing single `AVPlayer` instance
- Building `AVMutableComposition` from project data
- Playback control (play, pause, seek)
- **MUST NOT:** Depend on any UI views (MediaImportStepView, timeline views, etc.)

**Interface:**
```swift
// PlayerViewModel is owned by ProjectViewModel (or AppViewModel for stability)
// It only depends on Project data:
playerViewModel.rebuildComposition(from: Project)
playerViewModel.seek(to: Double)
playerViewModel.play() / pause()
```

**Rules:**
- ✅ Only reads `Project` data (segments, tracks, clips, settings)
- ✅ Owns a single `AVPlayer` instance (never recreated)
- ✅ Builds composition from `Project.segments` and `Project.tracks`
- ❌ **NEVER** depends on UI views
- ❌ **NEVER** knows about media import or stock services
- ❌ **NEVER** accesses `MediaImportStepView` or `StockService`

**Stability Requirements:**
- `PlayerViewModel` must be created once and persist for the project lifetime
- `AVPlayer` instance must never be recreated (only the `AVPlayerItem` changes)
- Composition rebuilds should preserve playback state when possible

---

### 4. Auto Edit Module

**Components:**
- `AutoEditService` - Segment generation logic
- `AudioAnalysisEngine` - Audio analysis
- `FrameAnalysisService` - Visual quality analysis

**Responsibilities:**
- Analyzing audio for silence detection
- Analyzing video for quality scoring
- Generating segments based on project type
- **MUST NOT:** Directly modify PlayerViewModel or composition

**Interface:**
```swift
// Auto Edit communicates via ProjectViewModel
projectViewModel.runAutoEdit()
// AutoEditService generates segments
// ProjectViewModel adds segments to project and triggers rebuild
```

**Rules:**
- ✅ Generates `Segment` objects
- ✅ Returns segments to `ProjectViewModel`
- ❌ **NEVER** directly calls `PlayerViewModel.rebuildComposition()`
- ❌ **NEVER** modifies `AVPlayer` or composition directly

---

### 5. Export Module

**Components:**
- `ExportStepView` - Export UI
- `ExportService` - Final video rendering

**Responsibilities:**
- Building final composition from project
- Rendering to file
- Progress tracking
- **MUST NOT:** Depend on preview or timeline UI

**Interface:**
```swift
// Export uses Project data and builds its own composition
exportService.export(project: Project, to: URL, format: ExportFormat)
```

**Rules:**
- ✅ Reads `Project` data
- ✅ Builds its own composition (independent of PlayerViewModel)
- ❌ **NEVER** depends on `PlayerViewModel` or preview UI

---

## Communication Patterns

### How Modules Communicate

1. **Media Import → Project:**
   ```
   MediaImportStepView → projectViewModel.importMedia(urls:)
   → Updates project.clips
   → Does NOT trigger composition rebuild (no segments yet)
   ```

2. **Auto Edit → Project:**
   ```
   AutoEditService → Generates segments
   → ProjectViewModel.runAutoEdit()
   → Updates project.segments
   → Calls playerViewModel.rebuildComposition(from: project)
   ```

3. **Timeline → Project:**
   ```
   TimelineView → projectViewModel.moveSegment(...)
   → Updates project.segments
   → Calls playerViewModel.rebuildComposition(from: project)
   ```

4. **Project → Preview:**
   ```
   ProjectViewModel → playerViewModel.rebuildComposition(from: project)
   → PlayerViewModel builds AVMutableComposition
   → Updates AVPlayer with new composition
   → PreviewPanel observes PlayerViewModel for playback state
   ```

---

## PlayerViewModel Stability Rules

### RULE A1 – Single, Stable PlayerViewModel / AVPlayer

- **Owner:** `ProjectViewModel` (or `AppViewModel` for maximum stability)
- **Lifetime:** Created once when project is created, persists for project lifetime
- **AVPlayer:** Single instance, never recreated (only `AVPlayerItem` changes)

```swift
// In ProjectViewModel:
private var playerViewModel: PlayerViewModel?  // Created in init, never nil after first access

var playerVM: PlayerViewModel {
    if playerViewModel == nil {
        playerViewModel = PlayerViewModel(project: project)
    }
    return playerViewModel!
}
```

### RULE A2 – Composition is Derived Solely from Project Data

- `PlayerViewModel.rebuildComposition(from: Project)` uses only:
  - `project.segments` (enabled segments)
  - `project.tracks` (track layout)
  - `project.clips` (source media)
  - `project.colorSettings` / `project.audioSettings`
- **Never** reaches into UI views or services

### RULE A3 – Media Import is a Pure Producer of ProjectMedia

- `MediaImportStepView` and `StockService` only:
  - Pick/select files
  - Download/copy files
  - Create `MediaClip` entries
  - Add to `project.clips`
- **Never** touch `AVPlayer`, `AVMutableComposition`, or `PlayerViewModel` internals

---

## Adding New Features

### Adding a New Stock Provider (e.g., Pixabay)

1. **Create new service:**
   - `PixabayService.swift` (similar to `PexelsService`)
   - Implements stock search/download

2. **Update Media Import UI:**
   - Add provider selection in `MediaImportStepView` or `StockPanel`
   - Call service methods to search/download

3. **No changes needed to:**
   - `PlayerViewModel` (it doesn't know about providers)
   - `TimelineView` (it doesn't know about providers)
   - `PreviewPanel` (it doesn't know about providers)

**Example:**
```swift
// In StockPanel or MediaImportStepView:
if selectedProvider == .pexels {
    clips = try await PexelsService.shared.search(...)
} else if selectedProvider == .pixabay {
    clips = try await PixabayService.shared.search(...)
}
// Then:
projectViewModel.importMedia(urls: downloadedURLs)
```

---

### Adding a New Timeline Tool (e.g., Marker Tool)

1. **Update `TimelineTool` enum:**
   ```swift
   enum TimelineTool {
       case cursor, razor, trim, hand, marker  // Add marker
   }
   ```

2. **Update `TimelineView` or `EnhancedTimelineView`:**
   - Add marker placement logic
   - Store markers in `Project` model (if needed)

3. **No changes needed to:**
   - `PlayerViewModel` (unless markers affect playback, then add to Project model)
   - `MediaImportStepView` (unrelated)

---

### Adding Audio-Only Tracks

1. **Ensure `TimelineTrackType` supports `.audio`:**
   ```swift
   enum TimelineTrackType {
       case videoPrimary, videoOverlay, audio
   }
   ```

2. **Update `PlayerViewModel.buildComposition()`:**
   - Iterate `project.tracks`
   - For `.audio` tracks, add audio-only segments to audio composition track
   - Respect `TimelineTrack.isMuted` and `isSolo`

3. **Update `TimelineView`:**
   - Render audio tracks as separate rows
   - Allow drag-and-drop of audio-only `MediaClip` to audio tracks

4. **No changes needed to:**
   - `MediaImportStepView` (it already handles audio-only clips)
   - `StockService` (unrelated)

---

## Common Pitfalls to Avoid

### ❌ DON'T: Access PlayerViewModel from Media Import

```swift
// BAD:
struct MediaImportStepView: View {
    var body: some View {
        // ...
        projectViewModel.playerVM.rebuildComposition(...)  // ❌ WRONG
    }
}
```

**Why:** Media import should only add clips. Composition rebuild happens automatically when segments are created (during auto-edit).

### ❌ DON'T: Recreate PlayerViewModel

```swift
// BAD:
var playerVM: PlayerViewModel {
    PlayerViewModel(project: project)  // ❌ Creates new instance every time
}
```

**Why:** This breaks the single stable instance rule. Use lazy initialization with stored property.

### ❌ DON'T: Make PlayerViewModel Depend on UI Views

```swift
// BAD:
class PlayerViewModel {
    func rebuildComposition(from mediaImportView: MediaImportStepView) {  // ❌ WRONG
        // ...
    }
}
```

**Why:** PlayerViewModel should only depend on `Project` data, not UI.

### ✅ DO: Use Project Data as Source of Truth

```swift
// GOOD:
class PlayerViewModel {
    func rebuildComposition(from project: Project) {  // ✅ Only depends on Project
        // Build composition from project.segments, project.tracks, project.clips
    }
}
```

---

## Testing Module Independence

To verify modules are independent:

1. **Test Media Import changes don't break preview:**
   - Restyle `MediaImportStepView` (change colors, layout, add/remove views)
   - Verify `PreviewPanel` continues to work
   - Verify `PlayerViewModel.player` instance identity doesn't change

2. **Test Timeline changes don't break media import:**
   - Modify timeline UI (add/remove tracks, change styling)
   - Verify media import still works
   - Verify stock search still works

3. **Test Preview changes don't break timeline:**
   - Modify `PreviewPanel` layout
   - Verify timeline still responds to playhead updates
   - Verify segment selection still works

---

## Summary

- **Media Import:** Produces `MediaClip` → adds to `project.clips` → never touches player
- **Auto Edit:** Produces `Segment` → adds to `project.segments` → triggers rebuild
- **Timeline:** Reads/writes `project.segments` → triggers rebuild
- **Preview:** Reads `PlayerViewModel` → displays playback
- **PlayerViewModel:** Reads `Project` → builds composition → updates `AVPlayer`

All communication flows through `ProjectViewModel` and `Project` data model. No direct cross-module dependencies.

