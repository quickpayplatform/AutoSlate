# Crash Fixes Summary - libRPAC.dylib QoS Tracking

## The Problem

The app crashes in `libRPAC.dylib` (QoS tracking library) when processing many CIContext operations during:
- Frame analysis
- Cinematic scoring  
- Vision framework operations

The crash occurs in the system library's hash table operations, indicating QoS tracking is being overwhelmed.

## Fixes Applied

### 1. Serial Queue with Lower QoS
- Changed queue QoS from `.userInitiated` to `.utility`
- Added `autoreleaseFrequency: .workItem` for better memory cleanup

### 2. Per-Operation CIContext
- Create a fresh `CIContext` for each operation instead of sharing
- Prevents memory corruption from shared state

### 3. Increased Delays
- **Frame Analysis**: 10ms delay between frames
- **Cinematic Scoring**: 50ms delay between frames, 100ms pause every 2 frames
- **Vision Operations**: 50ms delay before Vision operations
- **CIContext Creation**: 100ms delay before creating contexts

### 4. More Frequent Cleanup
- Cleanup every 5 frames (instead of 20)
- 50ms pause after every cleanup
- Aggressive `autoreleasepool` usage

### 5. Batch Processing
- Process frames in smaller batches
- Pause between batches to prevent overwhelming QoS tracking

## Current Status

Despite all these fixes, the crash **still occurs** because:
- The system library (`libRPAC.dylib`) has internal bugs
- QoS tracking is system-level and hard to control
- Even with delays, rapid operations can overwhelm it

## Recommendations

### Option 1: Further Increase Delays (Slower but More Stable)
- Increase to 100ms+ between frames
- Add 200ms pause every frame
- Will make processing much slower but more stable

### Option 2: Reduce Frame Count
- Reduce `Config.framesPerSegment` from 5 to 2-3
- Sample fewer frames for cinematic scoring
- Less accurate but fewer operations = fewer crashes

### Option 3: Disable Cinematic Scoring Temporarily
- Skip cinematic scoring entirely
- Use simpler quality metrics
- Avoids the problematic operations altogether

### Option 4: Process in Background Service
- Move frame analysis to a separate process
- Isolate crashes from main app
- Restart service if it crashes

## Files Modified

- `SkipSlate/Services/FrameAnalysisService.swift` - Added delays and serialization
- `SkipSlate/Services/CinematicScoringEngine.swift` - Added delays and batch processing
- `SkipSlate/Services/HighlightReelVisualAnalyzer.swift` - Uses per-operation contexts

## Next Steps

The crash is in a system library, making it hard to fully fix from application code. The best approach is likely:
1. **Reduce frame count** (quick fix)
2. **Further increase delays** (more stable, slower)
3. **Add retry logic** (recover from crashes)

