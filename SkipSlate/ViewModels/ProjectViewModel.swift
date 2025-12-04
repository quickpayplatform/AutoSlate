//
//  ProjectViewModel.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Project State Management (Central Coordinator)
//  - Owns Project data model and PlayerViewModel
//  - Coordinates communication between modules:
//    * Media Import → adds clips to project.clips
//    * Auto Edit → adds segments to project.segments → triggers composition rebuild
//    * Timeline → modifies segments → triggers composition rebuild
//    * Preview → reads PlayerViewModel for playback
//    * Export → reads Project data independently
//  - Does NOT contain UI-specific logic
//  - Provides clear, high-level methods for module communication
//

import SwiftUI
import AVFoundation

class ProjectViewModel: ObservableObject {
    @Published var project: Project
    @Published var selectedSegment: Segment?
    @Published var selectedSegmentIDs: Set<Segment.ID> = []  // Multi-selection support
    @Published var isAutoEditing: Bool = false
    @Published var autoEditStatus: String = ""
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0.0
    @Published var autoEditSettings: AutoEditSettings = .default
    @Published var autoEditError: String?
    
    // Time estimation for auto-edit
    @Published var autoEditTimeEstimate: String? = nil  // e.g., "Estimated time remaining: 5 minutes"
    private var autoEditStartTime: Date?
    private var autoEditProgress: (completed: Int, total: Int) = (0, 0)
    @Published var timelineZoom: Double = 1.0  // Timeline zoom level
    @Published var trackHeights: [UUID: CGFloat] = [:]  // Track ID -> height in points
    // NOTE: selectedTimelineTool moved to ToolState.shared - completely isolated from player/preview
    
    // Rerun Auto-Edit tracking
    @Published var hasUserModifiedAutoEdit: Bool = false  // True when user manually edits the timeline
    @Published var lastAutoEditRunID: UUID?  // Track previous auto-edit run
    
    // Undo/Redo support - custom snapshot-based system
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // Project snapshot for undo/redo
    struct ProjectSnapshot {
        let project: Project
        let selectedSegmentID: Segment.ID?
        let currentTime: Double
    }
    
    private var undoStack: [ProjectSnapshot] = [] {
        didSet {
            canUndo = !undoStack.isEmpty
        }
    }
    private var redoStack: [ProjectSnapshot] = [] {
        didSet {
            canRedo = !redoStack.isEmpty
        }
    }
    
    // MARK: - Copy/Paste Support
    
    /// Clipboard for copied segments - stores segment data for pasting
    @Published var copiedSegments: [Segment] = []
    @Published var canPaste: Bool = false
    
    /// Copy selected segments to clipboard
    func copySelectedSegments() {
        guard !selectedSegmentIDs.isEmpty else {
            print("SkipSlate: ⚠️ No segments selected to copy")
            return
        }
        
        // Get all selected segments
        copiedSegments = project.segments.filter { selectedSegmentIDs.contains($0.id) }
        canPaste = !copiedSegments.isEmpty
        
        print("SkipSlate: ✅ Copied \(copiedSegments.count) segment(s) to clipboard")
    }
    
    /// Paste copied segments at the current playhead position
    func pasteSegments(at time: Double? = nil) {
        guard !copiedSegments.isEmpty else {
            print("SkipSlate: ⚠️ No segments in clipboard to paste")
            return
        }
        
        let pasteTime = time ?? playerVM.currentTime
        
        performUndoableChange("Paste segments") {
            for copiedSegment in copiedSegments {
                // Skip gap segments - only paste clip segments
                guard copiedSegment.isClip, let sourceClipID = copiedSegment.sourceClipID else { continue }
                
                // Create a new segment with a new ID but same properties
                let newSegment = Segment(
                    id: UUID(),
                    sourceClipID: sourceClipID,
                    sourceStart: copiedSegment.sourceStart,
                    sourceEnd: copiedSegment.sourceEnd,
                    enabled: copiedSegment.enabled,
                    colorIndex: copiedSegment.colorIndex,
                    effects: copiedSegment.effects,
                    compositionStartTime: pasteTime,
                    transform: copiedSegment.transform
                )
                
                // Add to project segments
                project.segments.append(newSegment)
                
                // Find the appropriate track (same kind as original)
                if let originalTrack = trackForSegment(copiedSegment.id) {
                    // Find a track of the same kind
                    if let targetTrackIndex = project.tracks.firstIndex(where: { $0.kind == originalTrack.kind }) {
                        project.tracks[targetTrackIndex].segments.append(newSegment.id)
                        print("SkipSlate: ✅ Pasted segment to track \(project.tracks[targetTrackIndex].kind) at \(pasteTime)s")
                    }
                } else {
                    // Fallback: add to first video track
                    if let firstVideoTrackIndex = project.tracks.firstIndex(where: { $0.kind == .video }) {
                        project.tracks[firstVideoTrackIndex].segments.append(newSegment.id)
                        print("SkipSlate: ✅ Pasted segment to V1 at \(pasteTime)s")
                    }
                }
            }
        }
        
        immediateRebuild()
    }
    
    /// Duplicate selected segments (copy + paste in place, offset by duration)
    func duplicateSelectedSegments() {
        guard !selectedSegmentIDs.isEmpty else {
            print("SkipSlate: ⚠️ No segments selected to duplicate")
            return
        }
        
        performUndoableChange("Duplicate segments") {
            for segmentID in selectedSegmentIDs {
                guard let segment = project.segments.first(where: { $0.id == segmentID }),
                      segment.isClip,
                      let sourceClipID = segment.sourceClipID else { continue }
                
                // Create duplicate with new ID, placed right after original
                let duplicate = Segment(
                    id: UUID(),
                    sourceClipID: sourceClipID,
                    sourceStart: segment.sourceStart,
                    sourceEnd: segment.sourceEnd,
                    enabled: segment.enabled,
                    colorIndex: segment.colorIndex,
                    effects: segment.effects,
                    compositionStartTime: segment.compositionStartTime + segment.duration,
                    transform: segment.transform
                )
                
                // Add to project
                project.segments.append(duplicate)
                
                // Add to same track as original
                if let trackIndex = project.tracks.firstIndex(where: { $0.segments.contains(segmentID) }) {
                    project.tracks[trackIndex].segments.append(duplicate.id)
                    print("SkipSlate: ✅ Duplicated segment at \(duplicate.compositionStartTime)s")
                }
            }
        }
        
        immediateRebuild()
    }
    
    // MARK: - Grid Snapping
    
    /// Grid interval in seconds (snap segments to this interval)
    var gridInterval: Double {
        // Base grid: 0.5 seconds (half-second marks)
        // Can be made configurable later
        return 0.5
    }
    
    /// Snap a time value to the nearest grid point
    func snapToGrid(_ time: Double) -> Double {
        let snapped = round(time / gridInterval) * gridInterval
        return max(0, snapped)
    }
    
    // MARK: - Undo/Redo Implementation
    
