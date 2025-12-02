# Part A: Diagnosis - Why Pexels/Media Upload Breaks Preview

**Date:** December 2025  
**Purpose:** Document root causes of preview breakage when MediaImportStepView UI changes.

---

## Problem Statement

When the Pexels/stock media UI or MediaImportStepView is modified (tabs, layout, visual components), the video preview breaks. The preview may:
- Stop playing
- Show black screen
- Lose the AVPlayer instance
- Fail to rebuild composition

---

## Root Causes Identified

### Root Cause #1: PlayerViewModel Recreated During Media Import

**Location:** `ProjectViewModel.importMediaLimited()` (line ~788-790)

**Problem:**
```swift
// In ProjectViewModel.importMediaLimited():
if let playerVM = playerViewModel {
    playerVM.rebuildComposition(from: project)  // ❌ Called when no segments exist
}
```

**Issue:**
- `rebuildComposition()` is called immediately after importing clips
- At this point, `project.segments` is empty (segments are created during auto-edit)
- `PlayerViewModel.rebuildComposition()` checks for segments and returns early:
  ```swift
  guard !project.segments.isEmpty else {
      print("SkipSlate: ⚠️ Cannot rebuild - project has no segments")
      return
  }
  ```
- However, the early return may leave the player in an inconsistent state
- When MediaImportStepView UI changes (tab switch, layout update), SwiftUI may recreate views
- If `PlayerViewModel` is accessed during view recreation and the player is in a bad state, preview breaks

**Evidence:**
- `MediaImportStepView` does NOT directly access `PlayerViewModel` (verified via grep)
- `StockService` and `PexelsService` do NOT access `PlayerViewModel` (verified via grep)
- The issue occurs when UI changes, not when media is imported
- This suggests the problem is indirect: UI changes → view recreation → PlayerViewModel access → bad state

---

### Root Cause #2: PlayerViewModel Lazy Initialization May Create Multiple Instances

**Location:** `ProjectViewModel.playerVM` computed property (line ~362-367)

**Current Code:**
```swift
var playerVM: PlayerViewModel {
    if playerViewModel == nil {
        playerViewModel = PlayerViewModel(project: project)
    }
    return playerViewModel!
}
```

**Problem:**
- While this uses lazy initialization, if `playerViewModel` is ever set to `nil` (e.g., during view recreation or project reset), a new instance is created
- Each new `PlayerViewModel` creates a new `AVPlayer` instance
- `PreviewPanel` observes `projectViewModel.playerVM.player`, and if the player instance changes, the preview breaks

**Evidence:**
- `PlayerViewModel.init()` creates a new `AVPlayer()` instance
- If `PlayerViewModel` is recreated, the old player instance is lost
- `PreviewPanel` uses `projectViewModel.playerVM.player` - if this changes, the view may not update correctly

---

### Root Cause #3: Composition Rebuild Called Without Segments

**Location:** `ProjectViewModel.importMediaLimited()` (line ~788-790)

**Problem:**
- `rebuildComposition()` is called after importing clips, but before segments exist
- While it returns early, the call itself may trigger side effects or state changes
- If the UI changes trigger a view update that accesses `PlayerViewModel`, the player may be in an inconsistent state

**Evidence:**
- Logs show: "Cannot rebuild - project has no segments" during import
- This happens every time media is imported
- The issue manifests when UI changes, suggesting the bad state persists

---

### Root Cause #4: View Recreation May Access PlayerViewModel During Bad State

**Location:** `PreviewPanel` and views that observe `PlayerViewModel`

**Problem:**
- When `MediaImportStepView` changes (tab switch, layout update), SwiftUI may recreate child views
- If `PreviewPanel` or other views that observe `PlayerViewModel` are recreated, they access `projectViewModel.playerVM`
- If `PlayerViewModel` is in a bad state (e.g., composition rebuild failed or returned early), the view may not initialize correctly

**Evidence:**
- `PreviewPanel` uses `projectViewModel.playerVM.player`
- If `playerVM` is accessed during a bad state, `player` may be `nil` or invalid
- The view shows "No player available" or black screen

---

## Solution Strategy

### Fix #1: Don't Call rebuildComposition During Media Import

**Change:**
- Remove the `rebuildComposition()` call from `importMediaLimited()`
- Only call `rebuildComposition()` when segments exist (after auto-edit or manual segment creation)

**Rationale:**
- Media import should only add clips to `project.clips`
- Composition rebuild should only happen when segments exist
- This prevents calling rebuild when it will fail

---

### Fix #2: Ensure PlayerViewModel is Truly Stable

**Change:**
- Initialize `PlayerViewModel` in `ProjectViewModel.init()` (already done, but ensure it's never set to `nil`)
- Make `playerVM` a stored property, not a computed property with lazy init
- Or move `PlayerViewModel` ownership to `AppViewModel` for maximum stability

**Rationale:**
- Ensures a single instance exists for the project lifetime
- Prevents accidental recreation
- Makes the player instance truly stable

---

### Fix #3: Make PlayerViewModel Independent of UI State

**Change:**
- Ensure `PlayerViewModel` only depends on `Project` data
- Remove any dependencies on UI views or wizard step state
- Ensure `rebuildComposition()` is safe to call even when segments are empty (returns early without side effects)

**Rationale:**
- UI changes should not affect `PlayerViewModel`
- `PlayerViewModel` should be resilient to being accessed during any project state

---

### Fix #4: Ensure PreviewPanel Handles Player State Gracefully

**Change:**
- Make `PreviewPanel` handle cases where `player` is `nil` or invalid
- Ensure it updates correctly when player state changes
- Use proper SwiftUI observation patterns

**Rationale:**
- Prevents UI from breaking when player is in a transitional state
- Ensures preview recovers when player becomes valid

---

## Verification Steps

After fixes, verify:

1. **Import media → UI changes → Preview still works:**
   - Import clips in MediaImportStepView
   - Switch between "My Media" and "Stock" tabs
   - Restyle MediaImportStepView (change colors, layout)
   - Verify PreviewPanel continues to work (if segments exist)

2. **PlayerViewModel instance stability:**
   - Check that `PlayerViewModel` instance identity doesn't change during UI updates
   - Check that `AVPlayer` instance identity doesn't change

3. **Composition rebuild only when segments exist:**
   - Import clips → verify no rebuildComposition call
   - Run auto-edit → verify rebuildComposition is called
   - Verify preview works after auto-edit

---

## Related Code Locations

- `ProjectViewModel.importMediaLimited()` - Line ~755-800
- `ProjectViewModel.playerVM` - Line ~362-367
- `ProjectViewModel.init()` - Line ~357-360
- `PlayerViewModel.rebuildComposition()` - Line ~52-177
- `PreviewPanel` - Uses `projectViewModel.playerVM.player`

---

## Conclusion

The root cause is **indirect coupling** between MediaImportStepView UI changes and PlayerViewModel state:
1. Media import calls `rebuildComposition()` when no segments exist
2. This may leave PlayerViewModel in an inconsistent state
3. UI changes trigger view recreation
4. View recreation accesses PlayerViewModel during bad state
5. Preview breaks

**Solution:** Remove the premature `rebuildComposition()` call and ensure PlayerViewModel is truly stable and independent of UI state.

