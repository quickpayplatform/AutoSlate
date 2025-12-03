# Transform Effects Implementation Documentation

## Overview

This document describes the complete implementation of transform effects for video segments in SkipSlate. The transform system allows users to apply scale, position (X/Y), rotation, and "Scale to Fill Frame" effects to video segments with real-time preview updates.

**Date:** December 2, 2025  
**Status:** ✅ Fully Implemented

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Files Modified](#files-modified)
3. [Transform Calculation Logic](#transform-calculation-logic)
4. [Real-Time Preview Updates](#real-time-preview-updates)
5. [UI Integration](#ui-integration)
6. [Preview Observation Rule Compliance](#preview-observation-rule-compliance)
7. [Transform Order and Coordinate System](#transform-order-and-coordinate-system)
8. [Testing Checklist](#testing-checklist)
9. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

The transform effects system consists of three main components:

1. **Data Model** (`Segment.swift`): Stores transform properties in `SegmentEffects` and `SegmentTransform`
2. **Transform Calculation** (`TransitionService.swift`): Calculates the complete `CGAffineTransform` combining all effects
3. **UI & Updates** (`InspectorPanel.swift`, `ProjectViewModel.swift`): Provides UI controls and triggers real-time rebuilds

### Transform Properties

- **Scale**: Manual scale factor (0.5 to 3.0, default: 1.0)
- **Position X**: Horizontal position (-100% to +100%, default: 0.0)
- **Position Y**: Vertical position (-100% to +100%, default: 0.0)
- **Rotation**: Rotation angle in degrees (-180° to +180°, default: 0.0)
- **Scale to Fill Frame**: Boolean flag that auto-scales video to fill project frame without black bars

---

## Files Modified

### 1. `SkipSlate/Services/TransitionService.swift`

**Changes:**
- Added `calculateCompleteTransform(for:track:project:)` function
- Modified segment transform application in `createVideoCompositionWithTransitions`
- Updated `transformForScaleToFill` to be private (internal helper)

**Key Code Sections:**

```swift
// In createVideoCompositionWithTransitions, around line 363:
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)

// Calculate and apply complete transform (scale, position, rotation, scale to fill)
let finalTransform = calculateCompleteTransform(
    for: segment,
    track: track,
    project: project
)

// Always apply transform (even if identity) to ensure consistent behavior
layerInstruction.setTransform(finalTransform, at: currentTime)
```

**New Function: `calculateCompleteTransform`**

This function combines all transform effects in the correct order:

1. Scale to Fill Frame (if enabled)
2. Manual Scale (around center)
3. Rotation (around center)
4. Position Translation (X/Y)
5. Preferred Transform (source rotation/flip)

### 2. `SkipSlate/Views/InspectorPanel.swift`

**Changes:**
- Updated `updateSegmentEffects` to use `updateSegmentImmediate` for real-time preview
- Enhanced "Reset Transform" button to reset all transform properties including `scaleToFillFrame`

**Key Code Sections:**

```swift
// Updated updateSegmentEffects function:
private func updateSegmentEffects(_ update: (inout SegmentEffects) -> Void) {
    guard let selectedSegment = projectViewModel.selectedSegment else { return }
    var updatedSegment = selectedSegment
    update(&updatedSegment.effects)
    // CRITICAL: Use immediate rebuild for transform effects to enable real-time preview
    projectViewModel.updateSegmentImmediate(updatedSegment)
}

// Enhanced Reset Transform button:
Button("Reset Transform") {
    guard let selectedSegment = projectViewModel.selectedSegment else { return }
    var updatedSegment = selectedSegment
    
    // Reset effects
    updatedSegment.effects.scale = 1.0
    updatedSegment.effects.positionX = 0.0
    updatedSegment.effects.positionY = 0.0
    updatedSegment.effects.rotation = 0.0
    
    // Reset scaleToFillFrame
    updatedSegment.transform.scaleToFillFrame = false
    
    // CRITICAL: Use immediate rebuild for real-time preview
    projectViewModel.updateSegmentImmediate(updatedSegment)
}
```

### 3. `SkipSlate/ViewModels/ProjectViewModel.swift`

**Changes:**
- Added `updateSegmentImmediate(_:)` method for real-time preview updates
- Enhanced `updateSegment(_:)` to detect transform changes and use immediate rebuild
- Updated `projectHash(_:)` to include transform properties in hash calculation

**Key Code Sections:**

```swift
// New method for immediate rebuild:
func updateSegmentImmediate(_ segment: Segment) {
    if let index = project.segments.firstIndex(where: { $0.id == segment.id }) {
        project.segments[index] = segment
        if selectedSegment?.id == segment.id {
            selectedSegment = segment
        }
        immediateRebuild() // Always immediate for transform preview
    }
}

// Enhanced updateSegment to detect transform changes:
func updateSegment(_ segment: Segment) {
    if let index = project.segments.firstIndex(where: { $0.id == segment.id }) {
        project.segments[index] = segment
        if selectedSegment?.id == segment.id {
            selectedSegment = segment
        }
        // CRITICAL: Use immediate rebuild for transform effects to enable real-time preview
        let isTransformChange = segment.effects.scale != 1.0 || 
                               segment.effects.positionX != 0.0 || 
                               segment.effects.positionY != 0.0 || 
                               segment.effects.rotation != 0.0 || 
                               segment.transform.scaleToFillFrame
        
        if isTransformChange {
            immediateRebuild() // Real-time preview for transform changes
        } else {
            debouncedRebuild() // Use debounced rebuild for other effects updates
        }
    }
}

// Updated projectHash to include transform properties:
private func projectHash(_ project: Project) -> Int {
    var hasher = Hasher()
    hasher.combine(project.segments.count)
    for segment in project.segments {
        // ... existing hash components ...
        
        // CRITICAL: Include transform effects in hash to trigger rebuild on transform changes
        hasher.combine(segment.effects.scale)
        hasher.combine(segment.effects.positionX)
        hasher.combine(segment.effects.positionY)
        hasher.combine(segment.effects.rotation)
        hasher.combine(segment.transform.scaleToFillFrame)
    }
    // ... rest of hash calculation ...
}
```

### 4. `SkipSlate/ViewModels/PlayerViewModel.swift`

**Changes:**
- Updated `projectHash(_:)` to include transform properties in hash calculation

**Key Code Sections:**

```swift
private func projectHash(_ project: Project) -> Int {
    // ... existing hash components ...
    for segment in project.segments {
        // ... existing segment hash components ...
        
        // CRITICAL: Include transform effects in hash to trigger rebuild on transform changes
        hasher.combine(segment.effects.scale)
        hasher.combine(segment.effects.positionX)
        hasher.combine(segment.effects.positionY)
        hasher.combine(segment.effects.rotation)
        hasher.combine(segment.transform.scaleToFillFrame)
    }
    // ... rest of hash calculation ...
}
```

---

## Transform Calculation Logic

### Transform Order

**CRITICAL:** Transform concatenation order matters! In `CGAffineTransform`, when you do `A.concatenating(B)`, the result is `A * B`, meaning **B is applied first, then A**.

We want the visual order to be:
1. Preferred Transform (source rotation/flip)
2. Position Translation
3. Rotation
4. Manual Scale
5. Scale to Fill Frame

So we build the transform in **reverse order**:

```swift
var transform = CGAffineTransform.identity

// Step 1: Scale to Fill Frame (applied first in visual chain, last in concatenation)
if segment.transform.scaleToFillFrame {
    let scaleToFillTransform = transformForScaleToFill(...)
    transform = transform.concatenating(scaleToFillTransform)
}

// Step 2: Manual Scale (around center)
if manualScale != 1.0 {
    // Translate to center, scale, translate back
    var scaleTransform = CGAffineTransform.identity
    scaleTransform = scaleTransform.translatedBy(x: centerX, y: centerY)
    scaleTransform = scaleTransform.scaledBy(x: manualScale, y: manualScale)
    scaleTransform = scaleTransform.translatedBy(x: -centerX, y: -centerY)
    transform = transform.concatenating(scaleTransform)
}

// Step 3: Rotation (around center)
if rotationDegrees != 0.0 {
    // Translate to center, rotate, translate back
    var rotationTransform = CGAffineTransform.identity
    rotationTransform = rotationTransform.translatedBy(x: centerX, y: centerY)
    rotationTransform = rotationTransform.rotated(by: rotationRadians)
    rotationTransform = rotationTransform.translatedBy(x: -centerX, y: -centerY)
    transform = transform.concatenating(rotationTransform)
}

// Step 4: Position Translation
if translationX != 0.0 || translationY != 0.0 {
    let positionTransform = CGAffineTransform(translationX: translationX, y: translationY)
    transform = transform.concatenating(positionTransform)
}

// Step 5: Preferred Transform (applied last in visual chain, first in concatenation)
transform = transform.concatenating(track.preferredTransform)
```

### Coordinate System

- **Source Size**: `track.naturalSize` (after preferredTransform is applied)
- **Project Size**: `project.resolution.width × project.resolution.height`
- **Center Point**: `(projWidth / 2.0, projHeight / 2.0)`
- **Position Values**: Percentage-based (-100% to +100%)
  - `-100%` = move left/up by full frame width/height
  - `+100%` = move right/down by full frame width/height
  - Conversion: `translationX = (positionX / 100.0) * projWidth`

### Scale to Fill Frame Calculation

```swift
private func transformForScaleToFill(sourceSize: CGSize, projectSize: CGSize) -> CGAffineTransform {
    let srcWidth = abs(sourceSize.width)
    let srcHeight = abs(sourceSize.height)
    let projWidth = projectSize.width
    let projHeight = projectSize.height
    
    // Calculate scale factor to fill frame (scale to cover, not fit)
    let scaleX = projWidth / srcWidth
    let scaleY = projHeight / srcHeight
    let scale = max(scaleX, scaleY)  // Use larger scale to ensure full coverage
    
    // Calculate scaled dimensions
    let scaledWidth = srcWidth * scale
    let scaledHeight = srcHeight * scale
    
    // Center the scaled image in the project frame
    let tx = (projWidth - scaledWidth) / 2.0
    let ty = (projHeight - scaledHeight) / 2.0
    
    // Build transform: scale first, then translate
    var t = CGAffineTransform.identity
    t = t.scaledBy(x: scale, y: scale)
    t = t.translatedBy(x: tx / scale, y: ty / scale)
    
    return t
}
```

---

## Real-Time Preview Updates

### Immediate Rebuild Strategy

Transform changes trigger **immediate rebuilds** (not debounced) to enable real-time preview:

1. **Detection**: `updateSegment` detects transform changes by checking if any transform property differs from default
2. **Immediate Rebuild**: Calls `immediateRebuild()` instead of `debouncedRebuild()`
3. **Hash Update**: `projectHash` includes transform properties, so changes are detected
4. **Composition Rebuild**: `PlayerViewModel.rebuildComposition` rebuilds the entire composition
5. **Preview Update**: Preview views observe `PlayerViewModel` directly, so they update automatically

### Rebuild Flow

```
User moves slider in InspectorPanel
    ↓
updateSegmentEffects() called
    ↓
updateSegmentImmediate() called
    ↓
immediateRebuild() called
    ↓
playerViewModel.rebuildComposition() called
    ↓
buildComposition() creates new AVMutableComposition
    ↓
TransitionService.calculateCompleteTransform() calculates transform
    ↓
AVMutableVideoCompositionLayerInstruction.setTransform() applies transform
    ↓
PlayerViewModel updates playerItem
    ↓
Preview views observe PlayerViewModel and update automatically
```

---

## UI Integration

### Inspector Panel Controls

The transform controls are in the "Transform" section of the Inspector panel:

1. **Scale to Fill Frame Button**: Toggles `scaleToFillFrame` property
2. **Scale Slider**: Range 0.5 to 3.0, default 1.0
3. **Position X Slider**: Range -100.0 to +100.0, default 0.0
4. **Position Y Slider**: Range -100.0 to +100.0, default 0.0
5. **Rotation Slider**: Range -180.0° to +180.0°, default 0.0°
6. **Reset Transform Button**: Resets all transform properties to defaults

### Slider Bindings

All sliders use the same pattern:

```swift
Slider(
    value: Binding(
        get: { selectedSegment.effects.scale },
        set: { newValue in
            updateSegmentEffects { effects in
                effects.scale = newValue
            }
        }
    ),
    in: 0.5...3.0
)
```

This ensures every slider movement triggers `updateSegmentEffects`, which calls `updateSegmentImmediate`, which triggers `immediateRebuild()`.

---

## Preview Observation Rule Compliance

**CRITICAL:** All preview-related views must observe `PlayerViewModel` directly, not through `ProjectViewModel`.

### Verified Compliance

✅ **PreviewPanel.swift**: `@ObservedObject private var playerViewModel: PlayerViewModel`  
✅ **TimeRulerView.swift**: `@ObservedObject var playerViewModel: PlayerViewModel`  
✅ **PlayheadIndicator.swift**: `@ObservedObject var playerVM: PlayerViewModel`  
✅ **EnhancedTimelineView.swift**: `@ObservedObject private var playerViewModel: PlayerViewModel`  
✅ **TimelineTrackView.swift**: `@ObservedObject var playerViewModel: PlayerViewModel`  
✅ **TimelineSegmentView.swift**: `@ObservedObject var playerViewModel: PlayerViewModel`

### Why This Matters

When transform changes trigger `immediateRebuild()`, the composition is rebuilt in `PlayerViewModel`. If preview views only observed `ProjectViewModel`, they wouldn't detect the composition change because `ProjectViewModel` doesn't have `@Published` properties that change when `PlayerViewModel` changes.

By observing `PlayerViewModel` directly, preview views detect changes to:
- `playerViewModel.duration` (changes when composition is rebuilt)
- `playerViewModel.playerItem` (changes when composition is rebuilt)
- `playerViewModel.currentTime` (updates during playback)

---

## Transform Order and Coordinate System

### Visual Transform Order (What User Sees)

1. **Preferred Transform**: Source video rotation/flip (e.g., portrait video rotated to landscape)
2. **Position Translation**: Move video left/right/up/down
3. **Rotation**: Rotate video around center
4. **Manual Scale**: Scale video up/down around center
5. **Scale to Fill Frame**: Auto-scale to fill frame (if enabled)

### Concatenation Order (Code Implementation)

Since `A.concatenating(B)` means "apply B first, then A", we build in reverse:

1. Start with identity
2. Concatenate Scale to Fill Frame
3. Concatenate Manual Scale
4. Concatenate Rotation
5. Concatenate Position Translation
6. Concatenate Preferred Transform (last)

### Center Point Calculations

All transforms that rotate or scale around center use:
- `centerX = projWidth / 2.0`
- `centerY = projHeight / 2.0`

This ensures transforms are applied around the center of the **project frame**, not the source video frame.

---

## Testing Checklist

### Basic Functionality

- [ ] Scale slider moves video larger/smaller in real-time
- [ ] Position X slider moves video left/right in real-time
- [ ] Position Y slider moves video up/down in real-time
- [ ] Rotation slider rotates video around center in real-time
- [ ] Scale to Fill Frame button scales video to fill frame without black bars
- [ ] Reset Transform button resets all properties to defaults

### Edge Cases

- [ ] Transform works with portrait videos (preferredTransform applied)
- [ ] Transform works with landscape videos
- [ ] Transform works with square videos
- [ ] Multiple transforms can be combined (e.g., scale + rotation + position)
- [ ] Transform persists after switching segments
- [ ] Transform persists after closing and reopening project

### Real-Time Preview

- [ ] Moving any slider updates preview immediately (no delay)
- [ ] Preview doesn't freeze or stutter during transform changes
- [ ] Playback continues smoothly during transform changes
- [ ] Transform changes are visible in both preview and export

### Performance

- [ ] Multiple rapid slider movements don't cause crashes
- [ ] Composition rebuilds complete within reasonable time (< 1 second)
- [ ] Memory usage doesn't increase during transform changes

---

## Troubleshooting

### Transform Not Visible in Preview

**Symptoms:** Slider changes don't update preview

**Possible Causes:**
1. `updateSegmentImmediate` not being called
2. `immediateRebuild()` not triggering
3. `projectHash` not detecting changes
4. Preview view not observing `PlayerViewModel` directly

**Debug Steps:**
1. Check console logs for "immediateRebuild" messages
2. Verify `projectHash` includes transform properties
3. Verify preview view has `@ObservedObject var playerViewModel: PlayerViewModel`
4. Check if `rebuildComposition` is being called

### Transform Applied Incorrectly

**Symptoms:** Video appears in wrong position, wrong size, or wrong rotation

**Possible Causes:**
1. Transform concatenation order incorrect
2. Center point calculation wrong
3. Coordinate system mismatch
4. PreferredTransform not being applied

**Debug Steps:**
1. Check `calculateCompleteTransform` transform order
2. Verify center point uses project dimensions, not source dimensions
3. Check if `track.preferredTransform` is being applied last
4. Verify `transformForScaleToFill` calculation

### Preview Freezes During Transform Changes

**Symptoms:** Preview stops updating or becomes unresponsive

**Possible Causes:**
1. Too many rapid rebuilds
2. Composition rebuild taking too long
3. Memory issues
4. Threading issues

**Debug Steps:**
1. Check if `immediateRebuild` is being called too frequently
2. Add debouncing for rapid slider movements (if needed)
3. Check memory usage during rebuilds
4. Verify all UI updates are on main thread

### Reset Transform Not Working

**Symptoms:** Reset button doesn't reset all properties

**Possible Causes:**
1. `scaleToFillFrame` not being reset
2. `updateSegmentImmediate` not being called
3. Segment not being updated correctly

**Debug Steps:**
1. Verify Reset Transform button resets all 5 properties
2. Check if `updateSegmentImmediate` is called
3. Verify segment is updated in `project.segments` array

---

## Key Implementation Details

### Why Immediate Rebuild for Transforms?

Transform effects need real-time visual feedback. Using `debouncedRebuild()` would introduce a delay (typically 0.1-0.3 seconds), making the UI feel unresponsive. `immediateRebuild()` triggers composition rebuild immediately, enabling real-time preview.

### Why Include Transform in projectHash?

The `projectHash` is used to detect when the project has changed and needs a composition rebuild. Without including transform properties, changes to scale, position, rotation, or `scaleToFillFrame` wouldn't trigger a rebuild, and the preview wouldn't update.

### Why Always Apply Transform?

Even when all transform values are at defaults, we still call `setTransform()` with the calculated transform. This ensures consistent behavior and handles edge cases where the preferredTransform alone might not be sufficient.

### Why Reverse Transform Order?

CGAffineTransform concatenation applies transforms right-to-left. To achieve the desired visual order (preferredTransform → position → rotation → scale → scaleToFill), we must concatenate in reverse order (scaleToFill → scale → rotation → position → preferredTransform).

---

## Summary

The transform effects system is fully implemented with:

✅ Complete transform calculation combining all effects  
✅ Real-time preview updates via immediate rebuilds  
✅ UI controls for all transform properties  
✅ Reset functionality for all properties  
✅ Preview Observation Rule compliance  
✅ Proper transform order and coordinate system  
✅ Hash-based change detection for rebuilds  

All changes maintain compatibility with existing code and follow the Preview Observation Rule to ensure preview updates work correctly.

---

## Contact for Issues

If transform effects are not working correctly:

1. Check console logs for error messages
2. Verify all files listed in "Files Modified" have the changes described
3. Verify `projectHash` includes transform properties
4. Verify preview views observe `PlayerViewModel` directly
5. Check transform concatenation order in `calculateCompleteTransform`

For additional help, provide:
- Console logs showing rebuild messages
- Screenshot of Inspector panel with transform values
- Description of expected vs. actual behavior

