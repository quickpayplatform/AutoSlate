//
//  MenuActions.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  Central handler for all menu bar actions in Auto Slate
//

import SwiftUI
import AppKit

enum WorkspaceType {
    case `default`
    case clipRoom
    case storyRoom
    case podcastRoom
    case syncRoom
    case slateRoom
}

class MenuActions: ObservableObject {
    static let shared = MenuActions()
    
    // Reference to app view model (set from app)
    weak var appViewModel: AppViewModel?
    
    private init() {}
    
    // MARK: - Application Menu
    
    func showAbout() {
        print("[Menu] About Auto Slate triggered")
        // TODO: Show about dialog
    }
    
    func showPreferences() {
        print("[Menu] Preferences triggered")
        // TODO: Open preferences window
    }
    
    // MARK: - File Menu
    
    func newProject() {
        print("[Menu] New Project triggered")
        appViewModel?.startNewProject()
    }
    
    func openProject() {
        print("[Menu] Open Project triggered")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json] // Assuming projects are saved as JSON
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("[Menu] Opening project from: \(url.path)")
                // TODO: Load project from URL
                // This would need to be implemented in AppViewModel
            }
        }
    }
    
    func closeProject() {
        print("[Menu] Close Project triggered")
        // TODO: Close current project and return to welcome screen
        appViewModel?.isInWizard = false
        appViewModel?.projectViewModel = nil
    }
    
    func saveProject() {
        print("[Menu] Save Project triggered")
        guard let projectVM = appViewModel?.projectViewModel else {
            print("[Menu] No project to save")
            return
        }
        // TODO: Save project to file
        // This would need to be implemented in ProjectViewModel
    }
    
    func saveProjectAs() {
        print("[Menu] Save Project As triggered")
        guard let projectVM = appViewModel?.projectViewModel else {
            print("[Menu] No project to save")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = projectVM.projectName + ".autoslate"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("[Menu] Saving project to: \(url.path)")
                // TODO: Save project to URL
            }
        }
    }
    
    func revertToSaved() {
        print("[Menu] Revert to Saved triggered")
        // TODO: Revert project to last saved state
    }
    
    func importMedia() {
        print("[Menu] Import Media triggered")
        guard let projectVM = appViewModel?.projectViewModel else {
            print("[Menu] No project - cannot import media")
            return
        }
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audio, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        panel.begin { response in
            if response == .OK {
                projectVM.importMedia(urls: panel.urls)
            }
        }
    }
    
    func importFolderAsProject() {
        print("[Menu] Import Folder as Project triggered")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                print("[Menu] Importing folder as project: \(url.path)")
                // TODO: Import folder contents as project
            }
        }
    }
    
    func importFromCamera() {
        print("[Menu] Import From Camera triggered")
        // TODO: Open camera import interface
    }
    
    func quickExport() {
        print("[Menu] Quick Export triggered")
        guard let projectVM = appViewModel?.projectViewModel else {
            print("[Menu] No project - cannot export")
            return
        }
        
        guard !projectVM.segments.isEmpty else {
            print("[Menu] No segments to export")
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = projectVM.projectName + ".mp4"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                projectVM.export(to: url, format: .mp4)
            }
        }
    }
    
    func exportProject() {
        print("[Menu] Export Project triggered")
        quickExport() // For now, same as quick export
    }
    
    func exportSelectedRange() {
        print("[Menu] Export Selected Range triggered")
        // TODO: Export only selected time range
    }
    
    func showProjectSettings() {
        print("[Menu] Project Settings triggered")
        // TODO: Show project settings window
    }
    
    // MARK: - Edit Menu
    
    func undo() {
        print("[Menu] Undo triggered")
        // Call ProjectViewModel undo if available
        if let projectViewModel = appViewModel?.projectViewModel {
            projectViewModel.undo()
        }
    }
    
    func redo() {
        print("[Menu] Redo triggered")
        // Call ProjectViewModel redo if available
        if let projectViewModel = appViewModel?.projectViewModel {
            projectViewModel.redo()
        }
    }
    
    func cut() {
        print("[Menu] Cut triggered")
        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    }
    
    func copy() {
        print("[Menu] Copy triggered")
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    }
    
    func paste() {
        print("[Menu] Paste triggered")
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
    
    func delete() {
        print("[Menu] Delete triggered")
        // TODO: Delete selected segments/clips
        guard let projectVM = appViewModel?.projectViewModel,
              let selectedSegment = projectVM.selectedSegment else {
            return
        }
        projectVM.deleteSegment(selectedSegment)
    }
    
    func selectAll() {
        print("[Menu] Select All triggered")
        // TODO: Select all segments/clips
    }
    
    func deselectAll() {
        print("[Menu] Deselect All triggered")
        guard let projectVM = appViewModel?.projectViewModel else { return }
        projectVM.selectedSegment = nil
    }
    
    func splitAtPlayhead() {
        print("[Menu] Split at Playhead triggered")
        guard let projectVM = appViewModel?.projectViewModel,
              let selectedSegment = projectVM.selectedSegment else {
            return
        }
        // Get current playhead time from player
        let playheadTime = projectVM.playerVM.currentTime
        projectVM.splitSegment(selectedSegment, at: playheadTime)
    }
    
    func rippleDelete() {
        print("[Menu] Ripple Delete triggered")
        // TODO: Delete segment and close gap
        delete() // For now, same as delete
    }
    
    func trimStartToPlayhead() {
        print("[Menu] Trim Start to Playhead triggered")
        guard let projectVM = appViewModel?.projectViewModel,
              let selectedSegment = projectVM.selectedSegment else {
            return
        }
        let playheadTime = projectVM.playerVM.currentTime
        let compositionStart = projectVM.compositionStart(for: selectedSegment)
        let offset = playheadTime - compositionStart
        if offset > 0 {
            projectVM.updateSegmentTiming(selectedSegment, start: selectedSegment.sourceStart + offset, end: selectedSegment.sourceEnd)
        }
    }
    
    func trimEndToPlayhead() {
        print("[Menu] Trim End to Playhead triggered")
        guard let projectVM = appViewModel?.projectViewModel,
              let selectedSegment = projectVM.selectedSegment else {
            return
        }
        let playheadTime = projectVM.playerVM.currentTime
        let compositionStart = projectVM.compositionStart(for: selectedSegment)
        let offset = playheadTime - compositionStart
        if offset > 0 && offset < selectedSegment.duration {
            projectVM.updateSegmentTiming(selectedSegment, start: selectedSegment.sourceStart, end: selectedSegment.sourceStart + offset)
        }
    }
    
    func clearInOutPoints() {
        print("[Menu] Clear In/Out Points triggered")
        // TODO: Clear in/out points
    }
    
    // MARK: - View Menu
    
    func zoomInTimeline() {
        print("[Menu] Zoom In Timeline triggered")
        // TODO: Zoom in timeline view
    }
    
    func zoomOutTimeline() {
        print("[Menu] Zoom Out Timeline triggered")
        // TODO: Zoom out timeline view
    }
    
    func fitTimelineToWindow() {
        print("[Menu] Fit Timeline to Window triggered")
        // TODO: Fit timeline to window
    }
    
    func toggleWaveformPanel() {
        print("[Menu] Toggle Waveform Panel triggered")
        // TODO: Toggle waveform panel visibility
    }
    
    func toggleInspectorPanel() {
        print("[Menu] Toggle Inspector Panel triggered")
        // TODO: Toggle inspector panel visibility
    }
    
    func toggleMediaLibraryPanel() {
        print("[Menu] Toggle Media Library Panel triggered")
        // TODO: Toggle media library panel visibility
    }
    
    func toggleAudioMixerPanel() {
        print("[Menu] Toggle Audio Mixer Panel triggered")
        // TODO: Toggle audio mixer panel visibility
    }
    
    func showFullscreenViewer() {
        print("[Menu] Show Fullscreen Viewer triggered")
        // TODO: Enter fullscreen preview
    }
    
    func exitFullscreenViewer() {
        print("[Menu] Exit Fullscreen Viewer triggered")
        // TODO: Exit fullscreen preview
    }
    
    func switchWorkspace(_ workspace: WorkspaceType) {
        print("[Menu] Switch Workspace to \(workspace) triggered")
        // TODO: Switch to workspace
    }
    
    // MARK: - Clip Menu
    
    func enableDisableClip() {
        print("[Menu] Enable/Disable Clip triggered")
        guard let projectVM = appViewModel?.projectViewModel,
              let selectedSegment = projectVM.selectedSegment else {
            return
        }
        projectVM.toggleSegmentEnabled(selectedSegment)
    }
    
    func linkAudioAndVideo() {
        print("[Menu] Link Audio and Video triggered")
        // TODO: Link audio and video tracks
    }
    
    func unlinkAudioAndVideo() {
        print("[Menu] Unlink Audio and Video triggered")
        // TODO: Unlink audio and video tracks
    }
    
    func detachAudioToNewTrack() {
        print("[Menu] Detach Audio to New Track triggered")
        // TODO: Detach audio to new track
    }
    
    func normalizeClipAudio() {
        print("[Menu] Normalize Clip Audio triggered")
        // TODO: Normalize selected clip audio
    }
    
    func resetClipAudio() {
        print("[Menu] Reset Clip Audio triggered")
        // TODO: Reset clip audio settings
    }
    
    func groupClips() {
        print("[Menu] Group Clips triggered")
        // TODO: Group selected clips
    }
    
    func ungroupClips() {
        print("[Menu] Ungroup Clips triggered")
        // TODO: Ungroup selected clips
    }
    
    func setClipSpeed(_ speed: Double) {
        print("[Menu] Set Clip Speed to \(speed)% triggered")
        // TODO: Set clip speed
    }
    
    // MARK: - Sequence Menu
    
    func newSequenceFromSelection() {
        print("[Menu] New Sequence from Selection triggered")
        // TODO: Create new sequence from selection
    }
    
    func showSequenceSettings() {
        print("[Menu] Sequence Settings triggered")
        // TODO: Show sequence settings
    }
    
    func markIn() {
        print("[Menu] Mark In triggered")
        // TODO: Mark in point at playhead
    }
    
    func markOut() {
        print("[Menu] Mark Out triggered")
        // TODO: Mark out point at playhead
    }
    
    func clearInOut() {
        print("[Menu] Clear In/Out triggered")
        clearInOutPoints()
    }
    
    func goToIn() {
        print("[Menu] Go to In triggered")
        // TODO: Seek to in point
    }
    
    func goToOut() {
        print("[Menu] Go to Out triggered")
        // TODO: Seek to out point
    }
    
    func renderPreviewCache() {
        print("[Menu] Render Preview Cache triggered")
        // TODO: Render preview cache
    }
    
    func clearPreviewCache() {
        print("[Menu] Clear Preview Cache triggered")
        // TODO: Clear preview cache
    }
    
    // MARK: - Audio Menu
    
    func muteSelection() {
        print("[Menu] Mute Selection triggered")
        // TODO: Mute selected segments
    }
    
    func soloSelection() {
        print("[Menu] Solo Selection triggered")
        // TODO: Solo selected segments
    }
    
    func unmuteAll() {
        print("[Menu] Unmute All triggered")
        // TODO: Unmute all segments
    }
    
    func adjustGain() {
        print("[Menu] Adjust Gain triggered")
        // TODO: Show gain adjustment dialog
    }
    
    func normalizeLoudness() {
        print("[Menu] Normalize Loudness triggered")
        // TODO: Normalize loudness
    }
    
    func toggleAudioScrubbing() {
        print("[Menu] Toggle Audio Scrubbing triggered")
        // TODO: Toggle audio scrubbing
    }
    
    func toggleWaveformOnTimeline() {
        print("[Menu] Toggle Waveform on Timeline triggered")
        // TODO: Toggle waveform display on timeline
    }
    
    func detectSilenceSegments() {
        print("[Menu] Detect Silence Segments triggered")
        guard let projectVM = appViewModel?.projectViewModel else { return }
        // TODO: Run silence detection on project
    }
    
    func detectPeaksAndClipping() {
        print("[Menu] Detect Peaks and Clipping triggered")
        guard let projectVM = appViewModel?.projectViewModel else { return }
        // TODO: Detect audio peaks and clipping
    }
    
    func rebuildWaveforms() {
        print("[Menu] Rebuild Waveforms triggered")
        guard let projectVM = appViewModel?.projectViewModel else { return }
        // TODO: Rebuild waveform data
    }
    
    // MARK: - Tools Menu
    
    func runAutoEditOnSequence() {
        print("[Menu] Run Auto Edit on Current Sequence triggered")
        guard let projectVM = appViewModel?.projectViewModel else {
            print("[Menu] No project - cannot run auto edit")
            return
        }
        projectVM.runAutoEdit()
    }
    
    func rebuildAutoEditFromTags() {
        print("[Menu] Rebuild Auto Edit from Tags triggered")
        // TODO: Rebuild auto edit from tags
    }
    
    func analyzeAudioForSilence() {
        print("[Menu] Analyze Audio for Silence triggered")
        detectSilenceSegments()
    }
    
    func analyzeMusicBeats() {
        print("[Menu] Analyze Music Beats triggered")
        guard let projectVM = appViewModel?.projectViewModel else { return }
        // TODO: Analyze music beats
    }
    
    func generateTranscript() {
        print("[Menu] Generate Transcript triggered")
        // TODO: Generate transcript (future feature)
    }
    
    func rebuildMediaCache() {
        print("[Menu] Rebuild Media Cache triggered")
        // TODO: Rebuild media cache
    }
    
    func locateMissingMedia() {
        print("[Menu] Locate Missing Media triggered")
        // TODO: Locate missing media files
    }
    
    func clearTemporaryFiles() {
        print("[Menu] Clear Temporary Files triggered")
        // TODO: Clear temporary files
    }
    
    // MARK: - Window Menu
    
    func showProjectWindow() {
        print("[Menu] Show Project Window triggered")
        // TODO: Show project window
    }
    
    func showLogConsole() {
        print("[Menu] Show Log/Console triggered")
        // TODO: Show log/console window
    }
    
    func showBackgroundTasks() {
        print("[Menu] Show Background Tasks triggered")
        // TODO: Show background tasks window
    }
    
    // MARK: - Help Menu
    
    func showHelp() {
        print("[Menu] Auto Slate Help triggered")
        // TODO: Open help documentation
        if let url = URL(string: "https://autoslate.app/help") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func showKeyboardShortcuts() {
        print("[Menu] Keyboard Shortcuts triggered")
        // TODO: Show keyboard shortcuts window
    }
    
    func showWhatsNew() {
        print("[Menu] What's New in Auto Slate triggered")
        // TODO: Show what's new window
    }
    
    func reportBug() {
        print("[Menu] Report a Bug triggered")
        // TODO: Open bug report form
        if let url = URL(string: "mailto:support@autoslate.app?subject=Bug%20Report") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openLogsFolder() {
        print("[Menu] Open Logs Folder triggered")
        let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Logs")
            .appendingPathComponent("Auto Slate") ?? FileManager.default.temporaryDirectory
        
        NSWorkspace.shared.open(logsURL)
    }
}

