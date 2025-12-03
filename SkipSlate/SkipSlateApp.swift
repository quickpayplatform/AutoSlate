//
//  SkipSlateApp.swift
//  SkipSlate
//
//  Created by Tee Forest on 11/25/25.
//
//  SkipSlate - On-Device Smart Video Editor
//  All processing (auto-edit, audio analysis, color correction) happens
//  entirely on-device using AVFoundation, CoreImage, and CoreAudio.
//  No network calls, no cloud APIs, no external services.
//

import SwiftUI

@main
struct SkipSlateApp: App {
    @StateObject private var appViewModel = AppViewModel()
    
    var body: some Scene {
        let menuActions = MenuActions.shared
        
        return WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            appMenuCommands(menuActions: menuActions)
            fileMenuCommands(menuActions: menuActions)
            editMenuCommands(menuActions: menuActions)
            viewMenuCommands(menuActions: menuActions)
            clipMenuCommands(menuActions: menuActions)
            sequenceMenuCommands(menuActions: menuActions)
            audioMenuCommands(menuActions: menuActions)
            toolsMenuCommands(menuActions: menuActions)
            windowMenuCommands(menuActions: menuActions)
            helpMenuCommands(menuActions: menuActions)
        }
    }
    
    @CommandsBuilder
    private func appMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Auto Slate…") {
                menuActions.showAbout()
            }
        }
        
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Preferences…") {
                menuActions.showPreferences()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
    
    @CommandsBuilder
    private func fileMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                menuActions.newProject()
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                menuActions.openProject()
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button("Close Project") {
                menuActions.closeProject()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
        
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                menuActions.saveProject()
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Save As…") {
                menuActions.saveProjectAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            
            Button("Revert to Saved") {
                menuActions.revertToSaved()
            }
        }
        
        CommandGroup(after: .saveItem) {
            Divider()
            
            Menu("Import") {
                Button("Import Media…") {
                    menuActions.importMedia()
                }
                .keyboardShortcut("i", modifiers: .command)
                
                Button("Import Folder as Project…") {
                    menuActions.importFolderAsProject()
                }
                
                Button("Import From Camera…") {
                    menuActions.importFromCamera()
                }
            }
            
            Menu("Export") {
                Button("Quick Export…") {
                    menuActions.quickExport()
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Button("Export Project…") {
                    menuActions.exportProject()
                }
                
                Button("Export Selected Range…") {
                    menuActions.exportSelectedRange()
                }
            }
            
            Divider()
            
            Button("Project Settings…") {
                menuActions.showProjectSettings()
            }
        }
    }
    
    @CommandsBuilder
    private func editMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandGroup(replacing: .undoRedo) {
            let canUndo = menuActions.appViewModel?.projectViewModel?.canUndo ?? false
            let canRedo = menuActions.appViewModel?.projectViewModel?.canRedo ?? false
            
            Button("Undo") {
                menuActions.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canUndo)
            
            Button("Redo") {
                menuActions.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!canRedo)
        }
        
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                menuActions.cut()
            }
            .keyboardShortcut("x", modifiers: .command)
            
            Button("Copy") {
                menuActions.copy()
            }
            .keyboardShortcut("c", modifiers: .command)
            
            Button("Paste") {
                menuActions.paste()
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Button("Delete") {
                menuActions.delete()
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
        
        CommandGroup(after: .pasteboard) {
            Divider()
            
            Button("Select All") {
                menuActions.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)
            
            Button("Deselect All") {
                menuActions.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        
        CommandGroup(after: .textEditing) {
            Divider()
            
            Button("Split at Playhead") {
                menuActions.splitAtPlayhead()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            
            Button("Ripple Delete") {
                menuActions.rippleDelete()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            
            Divider()
            
            Button("Trim Start to Playhead") {
                menuActions.trimStartToPlayhead()
            }
            
            Button("Trim End to Playhead") {
                menuActions.trimEndToPlayhead()
            }
            
            Button("Clear In/Out Points") {
                menuActions.clearInOutPoints()
            }
        }
    }
    
    @CommandsBuilder
    private func viewMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandMenu("View") {
            Button("Zoom In Timeline") {
                menuActions.zoomInTimeline()
            }
            .keyboardShortcut("=", modifiers: .command)
            
            Button("Zoom Out Timeline") {
                menuActions.zoomOutTimeline()
            }
            .keyboardShortcut("-", modifiers: .command)
            
            Button("Fit Timeline to Window") {
                menuActions.fitTimelineToWindow()
            }
            .keyboardShortcut("0", modifiers: .command)
            
            Divider()
            
            Button("Toggle Waveform Panel") {
                menuActions.toggleWaveformPanel()
            }
            
            Button("Toggle Inspector Panel") {
                menuActions.toggleInspectorPanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            
            Button("Toggle Media Library Panel") {
                menuActions.toggleMediaLibraryPanel()
            }
            
            Button("Toggle Audio Mixer Panel") {
                menuActions.toggleAudioMixerPanel()
            }
            
            Divider()
            
            Button("Show Fullscreen Viewer") {
                menuActions.showFullscreenViewer()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
            
            Button("Exit Fullscreen Viewer") {
                menuActions.exitFullscreenViewer()
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Divider()
            
            Menu("Workspaces") {
                Button("Default Workspace") {
                    menuActions.switchWorkspace(.default)
                }
                
                Button("Clip Room") {
                    menuActions.switchWorkspace(.clipRoom)
                }
                
                Button("Story Room") {
                    menuActions.switchWorkspace(.storyRoom)
                }
                
                Button("Podcast Room") {
                    menuActions.switchWorkspace(.podcastRoom)
                }
            }
        }
    }
    
    @CommandsBuilder
    private func clipMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandMenu("Clip") {
            Button("Enable/Disable Clip") {
                menuActions.enableDisableClip()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Link Audio and Video") {
                menuActions.linkAudioAndVideo()
            }
            
            Button("Unlink Audio and Video") {
                menuActions.unlinkAudioAndVideo()
            }
            
            Button("Detach Audio to New Track") {
                menuActions.detachAudioToNewTrack()
            }
            
            Divider()
            
            Button("Normalize Clip Audio…") {
                menuActions.normalizeClipAudio()
            }
            
            Button("Reset Clip Audio") {
                menuActions.resetClipAudio()
            }
            
            Divider()
            
            Button("Group Clips") {
                menuActions.groupClips()
            }
            .keyboardShortcut("g", modifiers: .command)
            
            Button("Ungroup Clips") {
                menuActions.ungroupClips()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            
            Divider()
            
            Menu("Speed") {
                Button("50%") {
                    menuActions.setClipSpeed(0.5)
                }
                
                Button("100%") {
                    menuActions.setClipSpeed(1.0)
                }
                
                Button("200%") {
                    menuActions.setClipSpeed(2.0)
                }
                
                Divider()
                
                Button("Custom…") {
                    menuActions.setClipSpeed(1.0) // TODO: Show custom speed dialog
                }
            }
        }
    }
    
    @CommandsBuilder
    private func sequenceMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandMenu("Sequence") {
            Button("New Sequence from Selection") {
                menuActions.newSequenceFromSelection()
            }
            
            Button("Sequence Settings…") {
                menuActions.showSequenceSettings()
            }
            
            Divider()
            
            Button("Mark In") {
                menuActions.markIn()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            
            Button("Mark Out") {
                menuActions.markOut()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            
            Button("Clear In/Out") {
                menuActions.clearInOut()
            }
            .keyboardShortcut("x", modifiers: [.command, .option])
            
            Button("Go to In") {
                menuActions.goToIn()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            
            Button("Go to Out") {
                menuActions.goToOut()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Render Preview Cache") {
                menuActions.renderPreviewCache()
            }
            
            Button("Clear Preview Cache") {
                menuActions.clearPreviewCache()
            }
        }
    }
    
    @CommandsBuilder
    private func audioMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandMenu("Audio") {
            Button("Mute Selection") {
                menuActions.muteSelection()
            }
            
            Button("Solo Selection") {
                menuActions.soloSelection()
            }
            
            Button("Unmute All") {
                menuActions.unmuteAll()
            }
            
            Divider()
            
            Button("Adjust Gain…") {
                menuActions.adjustGain()
            }
            
            Button("Normalize Loudness…") {
                menuActions.normalizeLoudness()
            }
            
            Divider()
            
            Button("Toggle Audio Scrubbing") {
                menuActions.toggleAudioScrubbing()
            }
            
            Button("Toggle Waveform on Timeline") {
                menuActions.toggleWaveformOnTimeline()
            }
            
            Divider()
            
            Menu("Audio Analysis") {
                Button("Detect Silence Segments…") {
                    menuActions.detectSilenceSegments()
                }
                
                Button("Detect Peaks and Clipping…") {
                    menuActions.detectPeaksAndClipping()
                }
                
                Button("Rebuild Waveforms") {
                    menuActions.rebuildWaveforms()
                }
            }
        }
    }
    
    @CommandsBuilder
    private func toolsMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandMenu("Tools") {
            Menu("Auto Edit") {
                Button("Run Auto Edit on Current Sequence…") {
                    menuActions.runAutoEditOnSequence()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Button("Rebuild Auto Edit from Tags…") {
                    menuActions.rebuildAutoEditFromTags()
                }
            }
            
            Menu("Analysis") {
                Button("Analyze Audio for Silence…") {
                    menuActions.analyzeAudioForSilence()
                }
                
                Button("Analyze Music Beats…") {
                    menuActions.analyzeMusicBeats()
                }
                
                Button("Generate Transcript") {
                    menuActions.generateTranscript()
                }
            }
            
            Menu("Maintenance") {
                Button("Rebuild Media Cache") {
                    menuActions.rebuildMediaCache()
                }
                
                Button("Locate Missing Media…") {
                    menuActions.locateMissingMedia()
                }
                
                Button("Clear Temporary Files") {
                    menuActions.clearTemporaryFiles()
                }
            }
        }
    }
    
    @CommandsBuilder
    private func windowMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandGroup(replacing: .windowSize) {
            Button("Minimize") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            .keyboardShortcut("m", modifiers: .command)
            
            Button("Zoom") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        
        CommandGroup(after: .windowSize) {
            Divider()
            
            Button("Bring All to Front") {
                NSApp.arrangeInFront(nil)
            }
        }
        
        CommandGroup(after: .windowArrangement) {
            Divider()
            
            Button("Show Project Window") {
                menuActions.showProjectWindow()
            }
            
            Button("Show Log / Console") {
                menuActions.showLogConsole()
            }
            
            Button("Show Background Tasks") {
                menuActions.showBackgroundTasks()
            }
            
            Divider()
            
            Button("Toggle Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
    
    @CommandsBuilder
    private func helpMenuCommands(menuActions: MenuActions) -> some Commands {
        CommandGroup(replacing: .help) {
            Button("Auto Slate Help") {
                menuActions.showHelp()
            }
            .keyboardShortcut("?", modifiers: .command)
            
            Button("Keyboard Shortcuts") {
                menuActions.showKeyboardShortcuts()
            }
            
            Button("What's New in Auto Slate") {
                menuActions.showWhatsNew()
            }
            
            Divider()
            
            Button("Report a Bug…") {
                menuActions.reportBug()
            }
            
            Button("Open Logs Folder") {
                menuActions.openLogsFolder()
            }
        }
    }
}
