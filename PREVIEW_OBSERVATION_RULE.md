# Video Preview Observation Rule

## The Problem

After Part D refactoring, the video preview stopped showing after auto-edit completed, even though:
- ✅ Composition was built successfully
- ✅ Player was initialized correctly
- ✅ PlayerItem status was `readyToPlay`
- ✅ All logs showed everything working

**The preview view simply wasn't updating when the composition changed.**

## Root Cause

The issue was in `PreviewPanel.swift`. It was observing `ProjectViewModel` but accessing `PlayerViewModel` indirectly:

```swift
// ❌ WRONG - Indirect observation
struct PreviewPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        if let player = projectViewModel.playerVM.player {  // Indirect access
            VideoPlayerView(player: player)
        }
    }
}
```

**Why this fails:**
- SwiftUI's `@ObservedObject` only triggers view updates when the **observed object's `@Published` properties** change
- When composition is rebuilt, changes happen in `PlayerViewModel` (duration, playerItem, etc.)
- `ProjectViewModel` doesn't have `@Published` properties that change when `PlayerViewModel` changes
- So `PreviewPanel` never gets notified that it needs to re-render
- The view thinks nothing changed, even though the player/composition is completely different

## The Fix

Make views that display preview/playback state **directly observe `PlayerViewModel`**:

```swift
// ✅ CORRECT - Direct observation
struct PreviewPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject private var playerViewModel: PlayerViewModel  // Direct observation
    
    init(projectViewModel: ProjectViewModel) {
        self.projectViewModel = projectViewModel
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
    }
    
    var body: some View {
        // Now this view updates when playerViewModel.duration, isPlaying, etc. change
        if let player = playerViewModel.player, playerViewModel.duration > 0 {
            VideoPlayerView(player: player)
        }
    }
}
```

**Why this works:**
- `PreviewPanel` directly observes `PlayerViewModel`
- When composition is rebuilt, `PlayerViewModel.duration` changes (a `@Published` property)
- SwiftUI detects the change and triggers a view update
- The preview correctly displays the new composition

## General Rule

### 🚨 CRITICAL RULE: Preview/Playback Views Must Directly Observe PlayerViewModel

**Any view that displays video preview, playback state, or transport controls MUST:**

1. **Directly observe `PlayerViewModel`** using `@ObservedObject`
   - ✅ `@ObservedObject var playerViewModel: PlayerViewModel`
   - ❌ NOT just `projectViewModel.playerVM.player` (indirect access)

2. **Check `PlayerViewModel`'s `@Published` properties** to trigger updates
   - Use `playerViewModel.duration > 0` to detect when composition is ready
   - Use `playerViewModel.isPlaying` for play/pause state
   - Use `playerViewModel.currentTime` for scrubber position

3. **Why this matters:**
   - SwiftUI's reactive system only updates views when observed `@Published` properties change
   - Indirect access through `ProjectViewModel` breaks the observation chain
   - Composition rebuilds happen in `PlayerViewModel`, not `ProjectViewModel`
   - Without direct observation, views don't know when to update

## Examples

### ✅ CORRECT - Direct Observation

```swift
struct PreviewPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @ObservedObject private var playerViewModel: PlayerViewModel
    
    init(projectViewModel: ProjectViewModel) {
        self.projectViewModel = projectViewModel
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
    }
    
    var body: some View {
        if let player = playerViewModel.player, playerViewModel.duration > 0 {
            VideoPlayerView(player: player)
        }
    }
}

struct TransportControls: View {
    @ObservedObject var playerViewModel: PlayerViewModel  // ✅ Direct observation
    
    var body: some View {
        Slider(value: $playerViewModel.currentTime, in: 0...playerViewModel.duration)
    }
}
```

### ❌ WRONG - Indirect Observation

```swift
struct PreviewPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel  // Only observing this
    
    var body: some View {
        // ❌ Indirect access - won't update when PlayerViewModel changes
        if let player = projectViewModel.playerVM.player {
            VideoPlayerView(player: player)
        }
    }
}

struct TransportControls: View {
    @ObservedObject var projectViewModel: ProjectViewModel  // ❌ Wrong object
    
    var body: some View {
        // ❌ Won't update when player state changes
        Slider(value: $projectViewModel.playerVM.currentTime, ...)
    }
}
```

## When This Rule Applies

**Apply this rule to ANY view that:**
- Displays video preview (`VideoPlayerView`, `PreviewPanel`, etc.)
- Shows playback state (play/pause button, timecode, etc.)
- Displays transport controls (scrubber, seek buttons, etc.)
- Needs to react to composition rebuilds

**This rule does NOT apply to:**
- Views that only read project data (clips, segments, settings)
- Views that don't display preview/playback state
- Views that only modify project data (timeline editing, media import, etc.)

## Prevention Checklist

Before making changes that affect preview/playback views:

- [ ] Does the view directly observe `PlayerViewModel` using `@ObservedObject`?
- [ ] Does the view check `PlayerViewModel`'s `@Published` properties (duration, isPlaying, etc.)?
- [ ] Does the view update when composition is rebuilt (test after auto-edit)?
- [ ] Is the view using `playerViewModel.property` not `projectViewModel.playerVM.property`?

## Related Files

- `SkipSlate/Views/PreviewPanel.swift` - Main preview display (FIXED)
- `SkipSlate/Views/TransportControls.swift` - Playback controls (already correct)
- `SkipSlate/ViewModels/PlayerViewModel.swift` - Player state management
- `SkipSlate/ViewModels/ProjectViewModel.swift` - Project coordination

## History

- **Part D (Dec 2025)**: Refactored `MediaImportStepView` into components. Preview stopped working after auto-edit.
- **Fix Applied**: Made `PreviewPanel` directly observe `PlayerViewModel` instead of indirect access through `ProjectViewModel`.
- **Result**: Preview now correctly updates when composition is rebuilt.

