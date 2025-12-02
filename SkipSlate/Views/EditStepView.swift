//
//  EditStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/26/25.
//

import SwiftUI

enum EditingTool: String, CaseIterable {
    case select = "Select"
    case cut = "Cut"
    case trim = "Trim"
    
    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .cut: return "scissors"
        case .trim: return "slider.horizontal.3"
        }
    }
    
    var cursor: NSCursor {
        switch self {
        case .select: return .arrow
        case .cut: return NSCursor(image: NSImage(systemSymbolName: "scissors", accessibilityDescription: nil) ?? NSImage(), hotSpot: NSPoint(x: 8, y: 8))
        case .trim: return .resizeLeftRight
        }
    }
}

struct EditStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    // CRITICAL: Directly observe PlayerViewModel for playback state
    @ObservedObject private var playerViewModel: PlayerViewModel
    @State private var selectedTool: EditingTool = .select
    
    init(appViewModel: AppViewModel, projectViewModel: ProjectViewModel) {
        self.appViewModel = appViewModel
        self.projectViewModel = projectViewModel
        self._playerViewModel = ObservedObject(wrappedValue: projectViewModel.playerVM)
    }
    
    var body: some View {
        DaVinciStyleLayout(
            appViewModel: appViewModel,
            projectViewModel: projectViewModel,
            selectedTool: selectedTool
        ) {
            // Central viewer area - video preview for timeline editing
            VStack(spacing: 0) {
                // Toolbar with action buttons (no tools selector)
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Rerun Auto-Edit button - appears when user has modified the timeline
                    if !projectViewModel.segments.isEmpty && projectViewModel.hasUserModifiedAutoEdit {
                        VStack(spacing: 4) {
                            Button(action: {
                                projectViewModel.rerunAutoEdit()
                            }) {
                                HStack(spacing: 4) {
                                    if projectViewModel.isAutoEditing {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Rerun Auto-Edit")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(projectViewModel.isAutoEditing ? AppColors.panelBackground : AppColors.orangeAccent)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .disabled(projectViewModel.isAutoEditing)
                            
                            // Show status/error messages
                            if let error = projectViewModel.autoEditError {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 200)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !projectViewModel.autoEditStatus.isEmpty && projectViewModel.isAutoEditing {
                                Text(projectViewModel.autoEditStatus)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 200)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    
                    // Delete button for selected segment
                    if let selectedSegment = projectViewModel.selectedSegment {
                        Button(action: {
                            projectViewModel.deleteSegment(selectedSegment)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.panelBackground)
                
                Divider()
                
                PreviewPanel(projectViewModel: projectViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            handleLeftArrow()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleRightArrow()
            return .handled
        }
        .onKeyPress(.delete) {
            handleDelete()
            return .handled
        }
        .onKeyPress(.space) {
            // Spacebar to toggle play/pause
            // CRITICAL: Use directly observed playerViewModel, not indirect access
            if playerViewModel.isPlaying {
                playerViewModel.pause()
            } else {
                playerViewModel.play()
            }
            return .handled
        }
        .onAppear {
            // Set initial cursor
            selectedTool.cursor.push()
        }
    }
    
    private func handleLeftArrow() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        guard let currentIndex = projectViewModel.segments.firstIndex(where: { $0.id == selectedSegment.id }) else { return }
        
        if currentIndex > 0 {
            let prevSegment = projectViewModel.segments[currentIndex - 1]
            projectViewModel.selectedSegment = prevSegment
            projectViewModel.seekToSegment(prevSegment)
        }
    }
    
    private func handleRightArrow() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        guard let currentIndex = projectViewModel.segments.firstIndex(where: { $0.id == selectedSegment.id }) else { return }
        
        if currentIndex < projectViewModel.segments.count - 1 {
            let nextSegment = projectViewModel.segments[currentIndex + 1]
            projectViewModel.selectedSegment = nextSegment
            projectViewModel.seekToSegment(nextSegment)
        }
    }
    
    private func handleDelete() {
        guard let selectedSegment = projectViewModel.selectedSegment else { return }
        projectViewModel.deleteSegment(selectedSegment)
    }
    
    private func handleCutAtPlayhead() {
        guard selectedTool == .cut else { return }
        // CRITICAL: Use directly observed playerViewModel, not indirect access
        let playheadTime = playerViewModel.currentTime
        
        // Find the segment that contains the playhead
        var accumulatedTime: Double = 0
        for segment in projectViewModel.segments where segment.enabled {
            if playheadTime >= accumulatedTime && playheadTime < accumulatedTime + segment.duration {
                // Split this segment at the playhead
                let relativeTime = playheadTime - accumulatedTime
                let splitTime = segment.sourceStart + relativeTime
                projectViewModel.splitSegment(segment, at: splitTime)
                return
            }
            accumulatedTime += segment.duration
        }
    }
}