    private func makeSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            project: project,
            selectedSegmentID: selectedSegment?.id,
            currentTime: playerVM.currentTime
        )
    }
    
    private func restoreSnapshot(_ snapshot: ProjectSnapshot) {
        self.project = snapshot.project
        
        if let id = snapshot.selectedSegmentID {
            self.selectedSegment = project.segments.first(where: { $0.id == id })
        } else {
            self.selectedSegment = nil
        }
        
        playerVM.seek(to: snapshot.currentTime, precise: true)
        immediateRebuild()
    }
    
    func performUndoableChange(_ description: String = "", change: () -> Void) {
        let snapshotBefore = makeSnapshot()
        undoStack.append(snapshotBefore)
        redoStack.removeAll() // clear redo on new edit
        
        print("SkipSlate: [Undo DEBUG] push undo – \(description), stack size = \(undoStack.count)")
        
        change()
        
        // CRITICAL: Trigger UI update so timeline views refresh
        objectWillChange.send()
        
        // After change, rebuild composition
        immediateRebuild()
    }
    
    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let current = makeSnapshot()
        redoStack.append(current)
        
        print("SkipSlate: [Undo DEBUG] undo – new undoStack size = \(undoStack.count), redoStack size = \(redoStack.count)")
        
        restoreSnapshot(snapshot)
    }
    
    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let current = makeSnapshot()
        undoStack.append(current)
        
        print("SkipSlate: [Undo DEBUG] redo – new undoStack size = \(undoStack.count), redoStack size = \(redoStack.count)")
        
        restoreSnapshot(snapshot)
    }
    
    private var playerViewModel: PlayerViewModel?
    private let autoEditService = AutoEditService.shared
    private var assetsByClipID: [UUID: AVAsset] = [:]
    
    // Quality score cache: clipID -> average quality score (0.0-1.0)
    @Published var clipQualityScores: [UUID: Float] = [:]
    @Published var isAnalyzingQuality: Bool = false
    @Published var qualityAnalysisProgress: (current: Int, total: Int) = (0, 0)
    
    // Temporary storage for analyzed segments and clips (for gap filling)
    @Published var cachedAnalyzedSegments: [Segment] = []  // All segments from last Auto Edit run - PUBLISHED for UI updates
    @Published var cachedAnalyzedClipIDs: Set<UUID> = []  // Clips that have been analyzed - PUBLISHED for UI updates
    @Published var deletedClipIDs: Set<UUID> = []         // Clip IDs that were deleted - exclude from rerun - PUBLISHED for UI updates
    @Published var selectedClipIDs: Set<UUID> = []     // Clip IDs that are favorited/selected for rerun
    
    // MARK: - Cached Segments Access (for Media tab)
    
    /// Get all cached analyzed segments (for Media tab display)
    var allCachedSegments: [Segment] {
        cachedAnalyzedSegments.filter { segment in
            // Exclude deleted clips
            guard let clipID = segment.clipID else { return false }
            return !deletedClipIDs.contains(clipID)
        }
    }
    
    /// Get a cached segment by ID for drag-and-drop
    func getCachedSegment(by id: UUID) -> Segment? {
        return allCachedSegments.first { $0.id == id }
    }
    
    /// Add a segment to the timeline at a specific composition start time
    func addSegmentToTimeline(_ segment: Segment, at compositionStartTime: Double) {
        // Ensure segment has a valid clip ID
        guard let sourceClipID = segment.sourceClipID else {
            print("SkipSlate: ⚠️ Cannot add segment without sourceClipID")
            return
        }
        
        // Wrap in undoable change
        performUndoableChange("Add segment to timeline") {
            // Create a new segment instance with the specified composition start time
            let newSegment = Segment(
                id: UUID(), // New ID for the timeline instance
                sourceClipID: sourceClipID,
                sourceStart: segment.sourceStart,
                sourceEnd: segment.sourceEnd,
                enabled: segment.enabled,
                colorIndex: segment.colorIndex,
                effects: segment.effects,
                compositionStartTime: compositionStartTime
            )
            
            // Add to project segments
            project.segments.append(newSegment)
            
            // Find appropriate track and add segment ID to it
            // For now, add to the first video track (or create one if needed)
            // CRITICAL: Auto-edit and manual segment addition should use V1 (base video track)
            // Find or create the base video track (kind: .video, index: 0)
            if let baseVideoTrackIndex = project.tracks.firstIndex(where: { $0.kind == .video && $0.index == 0 }) {
                // Add to existing V1 track
                if !project.tracks[baseVideoTrackIndex].segments.contains(newSegment.id) {
                    project.tracks[baseVideoTrackIndex].segments.append(newSegment.id)
                }
            } else {
                // Create V1 track if it doesn't exist
                let videoTrack = TimelineTrack(
                    kind: .video,
                    index: 0,
                    segments: [newSegment.id]
                )
                project.tracks.append(videoTrack)
            }
            
            hasUserModifiedAutoEdit = true
        }
        print("SkipSlate: ✅ Added segment to timeline at \(compositionStartTime)s")
    }
    
    /// Move a segment to a new position in the timeline
    /// CRASH-PROOF: Comprehensive validation and error handling
    func moveSegment(_ segmentID: Segment.ID, to newCompositionStartTime: Double) {
        print("SkipSlate: [Move DEBUG] moveSegment id=\(segmentID) to time=\(newCompositionStartTime)")
        
        // CRASH-PROOF: Validate inputs
        guard newCompositionStartTime >= 0 && newCompositionStartTime.isFinite else {
            print("SkipSlate: ⚠️ Cannot move segment - invalid composition start time: \(newCompositionStartTime)")
            return
        }
        
        // CRASH-PROOF: Find segment in project
        guard let segmentIndex = project.segments.firstIndex(where: { $0.id == segmentID }) else {
            print("SkipSlate: ⚠️ Cannot move segment - segment not found: \(segmentID)")
            return
        }
        
        let segment = project.segments[segmentIndex]
        
        // CRASH-PROOF: Only allow moving clip segments (not gaps)
        guard segment.isClip else {
            print("SkipSlate: ⚠️ Cannot move gap segment")
            return
        }
        
        // CRASH-PROOF: Validate segment duration
        guard segment.duration > 0.01 && segment.duration.isFinite else {
            print("SkipSlate: ⚠️ Cannot move segment - invalid duration: \(segment.duration)")
            return
        }
        
        // Calculate new end time
        let newEndTime = newCompositionStartTime + segment.duration
        
        // CRASH-PROOF: Check for overlaps with other segments
        let overlappingSegments = project.segments.filter { otherSegment in
            // Skip self
            guard otherSegment.id != segmentID else { return false }
            
            // Skip gaps (gaps can overlap, they represent black)
            guard otherSegment.isClip else { return false }
            
            let otherStart = otherSegment.compositionStartTime
            let otherEnd = otherStart + otherSegment.duration
            
            // Check if new position overlaps with this segment
            let overlaps = (newCompositionStartTime < otherEnd && newEndTime > otherStart)
            
            return overlaps
        }
        
        if !overlappingSegments.isEmpty {
            print("SkipSlate: ⚠️ Warning: Moving segment to \(newCompositionStartTime)s will overlap with \(overlappingSegments.count) segment(s)")
            // Continue anyway - user may want to overlap (it will layer)
        }
        
        // Wrap in undoable change
        performUndoableChange("Move segment") {
            // Update segment composition start time
            updateSegmentCompositionStartTime(segmentID, newStartTime: max(0.0, newCompositionStartTime))
            
            // Mark as modified
            hasUserModifiedAutoEdit = true
        }
        
        print("SkipSlate: ✅ Moved segment \(segmentID) to composition time \(newCompositionStartTime)s")
    }
    
    /// Update a segment's composition start time (used during drag operations)
    /// CRASH-PROOF: Lightweight update for real-time dragging feedback
    /// IMPORTANT: Only edits the segment, nothing else - no auto-compacting or neighbor adjustments
    func updateSegmentCompositionStartTime(_ segmentID: Segment.ID, newStartTime: Double) {
        guard let idx = project.segments.firstIndex(where: { $0.id == segmentID }) else {
            print("SkipSlate: [Move DEBUG] updateSegmentCompositionStartTime – segment not found id=\(segmentID)")
            return
        }
        
        print("SkipSlate: [Move DEBUG] Before move – segment index=\(idx), oldStart=\(project.segments[idx].compositionStartTime)")
        project.segments[idx].compositionStartTime = newStartTime
        print("SkipSlate: [Move DEBUG] After move – segment index=\(idx), newStart=\(project.segments[idx].compositionStartTime)")
    }
    
    /// Request immediate rebuild after a timeline edit (segment move, etc.)
    func requestImmediateRebuildAfterTimelineEdit(reason: String) {
        print("SkipSlate: [Move DEBUG] requestImmediateRebuildAfterTimelineEdit – reason=\(reason)")
        immediateRebuild()
    }
    
    /// Get cached analyzed segments grouped by clip ID
    var cachedSegmentsByClip: [UUID: [Segment]] {
        var grouped: [UUID: [Segment]] = [:]
        for segment in cachedAnalyzedSegments {
            guard let clipID = segment.clipID else { continue }
            if grouped[clipID] == nil {
                grouped[clipID] = []
            }
            grouped[clipID]?.append(segment)
        }
        return grouped
    }
    
    /// Get all cached clip IDs
    var availableCachedClipIDs: Set<UUID> {
        cachedAnalyzedClipIDs
    }
    
    /// Check if a clip is deleted
    func isClipDeleted(_ clipID: UUID) -> Bool {
        deletedClipIDs.contains(clipID)
    }
    
    /// Check if a clip is selected/favorited
    func isClipSelected(_ clipID: UUID) -> Bool {
        selectedClipIDs.contains(clipID)
    }
    
    /// Toggle clip selection/favorite
    func toggleClipSelection(_ clipID: UUID) {
        if selectedClipIDs.contains(clipID) {
            selectedClipIDs.remove(clipID)
        } else {
            selectedClipIDs.insert(clipID)
        }
    }
    
    // MARK: - Per-Segment Favoriting
    
    /// Set of favorited segment IDs (for rerun prioritization)
    @Published var favoritedSegmentIDs: Set<Segment.ID> = []
    
    /// Currently previewed segment ID (for highlighting in Media tab)
    @Published var previewedSegmentID: Segment.ID? = nil
    
    /// Check if a segment is favorited
    func isSegmentFavorited(_ segmentID: Segment.ID) -> Bool {
        favoritedSegmentIDs.contains(segmentID)
    }
    
    /// Toggle segment favorite status
    /// CRASH-PROOF: Validates segment exists before toggling
    func toggleSegmentFavorite(_ segmentID: Segment.ID) {
        // CRASH-PROOF: Verify segment exists in cache or timeline
        let segmentExists = cachedAnalyzedSegments.contains(where: { $0.id == segmentID }) ||
                           project.segments.contains(where: { $0.id == segmentID })
        
        guard segmentExists else {
            print("SkipSlate: ⚠️ Cannot favorite segment - segment not found: \(segmentID)")
            return
        }
        
        if favoritedSegmentIDs.contains(segmentID) {
            favoritedSegmentIDs.remove(segmentID)
            print("SkipSlate: ⭐ Removed segment \(segmentID) from favorites")
        } else {
            favoritedSegmentIDs.insert(segmentID)
            print("SkipSlate: ⭐ Added segment \(segmentID) to favorites")
        }
    }
    
    /// Remove clip from cache (marks as deleted and removes from cached segments)
    func removeClipFromCache(_ clipID: UUID) {
        // Mark as deleted (excludes from rerun)
        deletedClipIDs.insert(clipID)
        // Remove from selected if it was selected
        selectedClipIDs.remove(clipID)
        // Remove segments from cache
        cachedAnalyzedSegments.removeAll { $0.clipID == clipID }
        cachedAnalyzedClipIDs.remove(clipID)
        print("SkipSlate: 🗑️ Removed clip \(clipID) from cache")
    }
    
    /// Remove a clip from the project completely
    /// This removes the clip and converts any segments using it to gap segments
    func removeClip(_ clipID: UUID) {
        // Find the clip
        guard let clipIndex = project.clips.firstIndex(where: { $0.id == clipID }),
              let clip = project.clips.first(where: { $0.id == clipID }) else {
            print("SkipSlate: ⚠️ Cannot remove clip - clip not found: \(clipID)")
            return
        }
        
        print("SkipSlate: 🗑️ Starting to remove clip: \(clip.fileName) (ID: \(clipID))")
        
        // Find all segments that use this clip
        let segmentsUsingClip = project.segments.filter { segment in
            segment.clipID == clipID
        }
        
        print("SkipSlate: 🗑️ Found \(segmentsUsingClip.count) segment(s) using this clip")
        
        // Convert segments using this clip to gap segments
        for segmentIndex in project.segments.indices {
            if project.segments[segmentIndex].clipID == clipID {
                let segment = project.segments[segmentIndex]
                // Create gap segment with same timing
                let gapSegment = Segment(
                    id: segment.id, // Keep same ID
                    gapDuration: segment.duration,
                    compositionStartTime: segment.compositionStartTime
                )
                project.segments[segmentIndex] = gapSegment
                print("SkipSlate: 🗑️ Converted segment \(segment.id) to gap segment")
            }
        }
        
        // Remove clip from project
        project.clips.remove(at: clipIndex)
        print("SkipSlate: 🗑️ Removed clip from project.clips array (now \(project.clips.count) clip(s))")
        
        // Remove from cache
        removeClipFromCache(clipID)
        
        // Remove from selected clips
        selectedClipIDs.remove(clipID)
        
        // Mark as modified
        hasUserModifiedAutoEdit = true
        
        // CRITICAL: Trigger UI update BEFORE rebuild
        objectWillChange.send()
        
        // Rebuild composition if there are segments
        if !project.segments.isEmpty {
            print("SkipSlate: 🗑️ Triggering immediate rebuild after clip removal")
            immediateRebuild()
        } else {
            print("SkipSlate: 🗑️ No segments to rebuild")
        }
        
        print("SkipSlate: 🗑️ ✅ Removed clip \(clip.fileName) from project (converted \(segmentsUsingClip.count) segment(s) to gaps)")
    }
    
    // MARK: - Quality Categorized Storage
    
    /// Quality categories for clips
    enum QualityCategory: String {
        case high      // 0.7 - 1.0
        case medium    // 0.5 - 0.7
        case low       // 0.0 - 0.5
        
        var threshold: Float {
            switch self {
            case .high: return 0.7
            case .medium: return 0.5
            case .low: return 0.0
            }
        }
        
        static func category(for score: Float) -> QualityCategory {
            if score >= 0.7 { return .high }
            if score >= 0.5 { return .medium }
            return .low
        }
    }
    
    /// Get clips categorized by quality tier
    func clipsByQuality() -> [QualityCategory: [MediaClip]] {
        var categorized: [QualityCategory: [MediaClip]] = [
            .high: [],
            .medium: [],
            .low: []
        ]
        
        for clip in project.clips {
            let score = clipQualityScores[clip.id] ?? 0.0
            let category = QualityCategory.category(for: score)
            categorized[category]?.append(clip)
        }
        
        return categorized
    }
    
    /// Get all high-quality clips (score >= 0.7)
    func highQualityClips() -> [MediaClip] {
        return project.clips.filter { clip in
            guard let score = clipQualityScores[clip.id] else { return false }
            return score >= 0.7
        }
    }
    
    /// Get all medium-quality clips (0.5 <= score < 0.7)
    func mediumQualityClips() -> [MediaClip] {
        return project.clips.filter { clip in
            guard let score = clipQualityScores[clip.id] else { return false }
            return score >= 0.5 && score < 0.7
        }
    }
    
    /// Get all low-quality clips (score < 0.5)
    func lowQualityClips() -> [MediaClip] {
        return project.clips.filter { clip in
            guard let score = clipQualityScores[clip.id] else { return false }
            return score < 0.5
        }
    }
    
    init(project: Project) {
        self.project = project
        self.playerViewModel = PlayerViewModel(project: project)
    }
    
    /// Accessor for PlayerViewModel - ensures single stable instance
    /// PlayerViewModel is created in init() and should never be nil after initialization
    var playerVM: PlayerViewModel {
        // Safety check: if somehow nil, create it (should never happen after init)
        if playerViewModel == nil {
            print("SkipSlate: ⚠️ WARNING - PlayerViewModel was nil, creating new instance. This should not happen after init.")
            playerViewModel = PlayerViewModel(project: project)
        }
        return playerViewModel!
    }
    
    // MARK: - Project Properties
    
    var projectName: String {
        get { project.name }
        set { project.name = newValue }
    }
    
    var type: ProjectType {
        project.type
    }
    
    var aspectRatio: AspectRatio {
        project.aspectRatio
    }
    
    var resolution: ResolutionPreset {
        project.resolution
    }
    
    var clips: [MediaClip] {
        project.clips
    }
    
    var segments: [Segment] {
        get { project.segments }
        set { project.segments = newValue }
    }
    
    var tracks: [TimelineTrack] {
        get { project.tracks }
        set { project.tracks = newValue }
    }
    
    /// Get all video tracks
    var videoTracks: [TimelineTrack] {
        project.tracks.filter { $0.kind == .video }.sorted { $0.index < $1.index }
    }
    
    /// Get all audio tracks
    var audioTracks: [TimelineTrack] {
        project.tracks.filter { $0.kind == .audio }.sorted { $0.index < $1.index }
    }
    
    // MARK: - Timeline Track Management
    
    /// Get segments for a specific track
    func segments(for track: TimelineTrack) -> [Segment] {
        let segmentDict = Dictionary(uniqueKeysWithValues: project.segments.map { ($0.id, $0) })
        return track.segments.compactMap { segmentDict[$0] }
    }
    
    /// Get all segments in a track, ordered by their position in the track
    func segmentsInOrder(for track: TimelineTrack) -> [Segment] {
        let segmentDict = Dictionary(uniqueKeysWithValues: project.segments.map { ($0.id, $0) })
        return track.segments.compactMap { segmentDict[$0] }
    }
    
    /// Move a segment to a different track at a specific index
    /// SIMPLE: Remove from current track, add to new track (atomic)
    func moveSegment(_ segmentID: Segment.ID, toTrack trackID: TimelineTrack.ID, atIndex newIndex: Int) {
        hasUserModifiedAutoEdit = true
        guard project.segments.first(where: { $0.id == segmentID }) != nil else { return }
        guard let targetIdx = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        
        // Find current track
        guard let currentIdx = project.tracks.firstIndex(where: { $0.segments.contains(segmentID) }) else { return }
        
        // Only move if tracks are same kind
        guard project.tracks[currentIdx].kind == project.tracks[targetIdx].kind else { return }
        
        // Atomic move: remove from current, add to target
        project.tracks[currentIdx].segments.removeAll { $0 == segmentID }
        let clampedIndex = max(0, min(newIndex, project.tracks[targetIdx].segments.count))
        project.tracks[targetIdx].segments.insert(segmentID, at: clampedIndex)
        
        // Defer to avoid "Publishing changes from within view updates"
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            self?.immediateRebuild()
        }
    }
    
    /// Move a segment to a new time position AND optionally to a different track
    /// SIMPLE: Update time, optionally move between tracks of same type
    /// Segment ALWAYS stays in a track - only user delete can remove it
    func moveSegmentToTrackAndTime(_ segmentID: Segment.ID, to newCompositionStartTime: Double, targetTrackID: TimelineTrack.ID?) {
        print("SkipSlate: [Move] segment \(segmentID) to time=\(newCompositionStartTime)")
        
        hasUserModifiedAutoEdit = true
        
        // Validate time
        guard newCompositionStartTime >= 0 && newCompositionStartTime.isFinite else { return }
        
        // Find segment
        guard let segmentIndex = project.segments.firstIndex(where: { $0.id == segmentID }),
              project.segments[segmentIndex].isClip else { return }
        
        // Update time position
        project.segments[segmentIndex].compositionStartTime = newCompositionStartTime
        
        // Handle track change if target specified
        if let targetTrackID = targetTrackID,
           let targetIdx = project.tracks.firstIndex(where: { $0.id == targetTrackID }) {
            
            // Find which track currently has this segment
            if let currentIdx = project.tracks.firstIndex(where: { $0.segments.contains(segmentID) }) {
                // Only move if going to different track of same kind
                if currentIdx != targetIdx && project.tracks[currentIdx].kind == project.tracks[targetIdx].kind {
                    // Remove from current, add to target (atomic operation)
                    project.tracks[currentIdx].segments.removeAll { $0 == segmentID }
                    project.tracks[targetIdx].segments.append(segmentID)
                    print("SkipSlate: ✅ Moved segment from track \(currentIdx) to track \(targetIdx)")
                }
                // If same track or different kind, segment stays where it is
            }
            // Note: If segment not in any track, something is wrong - but we don't orphan here
        }
        
        // Trigger UI update and rebuild - defer to avoid "Publishing changes from within view updates"
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            self?.immediateRebuild()
        }
    }
    
    /// Find which track a segment belongs to
    func trackForSegment(_ segmentID: Segment.ID) -> TimelineTrack? {
        return project.tracks.first { $0.segments.contains(segmentID) }
    }
    
    /// Reorder segments within a track
    func reorderSegment(inTrack trackID: TimelineTrack.ID, fromOffsets: IndexSet, toOffset: Int) {
        // Mark that user has manually modified the auto-edit
        hasUserModifiedAutoEdit = true
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              let sourceIndex = fromOffsets.first,
              sourceIndex < project.tracks[trackIndex].segments.count,
              toOffset <= project.tracks[trackIndex].segments.count else {
            return
        }
        
        var segments = project.tracks[trackIndex].segments
        let movedSegmentID = segments.remove(at: sourceIndex)
        
        let adjustedDestination = sourceIndex < toOffset ? toOffset - 1 : toOffset
        segments.insert(movedSegmentID, at: adjustedDestination)
        
        project.tracks[trackIndex].segments = segments
        immediateRebuild()
    }
    
    /// Add a new video or audio track
    func addTrack(kind: TrackKind) {
        // Get existing tracks of the same kind to determine next index
        let existingTracks = project.tracks.filter { $0.kind == kind }
        let nextIndex = existingTracks.count
        
        // Create new track
        let newTrack = TimelineTrack(
            kind: kind,
            index: nextIndex,
            segments: []
        )
        
        // Insert video tracks after the last video track, not at the end
        // This ensures video tracks stay together (V1, V2, V3...) before audio tracks (A1, A2...)
        if kind == .video {
            // Find the last video track's position
            let lastVideoTrackIndex = project.tracks.lastIndex { $0.kind == .video }
            if let insertIndex = lastVideoTrackIndex {
                project.tracks.insert(newTrack, at: insertIndex + 1)
            } else {
                // No video tracks exist, insert at the beginning
                project.tracks.insert(newTrack, at: 0)
            }
        } else {
            // Audio tracks go at the end
            project.tracks.append(newTrack)
        }
        
        // Update indices of all tracks of the same kind to ensure they're consecutive
        updateTrackIndices(for: kind)
        
        hasUserModifiedAutoEdit = true
        objectWillChange.send()
        
        print("SkipSlate: ✅ Added new \(kind == .video ? "video" : "audio") track at index \(nextIndex)")
    }
    
    /// Update track indices to ensure they're consecutive (0, 1, 2, ...)
    private func updateTrackIndices(for kind: TrackKind) {
        let tracksOfKind = project.tracks.filter { $0.kind == kind }.sorted { $0.index < $1.index }
        for (newIndex, track) in tracksOfKind.enumerated() {
            if let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }) {
                project.tracks[trackIndex].index = newIndex
            }
        }
    }
    
    /// Remove the topmost video track or bottommost audio track
    /// - Parameter kind: The kind of track to remove (.video or .audio)
    /// - Returns: true if a track was removed, false if removal was not possible
    @discardableResult
    func removeTrack(kind: TrackKind) -> Bool {
        let tracksOfKind = project.tracks.filter { $0.kind == kind }
        
        // Don't allow removing the last track of a kind
        guard tracksOfKind.count > 1 else {
            print("SkipSlate: ⚠️ Cannot remove the only \(kind == .video ? "video" : "audio") track")
            return false
        }
        
        // Find the track to remove:
        // - For video: remove the one with highest index (topmost, newest)
        // - For audio: remove the one with highest index (bottommost, newest)
        guard let trackToRemove = tracksOfKind.max(by: { $0.index < $1.index }) else {
            return false
        }
        
        // Remove all segments that belong to this track
        let segmentIDsToRemove = trackToRemove.segments
        project.segments.removeAll { segmentIDsToRemove.contains($0.id) }
        
        // Remove the track
        project.tracks.removeAll { $0.id == trackToRemove.id }
        
        // Update indices to keep them consecutive
        updateTrackIndices(for: kind)
        
        hasUserModifiedAutoEdit = true
        objectWillChange.send()
        
        // Rebuild composition to reflect changes
        immediateRebuild()
        
        print("SkipSlate: ✅ Removed \(kind == .video ? "video" : "audio") track at index \(trackToRemove.index)")
        return true
    }
    
    /// Count of video tracks
    var videoTrackCount: Int {
        project.tracks.filter { $0.kind == .video }.count
    }
    
    /// Count of audio tracks
    var audioTrackCount: Int {
        project.tracks.filter { $0.kind == .audio }.count
    }
    
    // MARK: - Transform Effects
    
    /// Scale selected segments to fill the project frame (no black bars)
    func scaleSelectedSegmentsToFillFrame() {
        let selectedIDs = selectedSegmentIDs.isEmpty && selectedSegment != nil
            ? [selectedSegment!.id]
            : selectedSegmentIDs
        
        guard !selectedIDs.isEmpty else {
            print("SkipSlate: ⚠️ No segments selected for Scale to Fill Frame")
            return
        }
        
        var updatedCount = 0
        
        // Update all selected segments
        for (index, segment) in project.segments.enumerated() {
            if selectedIDs.contains(segment.id) && segment.kind == .clip {
                project.segments[index].transform.scaleToFillFrame = true
                updatedCount += 1
            }
        }
        
        hasUserModifiedAutoEdit = true
        immediateRebuild()
        
        print("SkipSlate: ✅ Applied Scale to Fill Frame to \(updatedCount) segment(s)")
    }
    
    /// Remove Scale to Fill Frame from selected segments
    func removeScaleToFillFrame() {
        let selectedIDs = selectedSegmentIDs.isEmpty && selectedSegment != nil
            ? [selectedSegment!.id]
            : selectedSegmentIDs
        
        guard !selectedIDs.isEmpty else { return }
        
        for (index, segment) in project.segments.enumerated() {
            if selectedIDs.contains(segment.id) {
                project.segments[index].transform.scaleToFillFrame = false
            }
        }
        
        hasUserModifiedAutoEdit = true
        immediateRebuild()
    }
    
    // MARK: - Centralized Delete Logic
    
    /// SIMPLIFIED, RELIABLE deletion - works directly on project without manager
    /// Converts clip segments to gap segments, preserving timeline timing
    func deleteSegments(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { 
            print("SkipSlate: ⚠️ deleteSegments called with empty IDs")
            return 
        }
        
        print("SkipSlate: 🗑️ DELETE called for segments: \(ids)")
        
        // Wrap in undoable change
        performUndoableChange("Delete segments") {
            var deletedCount = 0
            var gapSegmentsCreated: [Segment] = []
            
            // Replace any matching clip segments with gap segments of identical time range
            for index in project.segments.indices.reversed() { // Reverse to avoid index shifting issues
                let seg = project.segments[index]
                guard ids.contains(seg.id) else { continue }
                
                // Only convert clips to gaps; skip gaps
                guard seg.kind == .clip else {
                    print("SkipSlate: ⚠️ Segment \(seg.id) is already a gap, skipping")
                    continue
                }
                
                // Track the clip ID that was deleted (so we don't reuse it in rerun)
                if let deletedClipID = seg.clipID {
                    deletedClipIDs.insert(deletedClipID)
                    print("SkipSlate: 🚫 Marked clip \(deletedClipID) as deleted - will exclude from rerun auto-edit")
                }
                
                // Create gap segment with same time range as the deleted clip
                let gapSegment = Segment(
                    gapDuration: seg.duration,
                    compositionStartTime: seg.compositionStartTime
                )
                
                print("SkipSlate: ✅ Replacing clip segment \(seg.id) with gap segment \(gapSegment.id) (duration: \(seg.duration)s, start: \(seg.compositionStartTime)s)")
                
                // Replace the clip segment with the gap segment
                project.segments[index] = gapSegment
                gapSegmentsCreated.append(gapSegment)
                deletedCount += 1
                
                // Update track references to point to the new gap segment ID
                for (trackIndex, track) in project.tracks.enumerated() {
                    if let segmentIndex = track.segments.firstIndex(of: seg.id) {
                        project.tracks[trackIndex].segments[segmentIndex] = gapSegment.id
                        print("SkipSlate: ✅ Updated track \(trackIndex) reference from \(seg.id) to \(gapSegment.id)")
                    }
                }
            }
            
            print("SkipSlate: ✅ Deleted \(deletedCount) segments, created \(gapSegmentsCreated.count) gap segments")
            
            // Clear selection for deleted segments
            for segmentID in ids {
                if selectedSegment?.id == segmentID {
                    selectedSegment = nil
                    print("SkipSlate: ✅ Cleared selectedSegment")
                }
                selectedSegmentIDs.remove(segmentID)
            }
            
            // CRITICAL: Ensure selectedSegment matches the first selectedSegmentID
            // This keeps them in sync
            if let firstSelectedID = selectedSegmentIDs.first,
               let matchingSegment = project.segments.first(where: { $0.id == firstSelectedID }) {
                selectedSegment = matchingSegment
                print("SkipSlate: ✅ Synced selectedSegment to first selectedSegmentID: \(firstSelectedID)")
            } else if selectedSegmentIDs.isEmpty {
                selectedSegment = nil
            }
            
            print("SkipSlate: ✅ Remaining selectedSegmentIDs: \(selectedSegmentIDs.count)")
            
            // Mark that user has modified auto-edit
            hasUserModifiedAutoEdit = true
        }
        
        print("SkipSlate: ✅ DELETE COMPLETE - segments count: \(project.segments.count)")
    }
    
    /// Delete selected segments - convenience wrapper around deleteSegments(withIDs:)
    /// This is the MAIN function called when user clicks delete button
    func deleteSelectedSegments() {
        print("SkipSlate: 🗑️ deleteSelectedSegments() called")
        print("SkipSlate: 🗑️ selectedSegmentIDs: \(selectedSegmentIDs)")
        print("SkipSlate: 🗑️ selectedSegment?.id: \(selectedSegment?.id.uuidString.prefix(8) ?? "nil")")
        
        // CRITICAL: If selectedSegmentIDs is empty but selectedSegment exists, use selectedSegment
        if selectedSegmentIDs.isEmpty, let seg = selectedSegment {
            print("SkipSlate: 🗑️ selectedSegmentIDs empty, but selectedSegment exists, using it")
            selectedSegmentIDs = [seg.id]
        }
        
        // CRITICAL: If selectedSegmentIDs has IDs but selectedSegment doesn't match, sync them
        if let firstID = selectedSegmentIDs.first,
           (selectedSegment?.id != firstID || selectedSegment == nil) {
            if let segment = project.segments.first(where: { $0.id == firstID }) {
                selectedSegment = segment
                print("SkipSlate: 🗑️ Synced selectedSegment to match first selectedSegmentID")
            }
        }
        
        guard !selectedSegmentIDs.isEmpty else {
            print("SkipSlate: ⚠️ Cannot delete - no segments selected")
            return
        }
        
        deleteSegments(withIDs: selectedSegmentIDs)
    }
    
    /// Remove a single segment - convenience wrapper
    func removeSegment(_ segmentID: Segment.ID) {
        deleteSegments(withIDs: [segmentID])
    }
    
    /// Notify that composition needs to be rebuilt
    private func notifyCompositionNeedsRebuild() {
        immediateRebuild()
    }
    
    /// Get the track that contains a segment
    func track(containing segmentID: Segment.ID) -> TimelineTrack? {
        return project.tracks.first { $0.segments.contains(segmentID) }
    }
    
    /// Get the index of a segment within its track
    func indexOfSegment(_ segmentID: Segment.ID, in track: TimelineTrack) -> Int? {
        return track.segments.firstIndex(of: segmentID)
    }
    
    var audioSettings: AudioSettings {
        get { project.audioSettings }
        set { project.audioSettings = newValue }
    }
    
    var colorSettings: ColorSettings {
        get { project.colorSettings }
        set { 
            project.colorSettings = newValue
            playerViewModel?.updateColorSettings(newValue)
        }
    }
    
    // MARK: - Debug Functions
    
    /// Debug function to play the first video clip raw (bypasses composition)
    /// This helps verify the preview view is wired correctly
    func debugPlayFirstClipRaw() {
        guard let firstClip = project.clips.first else {
            print("SkipSlate: DEBUG - No clips available to play raw.")
            return
        }
        
        print("SkipSlate: DEBUG - Playing first clip raw: \(firstClip.fileName)")
        print("SkipSlate: DEBUG - Clip type: \(firstClip.type), hasAudioTrack: \(firstClip.hasAudioTrack)")
        
        // Use the existing playFirstClipRawForDebug method in PlayerViewModel
        playerVM.playFirstClipRawForDebug()
    }
    
    /// Self-test: Build a minimal composition and verify audio works
    func runAudioSelfTest() async {
        print("SkipSlate: ===== AUDIO SELF-TEST START ======")
        
        // Find a clip with audio
        guard let testClip = project.clips.first(where: { $0.hasAudioTrack }) else {
            print("SkipSlate: Self-test FAILED - No clips with audio found")
            print("SkipSlate: Available clips: \(project.clips.map { "\($0.fileName) (hasAudioTrack=\($0.hasAudioTrack))" })")
            return
        }
        
        print("SkipSlate: Self-test - Using clip: \(testClip.fileName)")
        
        // Create a minimal test project
        var testProject = project
        testProject.segments = [
            Segment(
                id: UUID(),
                sourceClipID: testClip.id,
                sourceStart: 0.0,
                sourceEnd: min(5.0, testClip.duration), // Test with first 5 seconds
                enabled: true,
                colorIndex: 0
            )
        ]
        
        // Build composition
        do {
            let composition = try await playerVM.buildComposition(from: testProject)
            let audioTracks = composition.tracks(withMediaType: .audio)
            
            print("SkipSlate: Self-test - Composition built")
            print("SkipSlate: Self-test - Audio tracks: \(audioTracks.count)")
            
            if audioTracks.isEmpty {
                print("SkipSlate: Self-test FAILED - Composition has no audio tracks")
            } else {
                var hasValidAudio = false
                for track in audioTracks {
                    let duration = CMTimeGetSeconds(track.timeRange.duration)
                    print("SkipSlate: Self-test - Audio track duration: \(duration)s")
                    if duration > 0 {
                        hasValidAudio = true
                    }
                }
                
                if hasValidAudio {
                    print("SkipSlate: Self-test PASSED - Composition has valid audio")
                } else {
                    print("SkipSlate: Self-test FAILED - All audio tracks have zero duration")
                }
            }
        } catch {
            print("SkipSlate: Self-test FAILED - Error building composition: \(error)")
        }
        
        print("SkipSlate: ===== AUDIO SELF-TEST END ======")
    }
    
    // MARK: - Actions
    
    func importMedia(urls: [URL]) {
        print("SkipSlate: importMedia called with \(urls.count) URLs")
        guard !urls.isEmpty else {
            print("SkipSlate: No URLs provided to importMedia")
            return
        }
        
        // CRITICAL: For Highlight Reel, limit to 12 videos maximum
        // CRASH-PROOF: Comprehensive validation
        if project.type == .highlightReel {
            do {
                // CRASH-PROOF: Safely count existing videos
                let currentVideoCount = project.clips.filter { clip in
                    clip.type == .videoWithAudio || clip.type == .videoOnly
                }.count
                
                // CRASH-PROOF: Validate URLs count
                guard urls.count > 0 else {
                    print("SkipSlate: ⚠️ No URLs provided for import")
                    return
                }
                
                let totalAfterImport = currentVideoCount + urls.count
                
                // CRASH-PROOF: Validate counts are reasonable
                guard currentVideoCount >= 0 && currentVideoCount <= 12 else {
                    print("SkipSlate: ⚠️ Invalid current video count: \(currentVideoCount)")
                    Task { @MainActor in
                        autoEditError = "Invalid video count detected. Please restart the project."
                    }
                    return
                }
                
                if totalAfterImport > 12 {
                    let excessCount = totalAfterImport - 12
                    let allowedCount = max(0, 12 - currentVideoCount)
                    
                    Task { @MainActor in
                        autoEditError = "Highlight Reel is limited to 12 videos. You have \(currentVideoCount) video(s) and tried to add \(urls.count), which would exceed the limit by \(excessCount). Please select only \(allowedCount) video(s) or fewer."
                    }
                    print("SkipSlate: ⚠️ Highlight Reel video limit exceeded: \(currentVideoCount) existing + \(urls.count) new = \(totalAfterImport) (max: 12)")
                    
                    // Only import up to the limit
                    if allowedCount > 0 {
                        let limitedURLs = Array(urls.prefix(allowedCount))
                        print("SkipSlate: Limiting import to \(allowedCount) video(s) to stay within limit")
                        importMediaLimited(urls: limitedURLs)
                    } else {
                        print("SkipSlate: Cannot import any more videos - limit of 12 already reached")
                        Task { @MainActor in
                            autoEditError = "Highlight Reel video limit reached (12 videos). Cannot import more videos."
                        }
                    }
                    return
                }
            } catch {
                print("SkipSlate: ❌ Error validating Highlight Reel limit: \(error)")
                Task { @MainActor in
                    autoEditError = "Error validating video limit: \(error.localizedDescription)"
                }
                return
            }
        }
        
        importMediaLimited(urls: urls)
    }
    
    private func importMediaLimited(urls: [URL]) {
        Task {
            print("SkipSlate: Starting media import task...")
            let newClips = await MediaImportService.shared.importMedia(
                from: urls,
                existingClips: project.clips,
                projectType: project.type
            )
            print("SkipSlate: MediaImportService returned \(newClips.count) clips")
            
            await MainActor.run {
                if !newClips.isEmpty {
                    print("SkipSlate: ProjectViewModel - About to update project. Current clips: \(project.clips.count)")
                    
                    // Create a new project object to trigger @Published update
                    var updatedProject = project
                    updatedProject.clips.append(contentsOf: newClips)
                    
                    // Force update by replacing the entire project
                    // This should trigger @Published to notify observers
                    project = updatedProject
                    
                    print("SkipSlate: ProjectViewModel - Updated project with \(newClips.count) new clips. Total clips: \(project.clips.count)")
                    print("SkipSlate: ProjectViewModel - Clips in project: \(project.clips.map { $0.fileName })")
                    
                    // Verify the update took effect
                    if project.clips.count == updatedProject.clips.count {
                        print("SkipSlate: ProjectViewModel - Project update confirmed: \(project.clips.count) clips")
                    } else {
                        print("SkipSlate: ProjectViewModel - WARNING: Project update mismatch! Expected \(updatedProject.clips.count), got \(project.clips.count)")
                    }
                    
                    // NOTE: Do NOT call rebuildComposition() here - segments don't exist yet!
                    // Composition rebuild will happen automatically when:
                    // 1. Auto-edit creates segments (runAutoEdit calls rebuildComposition)
                    // 2. User manually adds segments to timeline (addSegmentToTimeline calls immediateRebuild)
                    // Calling rebuildComposition without segments would fail early and potentially leave
                    // PlayerViewModel in an inconsistent state, causing preview to break when UI changes.
                    print("SkipSlate: ProjectViewModel - Media imported successfully. Composition will rebuild when segments are created.")
                } else {
                    print("SkipSlate: ProjectViewModel - No clips were imported - check file types and permissions")
                    print("SkipSlate: ProjectViewModel - URLs provided: \(urls.map { $0.lastPathComponent })")
                }
            }
        }
    }
    
    func prepareAssetsIfNeeded() {
        for clip in project.clips {
            if assetsByClipID[clip.id] == nil {
                let asset = AVURLAsset(url: clip.url)
                assetsByClipID[clip.id] = asset
            }
        }
    }
    
    // MARK: - Quality Analysis
    
    /// Analyze quality scores for all video clips
    func analyzeQualityForClips() async {
        await MainActor.run {
            isAnalyzingQuality = true
            qualityAnalysisProgress = (0, 0)
        }
        
        let videoClips = project.clips.filter { $0.type == .videoWithAudio || $0.type == .videoOnly }
        let totalClips = videoClips.count
        
        await MainActor.run {
            qualityAnalysisProgress = (0, totalClips)
        }
        
        prepareAssetsIfNeeded()
        let frameAnalysis = FrameAnalysisService.shared
        
        // CRITICAL: Process clips sequentially - one at a time to prevent crashes
        print("SkipSlate: ProjectViewModel - Analyzing quality for \(totalClips) clips SEQUENTIALLY")
        
        for (index, clip) in videoClips.enumerated() {
            guard let asset = assetsByClipID[clip.id] else {
                await MainActor.run {
                    qualityAnalysisProgress = (index + 1, totalClips)
                }
                continue
            }
            
            print("SkipSlate: ProjectViewModel - [SEQUENTIAL] Analyzing quality for clip \(index + 1)/\(totalClips): \(clip.fileName)")
            
            do {
                // CRITICAL: await ensures this clip is completely analyzed before starting the next
                // Analyze frames to get quality scores
                let frameAnalyses = try await frameAnalysis.analyzeFrames(
                    from: asset,
                    sampleInterval: 1.0, // Sample every 1 second for faster analysis
                    progressCallback: nil
                )
                
                // Calculate average quality score for this clip
                guard !frameAnalyses.isEmpty else {
                    await MainActor.run {
                        clipQualityScores[clip.id] = 0.5 // Default if no frames analyzed
                        qualityAnalysisProgress = (index + 1, totalClips)
                    }
                    continue
                }
                
                let avgScore = frameAnalyses.map { $0.shotQualityScore }.reduce(0, +) / Float(frameAnalyses.count)
                
                await MainActor.run {
                    clipQualityScores[clip.id] = avgScore
                    qualityAnalysisProgress = (index + 1, totalClips)
                }
                
                print("SkipSlate: Analyzed quality for '\(clip.fileName)': \(String(format: "%.2f", avgScore))")
            } catch {
                print("SkipSlate: Error analyzing quality for '\(clip.fileName)': \(error)")
                await MainActor.run {
                    clipQualityScores[clip.id] = 0.5 // Default on error
                    qualityAnalysisProgress = (index + 1, totalClips)
                }
            }
        }
        
        await MainActor.run {
            isAnalyzingQuality = false
        }
    }
    
    /// Get quality score for a specific clip
    func qualityScore(for clipID: UUID) -> Float? {
        return clipQualityScores[clipID]
    }
    
    /// Get quality score for a segment (based on its source clip)
    func qualityScore(for segment: Segment) -> Float? {
        guard let clipID = segment.clipID else {
            return nil
        }
        return clipQualityScores[clipID]
    }
    
    func runAutoEdit() {
        guard !project.clips.isEmpty else {
            autoEditError = "No media clips to edit"
            return
        }
        
        isAutoEditing = true
        autoEditStatus = "Analyzing audio..."
        autoEditError = nil
        autoEditStartTime = Date()
        autoEditProgress = (0, project.clips.count)
        autoEditTimeEstimate = nil  // Will be calculated once we have progress
        
        // Prepare assets
        prepareAssetsIfNeeded()
        
        let currentProject = project
        let currentSettings = autoEditSettings
        
        Task {
            do {
                // Create progress callback that tracks progress for time estimation
                let totalClips = currentProject.clips.count
                
                let progressCallback: ((String) -> Void)? = { [weak self] message in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.autoEditStatus = message
                        
                        // Parse progress from message to track clips processed
                        // Messages like "Analyzing video clip 1/8: ..." or "Analyzing frame X/Y" indicate progress
                        if message.contains("clip") || message.contains("frame") || message.contains("Analyzing") {
                            // Try to extract progress numbers from message (e.g., "1/8", "5/10")
                            let pattern = #"(\d+)/(\d+)"#
                            if let range = message.range(of: pattern, options: .regularExpression) {
                                let clipInfo = String(message[range])
                                let parts = clipInfo.split(separator: "/")
                                if parts.count == 2,
                                   let current = Int(parts[0]),
                                   let total = Int(parts[1]),
                                   total > 0 {
                                    self.autoEditProgress = (current, total)
                                    // Update time estimate when we have meaningful progress
                                    if current > 0 {
                                        self.updateAutoEditTimeEstimate()
                                    }
                                }
                            }
                        }
                    }
                }
                
                // CRITICAL: Generate ALL segments from ALL clips WITHOUT target length limit
                // This gives us ALL possible segments for both caching AND timeline filtering
                var tempSettingsForAllSegments = currentSettings
                tempSettingsForAllSegments.targetLengthSeconds = nil  // No limit - get ALL segments
                
                print("SkipSlate: Generating ALL segments from ALL clips (no target length limit)...")
                
                // CRITICAL: For Highlight Reel, capture ALL analyzed segments via callback
                // This ensures we cache ALL segments before filtering (all scored candidates)
                var capturedAllAnalyzedSegments: [Segment] = []
                let allAnalyzedCallback: (([Segment]) -> Void)? = currentProject.type == .highlightReel ? { segments in
                    capturedAllAnalyzedSegments = segments
                    print("SkipSlate: ✅ Captured \(segments.count) ALL analyzed segments from Highlight Reel (before filtering)")
                } : nil
                
                let allSegmentsFromAllClips = try await autoEditService.generateSegments(
                    for: currentProject,
                    assetsByClipID: assetsByClipID,
                    settings: tempSettingsForAllSegments,
                    progressCallback: progressCallback,
                    allAnalyzedSegmentsCallback: allAnalyzedCallback
                )
                
                print("SkipSlate: Generated \(allSegmentsFromAllClips.count) TOTAL segments from all clips")
                
                // CRASH-PROOF: Cache ALL analyzed segments from ALL clips (not just filtered ones)
                // For Highlight Reel, use captured segments (all analyzed); for others, use generated segments
                let allClipSegments: [Segment]
                if currentProject.type == .highlightReel && !capturedAllAnalyzedSegments.isEmpty {
                    // Use ALL analyzed segments captured from Highlight Reel (includes ALL scored candidates)
                    allClipSegments = capturedAllAnalyzedSegments.filter { $0.isClip }
                    print("SkipSlate: ✅ Using \(allClipSegments.count) captured analyzed segments for Highlight Reel cache")
                } else {
                    // For other project types, use generated segments
                    allClipSegments = allSegmentsFromAllClips.filter { $0.isClip }
                }
                
                // Filter segments for timeline based on target length (if specified)
                let newSegments = autoEditService.limitSegmentsToTargetLength(
                    allSegmentsFromAllClips,
                    targetLength: currentSettings.targetLengthSeconds
                )
                
                // Set composition start times for new segments (sequential, no gaps initially)
                // Do this BEFORE MainActor.run to prepare data
                var segmentsWithStartTimes: [Segment] = []
                var totalDuration: Double = 0.0
                for segment in newSegments {
                    var segmentWithTime = segment
                    segmentWithTime.compositionStartTime = totalDuration
                    segmentsWithStartTimes.append(segmentWithTime)
                    totalDuration += segment.duration
                }
                
                // NOTE: V2 background fill logic removed - users can manually add V2 tracks if needed
                // Auto-edit only creates segments on V1 (base video track)
                
                await MainActor.run {
                    print("SkipSlate: Auto edit completed. Generated \(newSegments.count) segments for timeline (filtered from \(allSegmentsFromAllClips.count) total)")
                    print("SkipSlate: Caching \(allClipSegments.count) clip segments for Media tab")
                    
                    // CRITICAL: Cache ALL analyzed segments BEFORE filtering
                    // This ensures Media tab shows ALL available segments
                    cachedAnalyzedSegments = allClipSegments
                    cachedAnalyzedClipIDs = Set(allClipSegments.compactMap { $0.clipID })
                    
                    // Reset deleted clip IDs on fresh auto-edit (user wants fresh start)
                    deletedClipIDs.removeAll()
                    
                    print("SkipSlate: ✅ Cached \(cachedAnalyzedSegments.count) TOTAL analyzed segments from \(cachedAnalyzedClipIDs.count) clips")
                    print("SkipSlate: Segments per clip breakdown:")
                    let segmentsByClip = Dictionary(grouping: cachedAnalyzedSegments) { $0.clipID ?? UUID() }
                    for (clipID, segments) in segmentsByClip {
                        if let clip = currentProject.clips.first(where: { $0.id == clipID }) {
                            print("SkipSlate:   - \(clip.fileName): \(segments.count) segments")
                        }
                    }
                    
                    // Log segment timing
                    for segment in segmentsWithStartTimes {
                        if let clipID = segment.clipID,
                           let clip = project.clips.first(where: { $0.id == clipID }) {
                            print("SkipSlate:   Segment: clip='\(clip.fileName)', start=\(segment.sourceStart)s, end=\(segment.sourceEnd)s, duration=\(segment.duration)s, compositionStart=\(segment.compositionStartTime)s")
                        }
                    }
                    
                    var updatedProject = project
                    updatedProject.segments = segmentsWithStartTimes
                    
                    // CRITICAL: Auto-edit writes all segments to V1 (base video track) only
                    // Users can add V2, V3, etc. manually for overlays if they want
                    if let baseVideoTrackIndex = updatedProject.tracks.firstIndex(where: { $0.kind == .video && $0.index == 0 }) {
                        let segmentIDs = segmentsWithStartTimes.map { $0.id }
                        updatedProject.tracks[baseVideoTrackIndex].segments = segmentIDs
                        print("SkipSlate: ✅ Auto-edit: Added \(segmentIDs.count) segments to V1 (base video track)")
                    } else {
                        // Create V1 track if it doesn't exist
                        let baseVideoTrack = TimelineTrack(kind: .video, index: 0, segments: segmentsWithStartTimes.map { $0.id })
                        updatedProject.tracks.append(baseVideoTrack)
                        print("SkipSlate: ✅ Auto-edit: Created V1 track and added \(segmentsWithStartTimes.count) segments")
                    }
                    
                    // CRITICAL: For Highlight Reel, add the music track segment to A1 (audio track)
                    // This creates a visual representation of the music on the timeline
                    // IMPORTANT: Audio segment must match video duration (totalDuration holds total video duration)
                    if currentProject.type == .highlightReel {
                        // Find the audio-only clip (music track)
                        if let musicClip = currentProject.clips.first(where: { $0.type == .audioOnly }) {
                            // CRITICAL: Audio should end when video ends, not at full music duration
                            // totalDuration is the total duration of all video segments
                            let totalVideoDuration = totalDuration
                            let audioEndTime = min(musicClip.duration, totalVideoDuration)
                            
                            print("SkipSlate: 🎵 Audio segment calculation:")
                            print("SkipSlate:   Music clip duration: \(musicClip.duration)s")
                            print("SkipSlate:   Total video duration: \(totalVideoDuration)s")
                            print("SkipSlate:   Audio segment will end at: \(audioEndTime)s")
                            
                            // Create ONE audio segment matching the video duration
                            // SIMPLE: One continuous segment that ends when video ends
                            var audioSegment = Segment(
                                id: UUID(),
                                sourceClipID: musicClip.id,
                                sourceStart: 0.0,
                                sourceEnd: audioEndTime,  // Cut at video end
                                enabled: true,
                                colorIndex: -1,  // Special audio color (renders as teal-orange blend)
                                compositionStartTime: 0.0
                            )
                            
                            // Apply audio fade out if enabled in settings
                            // Default: 2 second fade out at the end
                            let fadeOutDuration: Double = 2.0
                            if audioEndTime > fadeOutDuration {
                                audioSegment.effects.audioFadeOutDuration = fadeOutDuration
                                print("SkipSlate:   Applied \(fadeOutDuration)s audio fade out")
                            }
                            
                            // Add to segments array
                            updatedProject.segments.append(audioSegment)
                            
                            // Add to A1 audio track
                            if let audioTrackIndex = updatedProject.tracks.firstIndex(where: { $0.kind == .audio && $0.index == 0 }) {
                                updatedProject.tracks[audioTrackIndex].segments = [audioSegment.id]
                                print("SkipSlate: ✅ Auto-edit: Added music segment '\(musicClip.fileName)' to A1 (audio track)")
                                print("SkipSlate:   Audio duration: \(audioEndTime)s (matches video duration)")
                            } else {
                                // Create A1 track if it doesn't exist
                                let audioTrack = TimelineTrack(kind: .audio, index: 0, segments: [audioSegment.id])
                                updatedProject.tracks.append(audioTrack)
                                print("SkipSlate: ✅ Auto-edit: Created A1 track and added music segment '\(musicClip.fileName)'")
                            }
                        } else {
                            print("SkipSlate: ⚠️ Auto-edit: No audio-only clip found for audio track segment")
                        }
                    }
                    
                    project = updatedProject
                    
                    // Reset modification flag after fresh Auto Edit
                    hasUserModifiedAutoEdit = false
                    lastAutoEditRunID = UUID()
                    
                    autoEditStatus = "Auto edit complete. Review segments below."
                    isAutoEditing = false
                    autoEditTimeEstimate = nil  // Clear estimate when done
                    autoEditStartTime = nil
                    
                    // Rebuild preview composition
                    print("SkipSlate: Rebuilding preview composition...")
                    // Use playerVM computed property to ensure PlayerViewModel exists
                    playerVM.rebuildComposition(from: project)
                }
            } catch {
                await MainActor.run {
                    isAutoEditing = false
                    autoEditStatus = "Auto edit failed"
                    
                    if let editError = error as? AutoEditError {
                        switch editError {
                        case .noUsableAudio:
                            autoEditError = "Auto edit couldn't find usable audio. Please ensure your media has audio tracks or add some audio-only files."
                        case .noClips:
                            autoEditError = "No media clips available for editing."
                        case .analysisFailed(let reason):
                            autoEditError = "Analysis failed: \(reason)"
                        }
                    } else {
                        autoEditError = "Auto edit failed: \(error.localizedDescription)"
                    }
                    
                    autoEditTimeEstimate = nil  // Clear estimate on error
                    autoEditStartTime = nil
                    
                    print("Auto edit error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Time Estimation
    
    /// Update time estimate based on progress
    private func updateAutoEditTimeEstimate() {
        guard let startTime = autoEditStartTime else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // CRASH-PROOF: Need at least a few seconds of elapsed time to make meaningful estimates
        guard elapsed > 5.0 else {
            // Too early to estimate - wait a bit
            autoEditTimeEstimate = "Calculating estimate..."
            return
        }
        
        // If we have progress data, use it for more accurate estimates
        if autoEditProgress.total > 0 && autoEditProgress.completed > 0 {
            let progress = Double(autoEditProgress.completed) / Double(autoEditProgress.total)
            
            // CRASH-PROOF: Safety checks
            guard progress > 0, progress <= 1.0, elapsed > 0 else {
                return
            }
            
            // Calculate estimated total time based on current progress
            let estimatedTotalTime = elapsed / progress
            let remainingTime = estimatedTotalTime - elapsed
            
            // CRASH-PROOF: Ensure remaining time is reasonable
            guard remainingTime > 0 else {
                autoEditTimeEstimate = "Almost done..."
                return
            }
            
            // Format time estimate
            autoEditTimeEstimate = formatTimeEstimate(remainingTime)
        } else {
            // Fallback: Estimate based on typical processing time per clip
            // Average: ~30-60 seconds per clip for analysis
            let avgTimePerClip: Double = 45.0 // seconds
            let totalClips = project.clips.count
            let estimatedTotalTime = Double(totalClips) * avgTimePerClip
            let remainingTime = max(0, estimatedTotalTime - elapsed)
            
            autoEditTimeEstimate = formatTimeEstimate(remainingTime)
        }
    }
    
    /// Format time in minutes/hours for display
    private func formatTimeEstimate(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        
        if minutes < 1 {
            return "Estimated time remaining: Less than a minute"
        } else if minutes < 60 {
            return "Estimated time remaining: \(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "Estimated time remaining: \(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "Estimated time remaining: \(hours) hour\(hours == 1 ? "" : "s") \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
            }
        }
    }
    
    /// Update progress for time estimation (called from progress callbacks)
    func updateAutoEditProgress(completed: Int, total: Int) {
        autoEditProgress = (completed, total)
        updateAutoEditTimeEstimate()
    }
    
    // Debouncing for rebuilds
    private var rebuildTask: Task<Void, Never>?
    private var lastRebuildHash: Int = 0
    
    private func projectHash() -> Int {
        var hasher = Hasher()
        hasher.combine(project.segments.count)
        for segment in project.segments {
            hasher.combine(segment.id)
            hasher.combine(segment.sourceStart)
            hasher.combine(segment.sourceEnd)
            hasher.combine(segment.enabled)
            hasher.combine(segment.compositionStartTime)
            hasher.combine(segment.effects.scale)
            hasher.combine(segment.effects.positionX)
            hasher.combine(segment.effects.positionY)
            hasher.combine(segment.effects.rotation)
            hasher.combine(segment.transform.scaleToFillFrame)
        }
        
        // CRITICAL: Include track membership - which segments are on which tracks
        // This ensures hash changes when segments move between tracks
        for track in project.tracks {
            hasher.combine(track.id)
            hasher.combine(track.segments.count)
            for segmentID in track.segments {
                hasher.combine(segmentID)
            }
        }
        
        return hasher.finalize()
    }
    
    private func debouncedRebuild() {
        // Check if anything actually changed
        let currentHash = projectHash()
        if currentHash == lastRebuildHash {
            print("SkipSlate: Skipping debounced rebuild - no changes detected")
            return
        }
        
        // Cancel any pending rebuild
        rebuildTask?.cancel()
        
        // Schedule rebuild after delay
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            if !Task.isCancelled {
                let hashBeforeRebuild = self.projectHash()
                // Use playerVM computed property to ensure PlayerViewModel exists
                self.playerVM.rebuildComposition(from: self.project)
                self.lastRebuildHash = hashBeforeRebuild
            }
        }
    }
    
    private func immediateRebuild() {
        print("SkipSlate: [Move DEBUG] immediateRebuild – starting")
        rebuildTask?.cancel()
        let currentHash = projectHash()
        if currentHash == lastRebuildHash {
            print("SkipSlate: [Move DEBUG] Skipping immediate rebuild - no changes detected (hash: \(currentHash))")
            return
        }
        print("SkipSlate: [Move DEBUG] immediateRebuild() - hash changed from \(lastRebuildHash) to \(currentHash), triggering rebuild")
        // Use playerVM computed property to ensure PlayerViewModel exists
        playerVM.rebuildComposition(from: project)
        lastRebuildHash = currentHash
        print("SkipSlate: [Move DEBUG] immediateRebuild – finished")
    }
    
    func toggleSegmentEnabled(_ segment: Segment) {
        if let index = project.segments.firstIndex(where: { $0.id == segment.id }) {
            project.segments[index].enabled.toggle()
            debouncedRebuild() // Use debounced rebuild for rapid toggles
        }
    }
    
    /// Select all clip segments (not gaps)
    func selectAllSegments() {
        let clipSegmentIDs = segments.filter { $0.kind == .clip }.map { $0.id }
        selectedSegmentIDs = Set(clipSegmentIDs)
        selectedSegment = segments.first { $0.kind == .clip }
        print("SkipSlate: ✅ Selected all \(clipSegmentIDs.count) segments")
    }
    
    /// Trim segment with undo support - call this at the END of a trim operation
    func trimSegmentUndoable(_ segmentID: Segment.ID, newSourceStart: Double, newSourceEnd: Double, newCompositionStart: Double? = nil) {
        guard let index = project.segments.firstIndex(where: { $0.id == segmentID }) else { return }
        
        performUndoableChange("Trim segment") {
            project.segments[index].sourceStart = newSourceStart
            project.segments[index].sourceEnd = newSourceEnd
            if let compStart = newCompositionStart {
                project.segments[index].compositionStartTime = compStart
            }
            hasUserModifiedAutoEdit = true
        }
        // Note: immediateRebuild is called by performUndoableChange
    }
    
    func updateSegmentTiming(_ segment: Segment, start: Double, end: Double) {
        if let index = project.segments.firstIndex(where: { $0.id == segment.id }) {
            project.segments[index].sourceStart = start
            project.segments[index].sourceEnd = end
            debouncedRebuild() // Use debounced rebuild for timing updates
        }
    }
    
    func updateSegment(_ segment: Segment) {
        if let index = project.segments.firstIndex(where: { $0.id == segment.id }) {
            project.segments[index] = segment
            // Update selected segment if it's the same one
            if selectedSegment?.id == segment.id {
                selectedSegment = segment
            }
            // CRITICAL: Use immediate rebuild for transform effects to enable real-time preview
            // Check if this is a transform-related change
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
    
    /// Update segment with immediate rebuild (for real-time preview)
    /// Use this specifically for transform effects that need immediate visual feedback
    func updateSegmentImmediate(_ segment: Segment) {
        guard let index = project.segments.firstIndex(where: { $0.id == segment.id }) else {
            print("SkipSlate: [Transform DEBUG] updateSegmentImmediate – segment not found id=\(segment.id)")
            return
        }
        
        // Wrap in undoable change for transform updates
        performUndoableChange("Update segment effects") {
            // STEP 3.1: Debug logging before and after writing segment
            print("SkipSlate: [Transform DEBUG] updateSegmentImmediate – writing segment at index \(index)")
            print("SkipSlate: [Transform DEBUG] Previous segment effects: scale=\(project.segments[index].effects.scale), pos=(\(project.segments[index].effects.positionX), \(project.segments[index].effects.positionY)), rot=\(project.segments[index].effects.rotation), scaleToFill=\(project.segments[index].transform.scaleToFillFrame)")
            
            project.segments[index] = segment
            
            print("SkipSlate: [Transform DEBUG] New segment effects: scale=\(project.segments[index].effects.scale), pos=(\(project.segments[index].effects.positionX), \(project.segments[index].effects.positionY)), rot=\(project.segments[index].effects.rotation), scaleToFill=\(project.segments[index].transform.scaleToFillFrame)")
            
            // Update selected segment if it's the same one
            if selectedSegment?.id == segment.id {
                selectedSegment = segment
            }
        }
        // Note: immediateRebuild is called by performUndoableChange
    }
    
    func deleteSegment(_ segment: Segment) {
        removeSegment(segment.id)
    }
    
    /// Convenience wrapper for backward compatibility
    func rerunAutoEdit() {
        handleRerunAutoEditFillGaps()
    }
    
    /// Canonical entry point for filling gaps with auto-edit
    /// ONLY fills gap segments - existing clip segments are never modified
    /// CRASH-PROOF: Comprehensive error handling at every step
    func handleRerunAutoEditFillGaps() {
        print("SkipSlate: 🔄 RERUN AUTO-EDIT CALLED")
        
        // CRASH-PROOF: Safety check - Ensure we have clips
        guard !project.clips.isEmpty else {
            autoEditError = "No clips available to rerun auto-edit"
            print("SkipSlate: ❌ Rerun Auto-Edit - No clips available")
            return
        }
        
        // CRASH-PROOF: Prevent concurrent auto-edit operations
        guard !isAutoEditing else {
            print("SkipSlate: Rerun Auto-Edit - Already in progress, ignoring request")
            return
        }
        
        // CRASH-PROOF: Validate project state before starting
        guard project.id != nil else {
            autoEditError = "Invalid project state"
            print("SkipSlate: ❌ Rerun Auto-Edit - Project has no ID")
            return
        }
        
        isAutoEditing = true
        autoEditStatus = "Analyzing clips and filling gaps..."
        autoEditError = nil  // Clear any previous errors
        autoEditStartTime = Date() // Start time for estimation
        autoEditProgress = (0, 0) // Reset progress
        autoEditTimeEstimate = "Estimating..."
        print("SkipSlate: 🔄 Starting rerun auto-edit...")
        
        // CRASH-PROOF: Prepare assets with error handling
        do {
            prepareAssetsIfNeeded()
        } catch {
            isAutoEditing = false
            autoEditError = "Failed to prepare assets: \(error.localizedDescription)"
            print("SkipSlate: ❌ Rerun Auto-Edit - Asset preparation failed: \(error)")
            return
        }
        
        // CRASH-PROOF: Capture current state safely
        let currentProject: Project
        let currentSettings: AutoEditSettings
        do {
            currentProject = project
            currentSettings = autoEditSettings
            
            // Validate captured state
            guard !currentProject.clips.isEmpty else {
                isAutoEditing = false
                autoEditError = "Project clips became empty during capture"
                print("SkipSlate: ❌ Rerun Auto-Edit - Clips empty after capture")
                return
            }
        } catch {
            isAutoEditing = false
            autoEditError = "Failed to capture project state: \(error.localizedDescription)"
            print("SkipSlate: ❌ Rerun Auto-Edit - State capture failed: \(error)")
            return
        }
        
        // CRASH-PROOF: Create task with cancellation support
        let rerunTask = Task { @MainActor in
            // CRASH-PROOF: Check for task cancellation
            guard !Task.isCancelled else {
                isAutoEditing = false
                autoEditStatus = "Operation cancelled"
                print("SkipSlate: Rerun Auto-Edit - Task cancelled before start")
                return
            }
            
            do {
                // CRASH-PROOF: Validate segments array before filtering
                guard !currentProject.segments.isEmpty else {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "No segments in timeline"
                        autoEditError = "Timeline is empty"
                    }
                    return
                }
                
                // CRASH-PROOF: Find all gap segments with error handling
                let gapSegments: [Segment]
                do {
                    gapSegments = currentProject.segments.filter { segment in
                        // CRASH-PROOF: Validate segment before checking properties
                        guard segment.kind == .gap else { return false }
                        guard segment.enabled else { return false }
                        guard segment.duration > 0.01 else { return false }
                        guard segment.compositionStartTime >= 0 else { return false }
                        return true
                    }
                } catch {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "Failed to analyze gaps"
                        autoEditError = "Error filtering gap segments: \(error.localizedDescription)"
                    }
                    print("SkipSlate: ❌ Rerun Auto-Edit - Gap filtering error: \(error)")
                    return
                }
                
                // CRASH-PROOF: Calculate total gap duration safely
                let totalGapDuration = gapSegments.reduce(0.0) { (sum, segment) -> Double in
                    let duration = max(0.0, segment.duration) // Prevent negative
                    guard duration.isFinite else { return sum } // Skip invalid durations
                    return sum + duration
                }
                
                print("SkipSlate: 🔍 Rerun Auto-Edit - Found \(gapSegments.count) gap segment(s) totaling \(String(format: "%.2f", totalGapDuration))s")
                
                // Safety check: Validate gaps
                guard !gapSegments.isEmpty else {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "No gaps to fill. Delete some segments first to create gaps."
                        autoEditError = "No gaps found in timeline"
                        print("SkipSlate: ⚠️ Rerun Auto-Edit - No gap segments found, nothing to fill. User needs to delete segments first.")
                    }
                    return
                }
                
                // Safety check: Validate gap durations
                let validGaps = gapSegments.filter { $0.duration > 0.01 && $0.compositionStartTime >= 0 }
                guard !validGaps.isEmpty else {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "No valid gaps to fill"
                        autoEditError = "Gap segments found but have invalid durations. Try deleting segments again."
                        print("SkipSlate: ⚠️ Rerun Auto-Edit - All gap segments are invalid (total gaps: \(gapSegments.count))")
                        
                        // CRASH-PROOF: Debug invalid gaps
                        for gap in gapSegments {
                            print("SkipSlate: Debug - Gap \(gap.id): duration=\(gap.duration), startTime=\(gap.compositionStartTime)")
                        }
                    }
                    return
                }
                
                // Fill gaps using cached analyzed segments
                var segmentsToAdd: [Segment] = []
                var totalFilled: Double = 0.0
                
                // CRASH-PROOF: Safety check - Ensure we have clips available (excluding deleted)
                let availableClipsCount: Int
                do {
                    availableClipsCount = currentProject.clips.filter { clip in
                        // CRASH-PROOF: Validate clip before accessing properties
                        guard clip.duration > 0.01 && clip.duration.isFinite else { return false }
                        guard !deletedClipIDs.contains(clip.id) else { return false }
                        
                        // CRASH-PROOF: Validate asset exists and is accessible
                        guard let asset = assetsByClipID[clip.id] else { return false }
                        guard asset.isReadable else {
                            print("SkipSlate: ⚠️ Clip \(clip.id) asset is not readable")
                            return false
                        }
                        
                        return true
                    }.count
                } catch {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "Failed to validate clips"
                        autoEditError = "Error checking available clips: \(error.localizedDescription)"
                    }
                    print("SkipSlate: ❌ Rerun Auto-Edit - Clip validation error: \(error)")
                    return
                }
                
                guard availableClipsCount > 0 else {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "No available clips to use"
                        autoEditError = "All clips have been deleted or are invalid. Import more clips to fill gaps."
                        print("SkipSlate: ❌ Rerun Auto-Edit - No available clips (total: \(currentProject.clips.count), deleted: \(deletedClipIDs.count), available: \(availableClipsCount))")
                    }
                    return
                }
                
                // CRITICAL: Filter out segments from deleted clips - don't reuse deleted clips
                var availableCachedSegments = cachedAnalyzedSegments.filter { segment in
                    guard let clipID = segment.clipID else { return false }
                    return !deletedClipIDs.contains(clipID)
                }
                let excludedCount = cachedAnalyzedSegments.count - availableCachedSegments.count
                if excludedCount > 0 {
                    print("SkipSlate: Rerun Auto-Edit - Filtered to \(availableCachedSegments.count) available segments from cache (excluded \(excludedCount) segments from deleted clips)")
                } else {
                    print("SkipSlate: Rerun Auto-Edit - Using \(availableCachedSegments.count) cached segments (none excluded)")
                }
                
                // CRITICAL: Use cached segments first - NO re-analysis unless absolutely necessary
                // Only analyze NEW clips that weren't in the original analysis
                print("SkipSlate: Rerun Auto-Edit - Using cached segments (no re-analysis needed)")
                
                // Get ALL clips (excluding deleted ones)
                let allAvailableClips = currentProject.clips.filter { clip in
                    guard clip.duration > 0.01 else { return false }
                    guard !deletedClipIDs.contains(clip.id) else { return false }
                    guard assetsByClipID[clip.id] != nil else { return false }
                    return true
                }
                
                // Check if we have enough cached segments - if yes, skip analysis entirely
                let totalGapDurationNeeded = validGaps.reduce(0.0) { $0 + $1.duration }
                let cachedSegmentsTotalDuration = availableCachedSegments.reduce(0.0) { $0 + $1.duration }
                
                // CRITICAL: Only analyze VIDEO clips (exclude audio-only clips like music tracks)
                // Audio-only clips should never be analyzed for video segments
                // CRASH-PROOF: Comprehensive validation before filtering
                let unanalyzedVideoClips = allAvailableClips.filter { clip in
                    // CRASH-PROOF: Validate clip properties before checking type
                    guard clip.duration > 0.01 && clip.duration.isFinite else { return false }
                    guard !deletedClipIDs.contains(clip.id) else { return false }
                    
                    // Must be a video clip (not audio-only or image)
                    guard clip.type == .videoWithAudio || clip.type == .videoOnly else {
                        return false
                    }
                    
                    // CRASH-PROOF: Verify asset exists before including
                    guard assetsByClipID[clip.id] != nil else {
                        print("SkipSlate: ⚠️ Skipping clip \(clip.fileName) - asset not available")
                        return false
                    }
                    
                    // Must not have been analyzed before
                    return !cachedAnalyzedClipIDs.contains(clip.id)
                }
                
                let needsAnalysis = !unanalyzedVideoClips.isEmpty || cachedSegmentsTotalDuration < totalGapDurationNeeded * 1.5
                
                if needsAnalysis && !unanalyzedVideoClips.isEmpty {
                    // Only analyze NEW VIDEO clips that weren't analyzed before
                    print("SkipSlate: Rerun Auto-Edit - Found \(unanalyzedVideoClips.count) new video clip(s) to analyze (out of \(allAvailableClips.count) total clips)")
                    // CRASH-PROOF: Check cancellation before expensive operation
                    guard !Task.isCancelled else {
                        await MainActor.run {
                            isAutoEditing = false
                            autoEditStatus = "Operation cancelled"
                        }
                        return
                    }
                    
                    // CRASH-PROOF: Create temporary project with ONLY new VIDEO clips
                    var tempProject: Project
                    do {
                        tempProject = currentProject
                        tempProject.clips = unanalyzedVideoClips  // Only analyze NEW VIDEO clips (excludes audio-only)
                        
                        // Validate temporary project
                        guard !tempProject.clips.isEmpty else {
                            print("SkipSlate: ⚠️ Rerun Auto-Edit - Temp project clips empty")
                            throw NSError(domain: "ProjectViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Temp project has no clips"])
                        }
                    } catch {
                        await MainActor.run {
                            isAutoEditing = false
                            autoEditStatus = "Failed to prepare project for analysis"
                            autoEditError = "Error creating temporary project: \(error.localizedDescription)"
                        }
                        print("SkipSlate: ❌ Rerun Auto-Edit - Temp project creation error: \(error)")
                        return
                    }
                    
                    // CRITICAL: Generate segments from NEW clips only with NO target length limit
                    // This ensures we get ALL possible segments from new clips
                    var tempSettings = currentSettings
                    tempSettings.targetLengthSeconds = nil  // No limit - get all segments
                    
                    // CRASH-PROOF: Generate ALL segments from ALL clips with comprehensive error handling
                    // Start with cached segments - always initialized
                    var allSegmentsFromAllClips = availableCachedSegments
                    
                    // If we have new VIDEO clips, analyze them and add to the segments
                    if !unanalyzedVideoClips.isEmpty {
                        do {
                        // Update progress for new clip analysis
                        await MainActor.run {
                            self.autoEditStatus = "Analyzing \(unanalyzedVideoClips.count) new video clip(s)..."
                            self.autoEditProgress = (0, unanalyzedVideoClips.count)
                            self.updateAutoEditTimeEstimate()
                        }
                        
                        // CRASH-PROOF: Check cancellation before expensive operation
                        guard !Task.isCancelled else {
                            await MainActor.run {
                                isAutoEditing = false
                                autoEditStatus = "Operation cancelled"
                            }
                            return
                        }
                        
                        // Only analyze NEW VIDEO clips - use cached segments for everything else
                        let newSegmentsFromNewClips = try await autoEditService.generateSegments(
                            for: tempProject,
                            assetsByClipID: assetsByClipID,
                            settings: tempSettings,
                            progressCallback: { [weak self] message in
                                Task { @MainActor in
                                    guard let self = self else { return }
                                    self.autoEditStatus = "Analyzing new video clips: \(message)"
                                    
                                    // Parse progress for time estimation
                                    if message.contains("clip") || message.contains("Analyzing") {
                                        let pattern = #"(\d+)/(\d+)"#
                                        if let range = message.range(of: pattern, options: .regularExpression) {
                                            let clipInfo = String(message[range])
                                            let parts = clipInfo.split(separator: "/")
                                            if parts.count == 2,
                                               let current = Int(parts[0]),
                                               let total = Int(parts[1]),
                                               total > 0 {
                                                self.autoEditProgress = (current, total)
                                                if current > 0 {
                                                    self.updateAutoEditTimeEstimate()
                                                }
                                            }
                                        }
                                    }
                                }
                            },
                            allAnalyzedSegmentsCallback: { [weak self] allSegments in
                                // CRASH-PROOF: Cache all analyzed segments from new VIDEO clips
                                guard let self = self else { return }
                                Task { @MainActor in
                                    // CRASH-PROOF: Capture unanalyzedVideoClips safely - create Set before async callback
                                    let newClipIDs = Set(unanalyzedVideoClips.map { $0.id })
                                    
                                    // CRASH-PROOF: Validate input segments before processing
                                    guard !allSegments.isEmpty else {
                                        print("SkipSlate: ⚠️ Callback received empty segments array - skipping cache update")
                                        return
                                    }
                                    
                                    // Only cache segments from new clips (unanalyzedVideoClips)
                                    let segmentsFromNewClips = allSegments.filter { segment in
                                        // CRASH-PROOF: Comprehensive segment validation
                                        guard segment.isClip,
                                              let clipID = segment.clipID,
                                              segment.duration > 0.01 && segment.duration.isFinite,
                                              segment.sourceStart >= 0 && segment.sourceStart.isFinite,
                                              segment.sourceEnd > segment.sourceStart && segment.sourceEnd.isFinite else {
                                            return false
                                        }
                                        return newClipIDs.contains(clipID)
                                    }
                                    
                                    // CRASH-PROOF: Validate count before appending to prevent memory issues
                                    guard segmentsFromNewClips.count < 10000 else {
                                        print("SkipSlate: ⚠️ Too many segments to cache: \(segmentsFromNewClips.count) (limit: 10000) - skipping cache update")
                                        return
                                    }
                                    
                                    // CRASH-PROOF: Safe appending with validation
                                    guard !segmentsFromNewClips.isEmpty else {
                                        print("SkipSlate: ⚠️ No valid segments to cache after filtering")
                                        return
                                    }
                                    
                                    self.cachedAnalyzedSegments.append(contentsOf: segmentsFromNewClips)
                                    for segment in segmentsFromNewClips {
                                        if let clipID = segment.clipID {
                                            self.cachedAnalyzedClipIDs.insert(clipID)
                                        }
                                    }
                                    print("SkipSlate: ✅ Cached \(segmentsFromNewClips.count) new segments from rerun analysis")
                                }
                            }
                        )
                        
                            // Combine new segments with cached segments
                            allSegmentsFromAllClips = availableCachedSegments + newSegmentsFromNewClips
                        } catch {
                            await MainActor.run {
                                isAutoEditing = false
                                autoEditStatus = "Failed to generate segments"
                                autoEditError = "Error generating segments: \(error.localizedDescription)"
                            }
                            print("SkipSlate: ❌ Rerun Auto-Edit - Segment generation error: \(error)")
                            if let nsError = error as NSError? {
                                print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
                            }
                            return
                        }
                    }
                    
                    // CRASH-PROOF: Filter valid segments with comprehensive validation
                    let validAllSegments: [Segment]
                    do {
                        validAllSegments = allSegmentsFromAllClips.filter { segment in
                            // CRASH-PROOF: Validate each segment property
                            guard segment.isClip else { return false }
                            guard let clipID = segment.clipID else { return false }
                            guard segment.duration > 0.01 && segment.duration.isFinite else { return false }
                            guard segment.sourceStart >= 0 && segment.sourceStart.isFinite else { return false }
                            guard segment.sourceEnd > segment.sourceStart && segment.sourceEnd.isFinite else { return false }
                            guard !deletedClipIDs.contains(clipID) else { return false }
                            
                            // CRASH-PROOF: Verify clip still exists in project
                            guard currentProject.clips.contains(where: { $0.id == clipID }) else { return false }
                            
                            return true
                        }
                    } catch {
                        await MainActor.run {
                            isAutoEditing = false
                            autoEditStatus = "Failed to validate segments"
                            autoEditError = "Error filtering segments: \(error.localizedDescription)"
                        }
                        print("SkipSlate: ❌ Rerun Auto-Edit - Segment validation error: \(error)")
                        return
                    }
                    
                    // CRASH-PROOF: Check cancellation before continuing
                    guard !Task.isCancelled else {
                        await MainActor.run {
                            isAutoEditing = false
                            autoEditStatus = "Operation cancelled"
                        }
                        return
                    }
                    
                    // CRASH-PROOF: Update cache with new segments from new clips
                    do {
                        // CRASH-PROOF: Filter segments from new video clips only
                        let newClipSegments = validAllSegments.filter { segment in
                            guard let clipID = segment.clipID else { return false }
                            // CRASH-PROOF: Safe check - only include segments from unanalyzedVideoClips
                            return unanalyzedVideoClips.contains(where: { $0.id == clipID })
                        }
                        
                        // CRASH-PROOF: Validate before appending to prevent memory issues
                        if newClipSegments.count < 10000 { // Sanity check
                            // Add new segments to cache
                            cachedAnalyzedSegments.append(contentsOf: newClipSegments)
                            for segment in newClipSegments {
                                if let clipID = segment.clipID {
                                    cachedAnalyzedClipIDs.insert(clipID)
                                }
                            }
                            print("SkipSlate: ✅ Added \(newClipSegments.count) new segments from \(unanalyzedVideoClips.count) new video clip(s) to cache")
                        } else {
                            print("SkipSlate: ⚠️ Too many segments to cache: \(newClipSegments.count), skipping cache update")
                        }
                    } catch {
                        print("SkipSlate: ⚠️ Cache update error (non-fatal): \(error)")
                        // Non-fatal, continue with available segments
                    }
                    
                    // Combine cached segments with new segments
                    availableCachedSegments = (availableCachedSegments + validAllSegments).shuffled()
                    print("SkipSlate: ✅ Using \(availableCachedSegments.count) total segments (\(availableCachedSegments.count - validAllSegments.count) cached + \(validAllSegments.count) new) for rerun")
                } else {
                    // We have enough cached segments - use them directly, no analysis needed
                    print("SkipSlate: ✅ Using \(availableCachedSegments.count) cached segments (no analysis needed)")
                    await MainActor.run {
                        self.autoEditStatus = "Using cached segments to fill gaps..."
                    }
                }
                
                // CRITICAL: Prioritize favorited SEGMENTS (not just clips) for rerun
                // Per-segment favoriting allows users to pick specific segments they want
                // CRASH-PROOF: Safe filtering with comprehensive validation
                let favoritedSegments = availableCachedSegments.filter { segment in
                    // CRASH-PROOF: Validate segment properties before checking favorites
                    guard segment.isClip,
                          segment.id != nil,
                          segment.duration > 0.01 && segment.duration.isFinite,
                          let clipID = segment.clipID,
                          !deletedClipIDs.contains(clipID),
                          currentProject.clips.contains(where: { $0.id == clipID }) else {
                        return false
                    }
                    return favoritedSegmentIDs.contains(segment.id)
                }
                
                let nonFavoritedSegments = availableCachedSegments.filter { segment in
                    // CRASH-PROOF: Validate segment properties
                    guard segment.isClip,
                          segment.id != nil,
                          segment.duration > 0.01 && segment.duration.isFinite,
                          let clipID = segment.clipID,
                          !deletedClipIDs.contains(clipID),
                          currentProject.clips.contains(where: { $0.id == clipID }) else {
                        return false
                    }
                    return !favoritedSegmentIDs.contains(segment.id)
                }
                
                // Also prioritize segments from favorited clips (backward compatibility)
                // CRASH-PROOF: Safe filtering with nil checks
                let segmentsFromFavoritedClips = nonFavoritedSegments.filter { segment in
                    guard let clipID = segment.clipID else { return false }
                    return selectedClipIDs.contains(clipID)
                }
                let otherSegments = nonFavoritedSegments.filter { segment in
                    guard let clipID = segment.clipID else { return false }
                    return !selectedClipIDs.contains(clipID)
                }
                
                print("SkipSlate: Rerun Auto-Edit - Prioritizing:")
                print("SkipSlate:   - \(favoritedSegments.count) favorited segments")
                print("SkipSlate:   - \(segmentsFromFavoritedClips.count) segments from favorited clips")
                print("SkipSlate:   - \(otherSegments.count) other segments")
                
                // CRASH-PROOF: Combine segments safely - favorited segments first, then favorited clips, then others
                // CRITICAL: Only use as many favorites as there are gaps to fill
                // User wants: If 10 favorites exist but only 3 segments were deleted, only use 3 favorites
                let gapCount = validGaps.count
                let maxFavoritesToUse = max(0, gapCount) // Use at most one favorite per gap
                
                // Limit favorites to match gap count (user requirement)
                let limitedFavoritedSegments: [Segment]
                if favoritedSegments.count > maxFavoritesToUse {
                    // Use only the first maxFavoritesToUse favorites (shuffled for variety)
                    limitedFavoritedSegments = Array(favoritedSegments.shuffled().prefix(maxFavoritesToUse))
                    print("SkipSlate: Rerun Auto-Edit - Limiting favorites: \(favoritedSegments.count) available, using only \(maxFavoritesToUse) (matching \(gapCount) gaps)")
                } else {
                    // Use all available favorites (if less than gap count)
                    limitedFavoritedSegments = favoritedSegments.shuffled()
                    print("SkipSlate: Rerun Auto-Edit - Using all \(limitedFavoritedSegments.count) favorited segments for \(gapCount) gaps")
                }
                
                // Shuffle each group for variety to prevent predictable selection
                // CRITICAL: Ensure we have enough segments to fill gaps
                let shuffledSegments: [Segment]
                
                do {
                    var tempSegments: [Segment] = []
                    // Use limited favorites (matching gap count)
                    tempSegments.append(contentsOf: limitedFavoritedSegments)
                    tempSegments.append(contentsOf: segmentsFromFavoritedClips.shuffled())
                    tempSegments.append(contentsOf: otherSegments.shuffled())
                    shuffledSegments = tempSegments
                } catch {
                    print("SkipSlate: ❌ ERROR shuffling segments: \(error)")
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "Error preparing segments"
                        autoEditError = "Failed to prepare segments: \(error.localizedDescription)"
                    }
                    return
                }
                
                // CRASH-PROOF: Validate we have segments to use
                guard !shuffledSegments.isEmpty else {
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "No segments available to fill gaps"
                        autoEditError = "No cached segments available. Please run auto-edit first or ensure segments are not all deleted."
                    }
                    print("SkipSlate: ❌ Rerun Auto-Edit - No segments available after filtering")
                    return
                }
                
                var cachedSegmentIndex = 0
                
                // Process each gap segment and replace it with clip segments
                // Track which segments fill which gap (defined at Task scope for MainActor access)
                var gapToSegmentsMap: [UUID: [Segment]] = [:]
                
                for gapSegment in validGaps {
                    // Safety check: Validate gap
                    guard gapSegment.duration > 0.01, gapSegment.compositionStartTime >= 0 else {
                        print("SkipSlate: Skipping invalid gap segment: start=\(gapSegment.compositionStartTime), duration=\(gapSegment.duration)")
                        continue
                    }
                    
                    var remainingGapDuration = gapSegment.duration
                    let gapStartTime = gapSegment.compositionStartTime
                    let maxIterations = 1000  // Safety limit to prevent infinite loops
                    var iterationCount = 0
                    var segmentsForThisGap: [Segment] = []
                    
                    // Fill gap with cached segments (excluding deleted clips)
                    while remainingGapDuration > 0.1 && cachedSegmentIndex < shuffledSegments.count && iterationCount < maxIterations {
                        iterationCount += 1
                        
                        // Safety check: Bounds checking
                        guard cachedSegmentIndex >= 0 && cachedSegmentIndex < shuffledSegments.count else {
                            print("SkipSlate: Rerun Auto-Edit - Segment index out of bounds: \(cachedSegmentIndex)")
                            break
                        }
                        
                        let cachedSegment = shuffledSegments[cachedSegmentIndex]
                        cachedSegmentIndex += 1
                        
                        // Safety check: Validate cached segment (must be a clip, use helper)
                        guard cachedSegment.isClip,
                              let cachedSourceClipID = cachedSegment.clipID,
                              cachedSegment.duration > 0.01,
                              cachedSegment.sourceStart >= 0,
                              cachedSegment.sourceEnd > cachedSegment.sourceStart else {
                            print("SkipSlate: Skipping invalid cached segment: duration=\(cachedSegment.duration)")
                            continue
                        }
                        
                        // CRITICAL: Double-check this clip wasn't deleted (additional safety)
                        guard !deletedClipIDs.contains(cachedSourceClipID) else {
                            print("SkipSlate: 🚫 Skipping segment from deleted clip: \(cachedSourceClipID)")
                            continue
                        }
                        
                        // Safety check: Verify clip still exists
                        guard currentProject.clips.contains(where: { $0.id == cachedSourceClipID }) else {
                            print("SkipSlate: Cached segment references missing clip: \(cachedSourceClipID)")
                            continue
                        }
                        
                        // Create new segment instance with new ID and updated composition start time
                        var newSegment = Segment(
                            id: UUID(),
                            sourceClipID: cachedSourceClipID,
                            sourceStart: cachedSegment.sourceStart,
                            sourceEnd: cachedSegment.sourceEnd,
                            enabled: true,
                            colorIndex: cachedSegment.colorIndex,
                            effects: cachedSegment.effects,
                            compositionStartTime: gapStartTime + (gapSegment.duration - remainingGapDuration)
                        )
                        
                        // Safety check: Validate segment duration before trimming
                        let segmentDuration = newSegment.duration
                        guard segmentDuration > 0.01 else {
                            print("SkipSlate: Skipping segment with invalid duration: \(segmentDuration)")
                            continue
                        }
                        
                        // If segment is longer than remaining gap, trim it
                        if segmentDuration > remainingGapDuration {
                            let originalDuration = segmentDuration
                            let trimmedEnd = newSegment.sourceStart + remainingGapDuration
                            
                            // Safety check: Ensure trimmed end is valid
                            guard trimmedEnd > newSegment.sourceStart, trimmedEnd <= cachedSegment.sourceEnd else {
                                print("SkipSlate: Invalid trim calculation, skipping segment")
                                continue
                            }
                            
                            newSegment.sourceEnd = trimmedEnd
                            print("SkipSlate: Trimmed cached segment from \(String(format: "%.2f", originalDuration))s to \(String(format: "%.2f", remainingGapDuration))s to fit gap")
                        }
                        
                        // Final validation before adding
                        guard newSegment.duration > 0.01,
                              newSegment.compositionStartTime >= 0 else {
                            print("SkipSlate: Skipping invalid new segment")
                            continue
                        }
                        
                        segmentsForThisGap.append(newSegment)
                        remainingGapDuration -= newSegment.duration
                        totalFilled += newSegment.duration
                        
                        // Safety check: Prevent negative remaining duration
                        if remainingGapDuration < 0 {
                            remainingGapDuration = 0
                        }
                    }
                    
                    // Safety check: Prevent infinite loop
                    if iterationCount >= maxIterations {
                        print("SkipSlate: Rerun Auto-Edit - Hit max iterations for gap filling, stopping")
                        break
                    }
                    
                    // If we've exhausted cached segments but still have gaps, we can't fill them
                    // (No re-analysis - user should run full auto-edit if they need more segments)
                    if remainingGapDuration > 0.1 && cachedSegmentIndex >= availableCachedSegments.count {
                        print("SkipSlate: ⚠️ Exhausted all cached segments. Gap of \(String(format: "%.2f", remainingGapDuration))s remains unfilled.")
                        print("SkipSlate: 💡 User should run full auto-edit to generate more segments, or delete fewer segments.")
                        
                        // Log which gap couldn't be filled
                        await MainActor.run {
                            self.autoEditStatus = "Some gaps couldn't be filled - not enough cached segments"
                        }
                        // Continue with what we have - partial fill is better than nothing
                    }
                    
                    // Map segments to this gap
                    gapToSegmentsMap[gapSegment.id] = segmentsForThisGap
                    
                    // Add segments for this gap to the overall list
                    segmentsToAdd.append(contentsOf: segmentsForThisGap)
                }
                
                // Capture gapToSegmentsMap for MainActor block
                let finalGapToSegmentsMap = gapToSegmentsMap
                
                await MainActor.run {
                    // Safety check: Validate segments before adding (using helpers)
                    let validSegmentsToAdd = segmentsToAdd.filter { segment in
                        segment.isClip &&
                        segment.duration > 0.01 &&
                        segment.compositionStartTime >= 0 &&
                        segment.clipID != nil &&
                        project.clips.contains(where: { $0.id == segment.clipID })
                    }
                    
                    guard !validSegmentsToAdd.isEmpty else {
                        isAutoEditing = false
                        autoEditStatus = "Could not generate segments to fill gaps"
                        autoEditError = "No valid segments could be created. Try deleting fewer segments or importing more clips."
                        print("SkipSlate: ❌ Rerun Auto-Edit - No valid segments to add (segmentsToAdd count: \(segmentsToAdd.count))")
                        
                        // CRASH-PROOF: Show helpful debug info
                        print("SkipSlate: Debug - Total gaps: \(validGaps.count), Available clips: \(currentProject.clips.count), Deleted clips: \(deletedClipIDs.count)")
                        return
                    }
                    
                    // CRITICAL: Replace ONLY gap segments, preserve ALL existing clip segments exactly as they are
                    // CRASH-PROOF: Comprehensive validation and error handling
                    var updatedProject: Project
                    var existingClipSegments: [Segment] = []  // Define outside do block for later use
                    
                    do {
                        updatedProject = project
                        
                        // CRASH-PROOF: Validate project state before modification
                        guard !updatedProject.segments.isEmpty || !validSegmentsToAdd.isEmpty else {
                            print("SkipSlate: ⚠️ Rerun Auto-Edit - No segments to work with")
                            isAutoEditing = false
                            autoEditStatus = "No segments available"
                            autoEditError = "Cannot update timeline: no segments found"
                            return
                        }
                        
                        // Get all gap segment IDs that will be replaced
                        let gapSegmentIDs = Set(updatedProject.segments.filter { $0.isGap }.map { $0.id })
                        
                        // CRITICAL: Preserve all existing clip segments (don't touch them!)
                        existingClipSegments = updatedProject.segments.filter { segment in
                            // CRASH-PROOF: Validate each segment
                            guard segment.isClip else { return false }
                            guard segment.duration > 0.01 else { return false }
                            guard segment.compositionStartTime >= 0 else { return false }
                            return true
                        }
                        
                        print("SkipSlate: Preserving \(existingClipSegments.count) existing clip segments with their exact compositionStartTime")
                        
                        // CRASH-PROOF: Validate segments array size to prevent memory issues
                        let totalSegmentsCount = existingClipSegments.count + validSegmentsToAdd.count
                        guard totalSegmentsCount < 5000 else { // Sanity check
                            print("SkipSlate: ⚠️ Too many segments to add: \(totalSegmentsCount)")
                            isAutoEditing = false
                            autoEditStatus = "Too many segments"
                            autoEditError = "Cannot add \(totalSegmentsCount) segments (maximum: 5000)"
                            return
                        }
                        
                        // Build new segments array: existing clips + new segments (replacing gaps)
                        var newSegmentsArray: [Segment] = []
                        
                        // Add all existing clip segments first (preserve them exactly - don't modify compositionStartTime!)
                        newSegmentsArray.append(contentsOf: existingClipSegments)
                        
                        // Add new segments that replace gaps
                        newSegmentsArray.append(contentsOf: validSegmentsToAdd)
                        
                        updatedProject.segments = newSegmentsArray
                        
                        // CRITICAL: Update tracks - replace gap IDs with new segment IDs, preserve existing clip segment IDs and their order
                        // CRASH-PROOF: Validate tracks before modification
                        if updatedProject.tracks.isEmpty {
                            print("SkipSlate: ⚠️ Rerun Auto-Edit - No tracks found, creating default tracks")
                            // Create V1 (base video) and A1 (audio) tracks if none exist
                            let baseVideoTrack = TimelineTrack(
                                kind: .video,
                                index: 0,
                                segments: validSegmentsToAdd.map { $0.id }
                            )
                            let audioTrack = TimelineTrack(kind: .audio, index: 0, segments: [])
                            updatedProject.tracks = [baseVideoTrack, audioTrack]
                        } else {
                            // Update existing tracks
                            for trackIndex in updatedProject.tracks.indices {
                                // CRASH-PROOF: Bounds checking
                                guard trackIndex >= 0 && trackIndex < updatedProject.tracks.count else {
                                    print("SkipSlate: ⚠️ Invalid track index: \(trackIndex)")
                                    continue
                                }
                                
                                var updatedTrackSegments = updatedProject.tracks[trackIndex].segments
                                
                                // Replace gap segment IDs with new clip segment IDs
                                // Use the finalGapToSegmentsMap we captured earlier
                                for (gapID, replacementSegments) in finalGapToSegmentsMap {
                                    // CRASH-PROOF: Validate gap ID and replacement segments
                                    guard !replacementSegments.isEmpty else { continue }
                                    
                                    if let gapIndex = updatedTrackSegments.firstIndex(of: gapID) {
                                        // CRASH-PROOF: Validate index before removal
                                        guard gapIndex >= 0 && gapIndex < updatedTrackSegments.count else {
                                            print("SkipSlate: ⚠️ Invalid gap index: \(gapIndex)")
                                            continue
                                        }
                                        
                                        // Replace gap ID with new segment IDs (maintain order)
                                        updatedTrackSegments.remove(at: gapIndex)
                                        let newSegmentIDs = replacementSegments.map { $0.id }
                                        updatedTrackSegments.insert(contentsOf: newSegmentIDs, at: gapIndex)
                                        print("SkipSlate: Replaced gap \(gapID) with \(newSegmentIDs.count) segments in track \(trackIndex)")
                                    }
                                }
                                
                                updatedProject.tracks[trackIndex].segments = updatedTrackSegments
                            }
                        }
                    } catch {
                        print("SkipSlate: ❌ Rerun Auto-Edit - Project update error: \(error)")
                        isAutoEditing = false
                        autoEditStatus = "Failed to update timeline"
                        autoEditError = "Error updating project: \(error.localizedDescription)"
                        return
                    }
                    
                    print("SkipSlate: ✅ Gap replacement complete - Preserved \(existingClipSegments.count) existing segments, added \(validSegmentsToAdd.count) new segments")
                    
                    // CRITICAL: Validate all segments have valid clips before proceeding
                    var invalidSegments: [Segment] = []
                    var missingClips: [UUID] = []
                    
                    for segment in updatedProject.segments {
                        guard segment.isClip else { continue } // Skip gaps
                        
                        guard let clipID = segment.clipID else {
                            invalidSegments.append(segment)
                            print("SkipSlate: ⚠️ Segment \(segment.id) has no sourceClipID")
                            continue
                        }
                        
                        guard let clip = updatedProject.clips.first(where: { $0.id == clipID }) else {
                            missingClips.append(clipID)
                            invalidSegments.append(segment)
                            print("SkipSlate: ⚠️ Segment references missing clip: \(clipID)")
                            continue
                        }
                        
                        // Validate clip URL is accessible
                        guard FileManager.default.fileExists(atPath: clip.url.path) else {
                            invalidSegments.append(segment)
                            print("SkipSlate: ⚠️ Clip file not found: \(clip.url.path)")
                            continue
                        }
                    }
                    
                    if !invalidSegments.isEmpty {
                        print("SkipSlate: ⚠️ WARNING - Found \(invalidSegments.count) invalid segments after rerun")
                        print("SkipSlate: Removing invalid segments to prevent black screen")
                        let invalidSegmentIDs = Set(invalidSegments.map { $0.id })
                        updatedProject.segments.removeAll(where: { invalidSegmentIDs.contains($0.id) })
                        
                        // Clean up tracks - remove references to invalid segments (already defined above)
                        for trackIndex in updatedProject.tracks.indices {
                            updatedProject.tracks[trackIndex].segments.removeAll(where: { invalidSegmentIDs.contains($0) })
                        }
                        
                        print("SkipSlate: ✅ Cleaned up invalid segments. Remaining segments: \(updatedProject.segments.count)")
                    }
                    
                    // CRITICAL: Validate we still have valid segments after cleanup
                    guard !updatedProject.segments.filter({ $0.isClip }).isEmpty else {
                        print("SkipSlate: ❌ ERROR - No valid clip segments remain after cleanup!")
                        isAutoEditing = false
                        autoEditStatus = "No valid segments after cleanup"
                        autoEditError = "All segments created were invalid. Check if source clips are accessible."
                        return
                    }
                    
                    // CRITICAL: Preserve playback state BEFORE updating project and rebuilding
                    let wasPlaying = playerViewModel?.isPlaying ?? false
                    let savedTime = playerViewModel?.currentTime ?? 0.0
                    print("SkipSlate: 📹 Preserving playback state - wasPlaying: \(wasPlaying), savedTime: \(savedTime)s")
                    
                    // CRASH-PROOF: Validate project has valid segments before updating
                    let enabledSegmentCount = updatedProject.segments.filter { $0.enabled && $0.isClip }.count
                    guard enabledSegmentCount > 0 else {
                        print("SkipSlate: ⚠️ Rerun Auto-Edit - No enabled clip segments after rerun, cannot update project")
                        isAutoEditing = false
                        autoEditStatus = "No valid segments after rerun"
                        autoEditError = "Rerun completed but no valid segments remain. Try running full auto-edit."
                        return
                    }
                    
                    project = updatedProject
                    
                    // Reset modification flag after successful rerun
                    hasUserModifiedAutoEdit = false
                    lastAutoEditRunID = UUID()
                    
                    let filledDuration = validSegmentsToAdd.reduce(0.0) { $0 + $1.duration }
                    autoEditStatus = "Filled gaps with \(validSegmentsToAdd.count) segments (\(String(format: "%.1f", filledDuration))s)"
                    isAutoEditing = false
                    
                    print("SkipSlate: Rerun Auto-Edit complete - Added \(validSegmentsToAdd.count) segments to fill gaps")
                    
                    // CRASH-PROOF: Rebuild preview composition - preserve playback state
                    // CRITICAL: Validate project has segments with enabled clips before rebuilding
                    let finalEnabledCount = project.segments.filter { $0.enabled && $0.isClip }.count
                    guard finalEnabledCount > 0 else {
                        print("SkipSlate: ⚠️ Cannot rebuild - project has no enabled clip segments after rerun")
                        print("SkipSlate: Total segments: \(project.segments.count), Enabled: \(project.segments.filter { $0.enabled }.count), Clips: \(project.segments.filter { $0.isClip }.count)")
                        return
                    }
                    
                    // CRITICAL: Rebuild composition and restore playback state after rebuild completes
                    // CRASH-PROOF: Wrap entire operation in comprehensive error handling
                    Task { @MainActor in
                        do {
                            // CRASH-PROOF: Validate project and playerViewModel before proceeding
                            // CRITICAL: Capture project state BEFORE async operations to prevent race conditions
                            let projectToRebuild = self.project
                            
                            // CRASH-PROOF: Double-check we have enabled clip segments
                            let enabledClipSegments = projectToRebuild.segments.filter { $0.enabled && $0.isClip }
                            guard !enabledClipSegments.isEmpty else {
                                print("SkipSlate: ⚠️ Cannot rebuild - project has no enabled clip segments (count: 0)")
                                print("SkipSlate: Project has \(projectToRebuild.clips.count) clips, \(projectToRebuild.tracks.count) tracks")
                                print("SkipSlate: Total segments: \(projectToRebuild.segments.count)")
                                return
                            }
                            
                            guard let playerVM = playerViewModel else {
                                print("SkipSlate: ⚠️ PlayerViewModel is nil, cannot rebuild composition")
                                return
                            }
                            
                            // CRASH-PROOF: Log project state before rebuild
                            let enabledCount = enabledClipSegments.count
                            print("SkipSlate: 🔄 Rebuilding composition with \(enabledCount) enabled clip segments from \(projectToRebuild.segments.count) total segments")
                            
                            // Rebuild composition (this is async and will update the player)
                            // CRASH-PROOF: Wrap in error handling and pass captured project state
                            autoreleasepool {
                                playerVM.rebuildComposition(from: projectToRebuild)
                            }
                            
                            // CRASH-PROOF: Wait for composition with timeout - shorter timeout to prevent freezing
                            // Don't wait too long - if it takes more than 1.5 seconds, just proceed
                            var attempts = 0
                            let maxAttempts = 15 // Max 1.5 seconds wait (15 * 0.1s) - shorter to prevent freeze
                            var compositionReady = false
                            var playerItemStatus: AVPlayerItem.Status? = nil
                            
                            while attempts < maxAttempts && !compositionReady {
                                await Task.yield()
                                
                                // CRASH-PROOF: Safe access to player item status
                                var shouldExit = false
                                autoreleasepool {
                                    if let player = playerVM.player,
                                       let playerItem = player.currentItem {
                                        let status = playerItem.status
                                        playerItemStatus = status
                                        
                                        if status == .readyToPlay {
                                            compositionReady = true
                                            shouldExit = true
                                            print("SkipSlate: ✅ Composition ready after \(attempts * 100)ms")
                                        } else if status == .failed {
                                            shouldExit = true
                                            print("SkipSlate: ⚠️ Player item failed, proceeding anyway")
                                        }
                                    }
                                }
                                
                                // Exit loop if needed
                                if shouldExit {
                                    break
                                }
                                
                                // Small delay between checks
                                do {
                                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                } catch {
                                    print("SkipSlate: ⚠️ Task.sleep error: \(error)")
                                    compositionReady = true // Exit loop on error by marking as ready
                                    break
                                }
                                attempts += 1
                            }
                            
                            if !compositionReady {
                                print("SkipSlate: ⚠️ Composition not ready after \(maxAttempts * 100)ms (status: \(playerItemStatus?.rawValue ?? -1)), proceeding with playback restoration anyway (timeout to prevent freeze)")
                            }
                            
                            // CRASH-PROOF: Small delay to ensure player is initialized, but don't wait too long
                            do {
                                try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds - shorter delay
                            } catch {
                                print("SkipSlate: ⚠️ Task.sleep error during delay: \(error)")
                                // Continue anyway
                            }
                            
                            // CRASH-PROOF: Restore playback state with comprehensive validation
                            autoreleasepool {
                                    if wasPlaying {
                                        // CRASH-PROOF: Re-validate player state before restoring
                                        guard let validPlayerVM = playerViewModel else {
                                            print("SkipSlate: ⚠️ PlayerViewModel is nil during playback restoration")
                                            return
                                        }
                                        
                                        // CRASH-PROOF: Validate player exists and is valid
                                        guard let player = validPlayerVM.player else {
                                            print("SkipSlate: ⚠️ Player is nil during playback restoration")
                                            return
                                        }
                                        
                                        // CRASH-PROOF: Validate seek time before seeking
                                        let duration = validPlayerVM.duration
                                        let maxDuration = (duration.isFinite && duration > 0) ? duration : 50.0
                                        let seekTime = min(max(0.0, savedTime), maxDuration)
                                        
                                        // CRASH-PROOF: Validate seek time is finite
                                        guard seekTime.isFinite && seekTime >= 0 else {
                                            print("SkipSlate: ⚠️ Invalid seek time: \(seekTime), skipping playback restoration")
                                            return
                                        }
                                        
                                        print("SkipSlate: 📹 Restoring playback - seeking to \(seekTime)s and resuming playback")
                                        
                                        // CRASH-PROOF: Seek and resume playback with timeout protection
                                        // Use a completion handler that doesn't block indefinitely
                                        validPlayerVM.seek(to: seekTime, precise: true) { [weak validPlayerVM] finished in
                                            guard let validPlayerVM = validPlayerVM else {
                                                print("SkipSlate: ⚠️ PlayerViewModel deallocated during seek completion")
                                                return
                                            }
                                            
                                            // CRASH-PROOF: Proceed even if seek didn't finish (timeout protection)
                                            DispatchQueue.main.async {
                                                autoreleasepool {
                                                    // CRASH-PROOF: Validate player before playing
                                                    guard validPlayerVM.player != nil else {
                                                        print("SkipSlate: ⚠️ Player is nil during play attempt")
                                                        return
                                                    }
                                                    
                                                    if finished {
                                                        validPlayerVM.play()
                                                        print("SkipSlate: ✅ Playback restored after rerun auto-edit")
                                                    } else {
                                                        // Seek didn't complete, but try to play anyway to prevent freeze
                                                        print("SkipSlate: ⚠️ Seek did not complete, attempting to play anyway")
                                                        validPlayerVM.play()
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        // If not playing, just seek to saved time (non-blocking)
                                        if let validPlayerVM = playerViewModel,
                                           savedTime > 0 && savedTime.isFinite {
                                            let duration = validPlayerVM.duration
                                            let maxDuration = (duration.isFinite && duration > 0) ? duration : 50.0
                                            let seekTime = min(max(0.0, savedTime), maxDuration)
                                            
                                            // CRASH-PROOF: Validate seek time
                                            if seekTime.isFinite && seekTime >= 0 {
                                                validPlayerVM.seek(to: seekTime, precise: true) { _ in }
                                            }
                                        }
                                    }
                            }
                        } catch {
                            // CRASH-PROOF: Catch any errors and log them without crashing
                            print("SkipSlate: ❌ CRITICAL ERROR during rerun composition rebuild: \(error)")
                            if let nsError = error as NSError? {
                                print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code)")
                                print("SkipSlate: Error description: \(nsError.localizedDescription)")
                            }
                            
                            // CRASH-PROOF: Ensure UI state is updated even on error
                            await MainActor.run {
                                isAutoEditing = false
                                autoEditError = "Failed to rebuild composition: \(error.localizedDescription)"
                            }
                        }
                    }
                    
                    // Clear time estimate
                    autoEditTimeEstimate = nil
                    autoEditStartTime = nil
                    autoEditProgress = (0, 0)
                }
            } catch {
                // CRASH-PROOF: Comprehensive error handling and recovery
                await MainActor.run {
                    isAutoEditing = false
                    
                    // Provide user-friendly error messages
                    let errorMessage: String
                    if let autoEditError = error as? AutoEditError {
                        switch autoEditError {
                        case .noUsableAudio:
                            errorMessage = "No usable audio found in clips"
                        case .noClips:
                            errorMessage = "No clips available"
                        case .analysisFailed(let reason):
                            errorMessage = "Analysis failed: \(reason)"
                        }
                    } else if let nsError = error as NSError? {
                        errorMessage = nsError.localizedDescription
                        
                        // Log detailed error info for debugging
                        print("SkipSlate: ❌ Rerun Auto-Edit error - Domain: \(nsError.domain), Code: \(nsError.code)")
                        if let userInfo = nsError.userInfo as? [String: Any], !userInfo.isEmpty {
                            print("SkipSlate: Error userInfo: \(userInfo)")
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    
                    autoEditStatus = "Failed to rerun auto-edit"
                    autoEditError = "Error: \(errorMessage)"
                    
                    // Clear time estimate on error
                    autoEditTimeEstimate = nil
                    autoEditStartTime = nil
                    autoEditProgress = (0, 0)
                    
                    print("SkipSlate: ❌ Rerun Auto-Edit error: \(error)")
                    print("SkipSlate: Error type: \(String(describing: Swift.type(of: error)))")
                    
                    // CRASH-PROOF: Attempt to preserve project state
                    // Project should already be in a valid state, but log if something is wrong
                    if project.segments.isEmpty {
                        print("SkipSlate: ⚠️ WARNING - Project segments became empty after error!")
                    }
                }
            }
        }
    }
    
    /// Detect gaps in the current timeline
    private func detectGapsInTimeline() -> [(startTime: Double, duration: Double)] {
        // Safety check: Ensure we have segments
        guard !project.segments.isEmpty else {
            return []
        }
        
        let enabledSegments = project.segments.filter { $0.enabled }
        guard !enabledSegments.isEmpty else {
            return []
        }
        
        // Safety check: Filter out invalid segments (only check clip segments, gaps are valid)
        let validSegments = enabledSegments.filter { segment in
            let duration = segment.duration
            guard duration > 0.01 else { return false }
            
            // For clip segments, verify clip exists (using helper)
            if let clipID = segment.clipID {
                guard project.clips.contains(where: { $0.id == clipID }) else {
                    return false
                }
            }
            // Gap segments are always valid
            
            return true
        }
        
        guard !validSegments.isEmpty else {
            return []
        }
        
        // Sort segments by composition start time
        let sortedSegments = validSegments.sorted { seg1, seg2 in
            let start1 = seg1.compositionStartTime > 0 ? seg1.compositionStartTime : compositionStart(for: seg1)
            let start2 = seg2.compositionStartTime > 0 ? seg2.compositionStartTime : compositionStart(for: seg2)
            return start1 < start2
        }
        
        var gaps: [(startTime: Double, duration: Double)] = []
        var currentTime: Double = 0.0
        
        for segment in sortedSegments {
            // Safety check: Validate segment
            guard segment.duration > 0.01 else {
                print("SkipSlate: Skipping invalid segment in gap detection: duration=\(segment.duration)")
                continue
            }
            
            let segmentStart = segment.compositionStartTime > 0 ? segment.compositionStartTime : compositionStart(for: segment)
            let segmentEnd = segmentStart + segment.duration
            
            // Safety check: Validate calculated times
            guard segmentStart >= 0, segmentEnd > segmentStart else {
                print("SkipSlate: Skipping segment with invalid times: start=\(segmentStart), end=\(segmentEnd)")
                continue
            }
            
            // If there's a gap before this segment
            if segmentStart > currentTime + 0.01 {  // 0.01s tolerance for floating point
                let gapDuration = segmentStart - currentTime
                
                // Safety check: Only add valid gaps
                if gapDuration > 0.01 && gapDuration < 3600.0 {  // Max 1 hour gap (sanity check)
                    gaps.append((startTime: currentTime, duration: gapDuration))
                    print("SkipSlate: Detected gap from \(String(format: "%.2f", currentTime))s to \(String(format: "%.2f", segmentStart))s (duration: \(String(format: "%.2f", gapDuration))s)")
                } else {
                    print("SkipSlate: Skipping invalid gap: duration=\(gapDuration)s")
                }
            }
            
            currentTime = max(currentTime, segmentEnd)
            
            // Safety check: Prevent infinite time values
            if currentTime > 86400.0 {  // Max 24 hours (sanity check)
                print("SkipSlate: Gap detection - Time exceeded 24 hours, stopping")
                break
            }
        }
        
        return gaps
    }
    
    /// Fill gaps in the timeline by re-running auto-edit only for missing segments
    /// This creates new segments from unused portions of clips to fill the timeline
    /// DEPRECATED: Use rerunAutoEdit() instead
    func fillGaps() {
        guard !project.clips.isEmpty else {
            autoEditError = "No clips available to fill gaps"
            return
        }
        
        isAutoEditing = true
        autoEditStatus = "Analyzing gaps and generating new clip cuts..."
        autoEditError = nil
        
        prepareAssetsIfNeeded()
        
        let currentProject = project
        let currentSettings = autoEditSettings
        
        Task {
            do {
                // Calculate total duration of existing enabled segments
                let existingDuration = currentProject.segments.filter { $0.enabled }.reduce(0.0) { $0 + $1.duration }
                
                // Calculate target duration (use original target or existing + some padding)
                let targetDuration = currentSettings.targetLengthSeconds ?? max(existingDuration * 1.2, 30.0)
                
                // Calculate how much time we need to fill
                let neededDuration = max(0, targetDuration - existingDuration)
                
                print("SkipSlate: Fill gaps - existing duration: \(existingDuration)s, target: \(targetDuration)s, needed: \(neededDuration)s")
                
                if neededDuration <= 0.5 {
                    // No significant gap to fill
                    await MainActor.run {
                        isAutoEditing = false
                        autoEditStatus = "Timeline is already full"
                    }
                    return
                }
                
                // Generate new segments to fill the gap
                // We'll generate segments from all clips, but prioritize unused clips
                let existingClipIDs = Set(currentProject.segments.compactMap { $0.sourceClipID })
                let unusedClips = currentProject.clips.filter { !existingClipIDs.contains($0.id) }
                
                print("SkipSlate: Fill gaps - \(unusedClips.count) unused clips available out of \(currentProject.clips.count) total")
                
                // Generate segments with a target length matching the gap
                var tempSettings = currentSettings
                tempSettings.targetLengthSeconds = neededDuration
                
                var newSegments = try await autoEditService.generateSegments(
                    for: currentProject,
                    assetsByClipID: assetsByClipID,
                    settings: tempSettings,
                    progressCallback: { [weak self] message in
                        Task { @MainActor in
                            self?.autoEditStatus = "Filling gaps: \(message)"
                        }
                    }
                )
                
                // Prioritize segments from unused clips, but allow reusing clips if needed
                newSegments.sort { seg1, seg2 in
                    guard let seg1ClipID = seg1.sourceClipID,
                          let seg2ClipID = seg2.sourceClipID else {
                        return false
                    }
                    let seg1Unused = !existingClipIDs.contains(seg1ClipID)
                    let seg2Unused = !existingClipIDs.contains(seg2ClipID)
                    if seg1Unused != seg2Unused {
                        return seg1Unused // Prefer unused clips
                    }
                    return seg1.duration > seg2.duration // Then prefer longer segments
                }
                
                // Add segments until we fill the gap (with some tolerance)
                var accumulatedDuration = existingDuration
                var segmentsToAdd: [Segment] = []
                let targetWithTolerance = targetDuration * 1.1 // Allow 10% over
                
                for segment in newSegments {
                    if accumulatedDuration >= targetWithTolerance {
                        break
                    }
                    segmentsToAdd.append(segment)
                    accumulatedDuration += segment.duration
                }
                
                await MainActor.run {
                    // Insert new segments at the end of the timeline
                    var updatedProject = project
                    updatedProject.segments.append(contentsOf: segmentsToAdd)
                    project = updatedProject
                    
                    autoEditStatus = "Added \(segmentsToAdd.count) new clip cuts to fill gaps"
                    isAutoEditing = false
                    
                    print("SkipSlate: Fill gaps complete - added \(segmentsToAdd.count) segments, new total: \(project.segments.count)")
                    
                    // Rebuild preview composition
                    // Use playerVM computed property to ensure PlayerViewModel exists
                    playerVM.rebuildComposition(from: project)
                }
            } catch {
                await MainActor.run {
                    isAutoEditing = false
                    autoEditStatus = "Failed to fill gaps"
                    autoEditError = "Error: \(error.localizedDescription)"
                    print("SkipSlate: Fill gaps error: \(error)")
                }
            }
        }
    }
    
    func reorderSegments(from source: IndexSet, to destination: Int) {
        // Legacy method for single-track reordering - find the base video track (V1) and reorder there
        guard let baseVideoTrackIndex = project.tracks.firstIndex(where: { $0.kind == .video && $0.index == 0 }) else {
            print("SkipSlate: No base video track (V1) found")
            return
        }
        
        reorderSegment(inTrack: project.tracks[baseVideoTrackIndex].id, fromOffsets: source, toOffset: destination)
    }
    
    func splitSegment(_ segment: Segment, at cutTime: Double) {
        guard let index = project.segments.firstIndex(where: { $0.id == segment.id }) else { return }
        
        // Use actual compositionStartTime from segment (not calculated)
        let segmentCompStart = segment.compositionStartTime
        let segmentCompEnd = segmentCompStart + segment.duration
        
        // Validate cut time is within segment bounds
        guard cutTime >= segmentCompStart + 0.1 && cutTime <= segmentCompEnd - 0.1 else {
            print("SkipSlate: ⚠️ Cut time \(cutTime)s is outside segment bounds [\(segmentCompStart)s - \(segmentCompEnd)s]")
            return
        }
        
        // Only split clip segments (gaps cannot be split)
        guard let sourceClipID = segment.clipID else {
            print("SkipSlate: ⚠️ Cannot split gap segment")
            return
        }
        
        // Wrap in undoable change
        performUndoableChange("Split segment") {
            // Calculate offset in composition time
            let compositionOffset = cutTime - segmentCompStart
            
            // Calculate corresponding offset in source time
            let sourceDuration = segment.sourceEnd - segment.sourceStart
            let sourceOffset = (compositionOffset / segment.duration) * sourceDuration
            let newSourceSplitPoint = segment.sourceStart + sourceOffset
            
            // Validate source split point is within bounds
            guard newSourceSplitPoint > segment.sourceStart + 0.1 && newSourceSplitPoint < segment.sourceEnd - 0.1 else {
                print("SkipSlate: ⚠️ Calculated source split point \(newSourceSplitPoint)s is invalid")
                return
            }
            
            // Create first segment (from start to cut point)
            var segA = Segment(
                id: UUID(),
                sourceClipID: sourceClipID,
                sourceStart: segment.sourceStart,
                sourceEnd: newSourceSplitPoint,
                enabled: segment.enabled,
                colorIndex: segment.colorIndex,
                compositionStartTime: segmentCompStart
            )
            segA.effects = segment.effects
            
            // Create second segment (from cut point to end)
            var segB = Segment(
                id: UUID(),
                sourceClipID: sourceClipID,
                sourceStart: newSourceSplitPoint,
                sourceEnd: segment.sourceEnd,
                enabled: segment.enabled,
                colorIndex: segment.colorIndex,
                compositionStartTime: cutTime
            )
            segB.effects = segment.effects
            
            print("SkipSlate: ✂️ Splitting segment:")
            print("SkipSlate:   Original: compStart=\(segmentCompStart)s, duration=\(segment.duration)s, source=\(segment.sourceStart)s-\(segment.sourceEnd)s")
            print("SkipSlate:   SegA: compStart=\(segA.compositionStartTime)s, duration=\(segA.duration)s, source=\(segA.sourceStart)s-\(segA.sourceEnd)s")
            print("SkipSlate:   SegB: compStart=\(segB.compositionStartTime)s, duration=\(segB.duration)s, source=\(segB.sourceStart)s-\(segB.sourceEnd)s")
            
            // Find which track contains this segment and update track references
            for (trackIndex, track) in project.tracks.enumerated() {
                if let segmentIndex = track.segments.firstIndex(of: segment.id) {
                    project.tracks[trackIndex].segments.remove(at: segmentIndex)
                    project.tracks[trackIndex].segments.insert(segB.id, at: segmentIndex)
                    project.tracks[trackIndex].segments.insert(segA.id, at: segmentIndex)
                    print("SkipSlate: ✅ Updated track \(trackIndex) with split segments")
                    break
                }
            }
            
            // Replace original with two new segments in the segments array
            project.segments.remove(at: index)
            project.segments.insert(segB, at: index)
            project.segments.insert(segA, at: index)
            
            // Mark as modified
            hasUserModifiedAutoEdit = true
            
            // Clear selection
            selectedSegmentIDs.removeAll()
            selectedSegment = nil
        }
        // Note: immediateRebuild is called by performUndoableChange
        
        print("SkipSlate: ✅ Split complete - segment split into two at \(cutTime)s")
    }
    
    func seekToSegment(_ segment: Segment) {
        // Use compositionStart method which now uses stored start times
        let compositionStart = compositionStart(for: segment)
        
        // Update selected segment first
        selectedSegment = segment
        
        // Precise seek to the exact start of the segment, then start playing
        playerViewModel?.seek(to: compositionStart, precise: true) { [weak self] completed in
            guard completed, let self = self else { return }
            // Start playing immediately after precise seek completes
            DispatchQueue.main.async {
                self.playerViewModel?.play()
            }
        }
    }
    
    func compositionStart(for segment: Segment) -> Double {
        // Use stored compositionStartTime (supports gaps - non-ripple behavior)
        // If not set (-1), fall back to calculating from track order (for backward compatibility)
        // NOTE: >= 0 check allows position 0.0 (first segment) to be valid
        if segment.compositionStartTime >= 0 || project.segments.contains(where: { $0.id == segment.id && $0.compositionStartTime >= 0 }) {
            // Use stored start time
            if let storedSegment = project.segments.first(where: { $0.id == segment.id }) {
                if storedSegment.compositionStartTime >= 0 {
                    return storedSegment.compositionStartTime
                }
            }
        }
        
        // Fallback: Calculate from track order (for segments created before explicit start times)
        guard let track = track(containing: segment.id) else {
            // Fallback to old behavior if segment not in any track
            var start: Double = 0.0
            for seg in project.segments {
                if seg.id == segment.id {
                    break
                }
                if seg.enabled {
                    start += seg.duration
                }
            }
            return start
        }
        
        // Calculate start time based on segments before this one in the same track
        let segmentDict = Dictionary(uniqueKeysWithValues: project.segments.map { ($0.id, $0) })
        var start: Double = 0.0
        
        for segmentID in track.segments {
            if segmentID == segment.id {
                break
            }
            if let seg = segmentDict[segmentID], seg.enabled {
                start += seg.duration
            }
        }
        
        return start
    }
    
    func updateAudioSettings(_ settings: AudioSettings) {
        project.audioSettings = settings
        playerViewModel?.updateAudioSettings(settings)
    }
    
    func export(to url: URL, format: ExportFormat) {
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                try await ExportService.shared.export(
                    project: project,
                    to: url,
                    format: format,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.exportProgress = progress
                        }
                    }
                )
                
                await MainActor.run {
                    isExporting = false
                    exportProgress = 1.0
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    print("Export error: \(error)")
                }
            }
        }
    }
}

// MARK: - Transform Debug Helpers

extension ProjectViewModel {
    func debugLogSelectedSegment(_ note: String) {
        if let seg = selectedSegment {
            print("SkipSlate: [Transform DEBUG] \(note) – segment id=\(seg.id), scale=\(seg.effects.scale), pos=(\(seg.effects.positionX), \(seg.effects.positionY)), rot=\(seg.effects.rotation), scaleToFill=\(seg.transform.scaleToFillFrame)")
        } else {
            print("SkipSlate: [Transform DEBUG] \(note) – no selected segment")
        }
    }
}

