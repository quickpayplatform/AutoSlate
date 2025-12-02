//
//  DaVinciStyleLayout.swift
//  SkipSlate
//
//  Created by Cursor on 11/26/25.
//

import SwiftUI

/// Main layout that mirrors DaVinci Resolve's interface structure
struct DaVinciStyleLayout<Content: View>: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    let content: Content
    var selectedTool: EditingTool = .select // Optional tool selection for edit step
    
    @State private var rightSidebarWidth: CGFloat = 350
    @State private var timelineHeight: CGFloat = 400 // Default to half screen (will be calculated from geometry)
    @State private var isRightSidebarVisible: Bool = true
    @State private var isResizingLeft: Bool = false
    @State private var isResizingRight: Bool = false
    @State private var isResizingTimeline: Bool = false
    
    init(
        appViewModel: AppViewModel,
        projectViewModel: ProjectViewModel,
        selectedTool: EditingTool = .select,
        @ViewBuilder content: () -> Content
    ) {
        self.appViewModel = appViewModel
        self.projectViewModel = projectViewModel
        self.selectedTool = selectedTool
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { mainGeometry in
            VStack(spacing: 0) {
                // Top bar with tabs (like DaVinci's page tabs)
                topTabBar
                
                Divider()
                    .background(Color(white: 0.15))
                
                // Main content area with resizable panels
                HStack(spacing: 0) {
                    // Central viewer/content area (no left sidebar/toolbox)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                
                    // Right sidebar (inspector)
                    if isRightSidebarVisible {
                        // Resizable divider
                        ResizableDivider(
                            isResizing: $isResizingRight,
                            onResize: { delta in
                                rightSidebarWidth = max(200, min(600, rightSidebarWidth + delta))
                            }
                        )
                        
                        rightSidebar
                            .frame(width: rightSidebarWidth)
                            .background(Color(white: 0.12))
                    }
                }
                .frame(height: max(400, mainGeometry.size.height - timelineHeight))
                
                // Resizable divider for timeline
                ResizableDivider(
                    isResizing: $isResizingTimeline,
                    isHorizontal: true,
                    onResize: { delta in
                        // Allow resizing smaller, but default is half screen
                        let minHeight: CGFloat = 150
                        let maxHeight = mainGeometry.size.height * 0.8
                        timelineHeight = max(minHeight, min(maxHeight, timelineHeight - delta))
                    }
                )
                
                // Bottom timeline - always visible
                timelinePanel
                    .frame(height: timelineHeight)
                    .background(Color(white: 0.10))
            }
            .onAppear {
                // Set default timeline height to half screen on first appearance
                if timelineHeight == 400 { // Only if not already set by user
                    timelineHeight = mainGeometry.size.height * 0.5
                }
            }
        }
        .background(Color(white: 0.08))
    }
    
    // MARK: - Top Tab Bar
    
    private var topTabBar: some View {
        HStack(spacing: 0) {
            // App Logo (top-left corner)
            HStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .compositingGroup()
                    .padding(.leading, 12)
                
                // Project name
                Text(projectViewModel.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Text("|")
                    .foregroundColor(Color(white: 0.4))
                
                Text("Timeline 1")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.6))
            }
            .padding(.horizontal, 16)
            
            Divider()
                .frame(height: 20)
                .background(Color(white: 0.2))
            
            // Page tabs (like DaVinci)
            // After auto-edit completes (segments exist), only show forward tabs: Color, Audio, Edit, Export
            // Before auto-edit, show all tabs including Media and Auto Edit
            HStack(spacing: 0) {
                let availableTabs: [WizardStep] = {
                    // If segments exist (auto-edit completed), only show forward tabs
                    if !projectViewModel.segments.isEmpty {
                        return [.color, .audio, .edit, .export]
                    } else {
                        // Before auto-edit, show all tabs
                        return [.media, .autoEdit, .color, .audio, .edit, .export]
                    }
                }()
                
                ForEach(availableTabs, id: \.rawValue) { step in
                    WizardTabButton(
                        step: step,
                        isActive: appViewModel.currentStep == step,
                        action: {
                            // Only allow navigation if project exists and prerequisites are met
                            if canNavigateToStep(step) {
                                appViewModel.goToStep(step)
                            }
                        }
                    )
                }
            }
            
            Spacer()
            
            // Playback controls and timecode
            HStack(spacing: 16) {
                // Timecode display - use helper view to properly observe PlayerViewModel
                TimecodeDisplay(playerViewModel: projectViewModel.playerVM)
                
                // Playback controls
                Button(action: {
                    projectViewModel.playerVM.seek(to: 0)
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                
                Button(action: {
                    if projectViewModel.playerVM.isPlaying {
                        projectViewModel.playerVM.pause()
                    } else {
                        projectViewModel.playerVM.play()
                    }
                }) {
                    Image(systemName: projectViewModel.playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                
                Button(action: {
                    projectViewModel.playerVM.seek(to: projectViewModel.playerVM.duration)
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 40)
        .background(Color(white: 0.10))
    }
    
    
}

// Helper view to properly observe PlayerViewModel for timecode updates
struct TimecodeDisplay: View {
    @ObservedObject var playerViewModel: PlayerViewModel
    
    var body: some View {
        Text(timecodeString)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 100)
    }
    
    private var timecodeString: String {
        let time = playerViewModel.currentTime
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
    }
    
extension DaVinciStyleLayout {
    private func canNavigateToStep(_ step: WizardStep) -> Bool {
        // CRITICAL: Once segments exist (auto-edit completed), prevent going back to Media or AutoEdit
        let hasSegments = !projectViewModel.segments.isEmpty
        
        if hasSegments {
            // After auto-edit: Only allow forward navigation (Color, Audio, Edit, Export)
            // Block Media and AutoEdit to prevent restarting
            if step == .media || step == .autoEdit {
                return false
            }
            // Forward steps require segments (already have them)
            return [.color, .audio, .edit, .export].contains(step)
        } else {
            // Before auto-edit: Allow Media and AutoEdit
            if step == .media { return true }
            if step == .autoEdit { return !projectViewModel.clips.isEmpty }
            // Forward steps require segments (don't have them yet)
            if [.color, .audio, .edit, .export].contains(step) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Left Sidebar (Toolbox) - REMOVED
    // Toolbox has been removed per user request
    
    // MARK: - Right Sidebar (Inspector)
    
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inspector header
            HStack {
                Text(inspectorTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { isRightSidebarVisible.toggle() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(white: 0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.08))
            
            Divider()
                .background(Color(white: 0.15))
            
            // Inspector content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inspectorContent
                }
                .padding(12)
            }
        }
    }
    
    private var inspectorTitle: String {
        switch appViewModel.currentStep {
        case .media: return "Media"
        case .autoEdit: return "Auto Edit Settings"
        case .color: return "Color"
        case .audio: return "Audio"
        case .edit: return "Inspector"
        case .export: return "Export"
        default: return "Inspector"
        }
    }
    
    @ViewBuilder
    private var inspectorContent: some View {
        // After auto-edit (segments exist), only show forward inspectors
        let hasSegments = !projectViewModel.segments.isEmpty
        
        switch appViewModel.currentStep {
        case .media:
            if !hasSegments {
                // Use existing MediaInspector from InspectorPanel
                VStack(alignment: .leading, spacing: 16) {
                    Text("Media Library")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    
                    if projectViewModel.clips.isEmpty {
                        VStack(spacing: 8) {
                            Text("No media imported")
                                .foregroundColor(Color(white: 0.6))
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(projectViewModel.clips) { clip in
                            MediaClipRow(clip: clip, projectViewModel: projectViewModel)
                        }
                    }
                }
            } else {
                // Hide Media inspector after auto-edit
                EmptyView()
            }
        case .autoEdit:
            if !hasSegments {
                AutoEditInspector(projectViewModel: projectViewModel)
            } else {
                // Hide AutoEdit inspector after auto-edit
                EmptyView()
            }
        case .color:
            // Dedicated color grading inspector
            ColorInspector(projectViewModel: projectViewModel)
        case .audio:
            // Dedicated audio editing inspector
            AudioInspector(projectViewModel: projectViewModel)
        case .edit:
            // Full inspector panel with tabs
            InspectorPanel(projectViewModel: projectViewModel)
        case .export:
            ExportInspector(projectViewModel: projectViewModel)
        default:
            EmptyView()
        }
    }
    
    // MARK: - Timeline Panel
    
    private var timelinePanel: some View {
        VStack(spacing: 0) {
            // Timeline header
            HStack {
                Text("Timeline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))
            
            Divider()
                .background(Color(white: 0.15))
            
            // Timeline content - using clean minimal timeline
            TimelineView(projectViewModel: projectViewModel)
        }
    }
}

// MARK: - Tab Button

private struct WizardTabButton: View {
    let step: WizardStep
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: step.iconName)
                    .font(.system(size: 11))
                Text(step.label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            .foregroundColor(isActive ? .white : Color(white: 0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isActive ? Color(white: 0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toolbox Components - REMOVED
// Toolbox has been removed per user request

// MARK: - Inspector Components

struct AutoEditInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto Edit Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 8)
            
            Text("Configure auto-edit preferences")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.6))
        }
    }
}

struct ExportInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 8)
            
            Text("Configure export options")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.6))
        }
    }
}

// MARK: - Resizable Divider

struct ResizableDivider: View {
    @Binding var isResizing: Bool
    var isHorizontal: Bool = false
    var onResize: (CGFloat) -> Void
    
    @State private var dragStart: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Divider line
            if isHorizontal {
                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(height: 2)
            } else {
                Rectangle()
                    .fill(Color(white: 0.15))
                    .frame(width: 2)
            }
            
            // Drag handle area
            if isHorizontal {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    dragStart = value.startLocation.y
                                }
                                let delta = value.translation.height
                                onResize(delta)
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isResizing {
                                    isResizing = true
                                    dragStart = value.startLocation.x
                                }
                                let delta = value.translation.width
                                onResize(delta)
                            }
                            .onEnded { _ in
                                isResizing = false
                            }
                    )
            }
        }
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

