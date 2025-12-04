//
//  InspectorPanel.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct InspectorPanel: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom styled tab selector - matches app color palette
            HStack(spacing: 8) {
                // Info Tab
                InspectorTabButton(
                    title: "Info",
                    isSelected: selectedTab == 0,
                    accentColor: AppColors.tealAccent
                ) {
                    // CRASH-PROOF: Safe tab selection
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 0
                    }
                }
                
                // Effects Tab
                InspectorTabButton(
                    title: "Effects",
                    isSelected: selectedTab == 1,
                    accentColor: AppColors.orangeAccent
                ) {
                    // CRASH-PROOF: Safe tab selection
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 1
                    }
                }
                
                // Media Tab
                InspectorTabButton(
                    title: "Media",
                    isSelected: selectedTab == 2,
                    accentColor: AppColors.tealAccent
                ) {
                    // CRASH-PROOF: Safe tab selection
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 2
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.panelBackground)
            
            // Divider with accent color hint
            Rectangle()
                .fill(selectedTab == 1 ? AppColors.orangeAccent.opacity(0.3) : AppColors.tealAccent.opacity(0.3))
                .frame(height: 2)
            
            // Tab content
            ScrollView {
                Group {
                    // CRASH-PROOF: Safe tab content switching
                    if selectedTab == 0 {
                        InfoInspector(projectViewModel: projectViewModel)
                    } else if selectedTab == 1 {
                        EffectsInspector(projectViewModel: projectViewModel)
                    } else if selectedTab == 2 {
                        MediaInspector(projectViewModel: projectViewModel)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(AppColors.panelBackground)
        }
        .background(AppColors.panelBackground)
    }
}

// MARK: - Custom Inspector Tab Button

struct InspectorTabButton: View {
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minWidth: 60)
                .background(
                    Group {
                        if isSelected {
                            accentColor
                        } else {
                            Color.clear
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.clear : accentColor.opacity(0.4),
                            lineWidth: 1.5
                        )
                )
                .cornerRadius(6)
                .shadow(
                    color: isSelected ? accentColor.opacity(0.25) : .clear,
                    radius: 3,
                    x: 0,
                    y: 1
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Inspector

struct InfoInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // CRITICAL: Check both selectedSegment and selectedSegmentIDs to determine if segment is selected
            // If selectedSegmentIDs has IDs, use the first one to get the segment
            let effectiveSelectedSegment: Segment? = {
                if let seg = projectViewModel.selectedSegment {
                    return seg
                } else if let firstID = projectViewModel.selectedSegmentIDs.first,
                          let seg = projectViewModel.segments.first(where: { $0.id == firstID }) {
                    // Sync selectedSegment from selectedSegmentIDs
                    DispatchQueue.main.async {
                        projectViewModel.selectedSegment = seg
                    }
                    return seg
                }
                return nil
            }()
            
            if let selectedSegment = effectiveSelectedSegment,
               let clipID = selectedSegment.clipID,
               let clip = projectViewModel.clips.first(where: { $0.id == clipID }) {
                // Selected Segment Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Segment")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    InfoRow(label: "Clip Name", value: clip.fileName)
                    InfoRow(label: "Duration", value: String(format: "%.2f s", selectedSegment.duration))
                    InfoRow(label: "Source Range", value: String(format: "%.2f - %.2f s", selectedSegment.sourceStart, selectedSegment.sourceEnd))
                    InfoRow(label: "Type", value: clipTypeString(clip.type))
                    
                    if clip.type == .videoWithAudio || clip.type == .videoOnly {
                        // Video-specific info could go here
                    }
                }
                
                Rectangle()
                    .fill(AppColors.panelBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 8)
            } else {
                // No selection
                VStack(spacing: 12) {
                    Text("No segment selected")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.subheadline)
                    
                    Text("Click a segment in the timeline to view its properties")
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            // Project Info
            VStack(alignment: .leading, spacing: 12) {
                Text("Project Info")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                InfoRow(label: "Type", value: projectViewModel.type.displayName)
                InfoRow(label: "Aspect Ratio", value: projectViewModel.aspectRatio.displayName)
                InfoRow(label: "Resolution", value: "\(projectViewModel.resolution.width)×\(projectViewModel.resolution.height)")
                InfoRow(label: "Clips", value: "\(projectViewModel.clips.count)")
                InfoRow(label: "Segments", value: "\(projectViewModel.segments.count)")
            }
        }
    }
    
    private func clipTypeString(_ type: MediaClipType) -> String {
        switch type {
        case .videoWithAudio: return "Video+Audio"
        case .videoOnly: return "Video"
        case .audioOnly: return "Audio"
        case .image: return "Image"
        }
    }
}

// MARK: - Effects Inspector

struct EffectsInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Show transform controls if segments are selected
            let hasSelection = !projectViewModel.selectedSegmentIDs.isEmpty || projectViewModel.selectedSegment != nil
            let selectedSegment = projectViewModel.selectedSegment ?? projectViewModel.segments.first(where: { projectViewModel.selectedSegmentIDs.contains($0.id) })
            
            if hasSelection, let selectedSegment = selectedSegment {
                // Transition Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transition")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Picker("", selection: Binding(
                        get: { selectedSegment.effects.transitionType },
                        set: { newValue in
                            updateSegmentEffects { effects in
                                effects.transitionType = newValue
                            }
                        }
                    )) {
                        Text("None").tag(SegmentTransitionType.none)
                        Text("Crossfade").tag(SegmentTransitionType.crossfade)
                        Text("Dip to Black").tag(SegmentTransitionType.dipToBlack)
                        Text("Dip to White").tag(SegmentTransitionType.dipToWhite)
                    }
                    .pickerStyle(.menu)
                    
                    if selectedSegment.effects.transitionType != .none {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duration: \(String(format: "%.2f", selectedSegment.effects.transitionDuration))s")
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Slider(
                                value: Binding(
                                    get: { selectedSegment.effects.transitionDuration },
                                    set: { newValue in
                                        updateSegmentEffects { effects in
                                            effects.transitionDuration = newValue
                                        }
                                    }
                                ),
                                in: 0.0...2.0
                            )
                            .tint(AppColors.orangeAccent)
                        }
                    }
                }
                
                Rectangle()
                    .fill(AppColors.panelBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                
                // Transform Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transform")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    // Scale to Fill Frame button
                    Button(action: {
                        projectViewModel.scaleSelectedSegmentsToFillFrame()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("Scale to Fill Frame")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedSegment.transform.scaleToFillFrame 
                                ? AppColors.tealAccent 
                                : AppColors.tealAccent.opacity(0.3)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Scale and crop selected segments to fully cover the project frame")
                    
                    // Show status if scale to fill is active
                    if selectedSegment.transform.scaleToFillFrame {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.tealAccent)
                            Text("Scale to Fill Frame is active")
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Scale
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scale")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.2f", selectedSegment.effects.scale))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.scale },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.scale = newValue
                                    }
                                    projectViewModel.debugLogSelectedSegment("Scale slider changed")
                                }
                            ),
                            in: 0.5...3.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    // Position X
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Position X")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.1f", selectedSegment.effects.positionX))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.positionX },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.positionX = newValue
                                    }
                                    projectViewModel.debugLogSelectedSegment("Position X slider changed")
                                }
                            ),
                            in: -100.0...100.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    // Position Y
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Position Y")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.1f", selectedSegment.effects.positionY))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.positionY },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.positionY = newValue
                                    }
                                    projectViewModel.debugLogSelectedSegment("Position Y slider changed")
                                }
                            ),
                            in: -100.0...100.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    // Rotation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rotation")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.1f°", selectedSegment.effects.rotation))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.rotation },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.rotation = newValue
                                    }
                                    projectViewModel.debugLogSelectedSegment("Rotation slider changed")
                                }
                            ),
                            in: -180.0...180.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    Button("Reset Transform") {
                        // Reset all transform properties: effects and scaleToFillFrame
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
                        
                        print("SkipSlate: ✅ Reset Transform - all transform properties reset to defaults")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.orangeAccent.opacity(0.8))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.orangeAccent, lineWidth: 1)
                    )
                }
                
                Rectangle()
                    .fill(AppColors.panelBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                
                // Crop Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crop")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    // Preset buttons - styled to match app palette
                    HStack(spacing: 8) {
                        CropPresetButton(title: "16:9") {
                            // Set crop for 16:9 (placeholder)
                        }
                        CropPresetButton(title: "9:16") {
                            // Set crop for 9:16 (placeholder)
                        }
                        CropPresetButton(title: "1:1") {
                            // Set crop for 1:1 (placeholder)
                        }
                        CropPresetButton(title: "Custom") {
                            // Enable custom crop (placeholder)
                        }
                    }
                    
                    // Crop amount slider (simplified)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crop Amount")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.0f%%", (selectedSegment.effects.cropTop + selectedSegment.effects.cropBottom + selectedSegment.effects.cropLeft + selectedSegment.effects.cropRight) / 4.0 * 100))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { (selectedSegment.effects.cropTop + selectedSegment.effects.cropBottom + selectedSegment.effects.cropLeft + selectedSegment.effects.cropRight) / 4.0 },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.cropTop = newValue
                                        effects.cropBottom = newValue
                                        effects.cropLeft = newValue
                                        effects.cropRight = newValue
                                    }
                                }
                            ),
                            in: 0.0...0.5
                        )
                        .tint(AppColors.orangeAccent)
                    }
                }
                
                Rectangle()
                    .fill(AppColors.panelBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                
                // Composition Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Composition")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    // Mode - Styled button grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mode")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(spacing: 8) {
                            CompositionModeButton(
                                title: "Fit",
                                icon: "arrow.down.right.and.arrow.up.left",
                                isSelected: selectedSegment.effects.compositionMode == .fit,
                                color: AppColors.tealAccent
                            ) {
                                updateSegmentEffects { effects in
                                    effects.compositionMode = .fit
                                }
                            }
                            
                            CompositionModeButton(
                                title: "Fill",
                                icon: "arrow.up.left.and.arrow.down.right",
                                isSelected: selectedSegment.effects.compositionMode == .fill,
                                color: AppColors.orangeAccent
                            ) {
                                updateSegmentEffects { effects in
                                    effects.compositionMode = .fill
                                }
                            }
                            
                            CompositionModeButton(
                                title: "Letterbox",
                                icon: "rectangle.split.3x1",
                                isSelected: selectedSegment.effects.compositionMode == .fitWithLetterbox,
                                color: AppColors.tealAccent
                            ) {
                                updateSegmentEffects { effects in
                                    effects.compositionMode = .fitWithLetterbox
                                }
                            }
                        }
                    }
                    
                    // Anchor - 3x3 grid style
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Anchor Position")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        // 3x3 Anchor Grid
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                AnchorButton(anchor: .topLeft, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .topLeft }
                                }
                                AnchorButton(anchor: .top, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .top }
                                }
                                AnchorButton(anchor: .topRight, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .topRight }
                                }
                            }
                            HStack(spacing: 4) {
                                AnchorButton(anchor: .left, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .left }
                                }
                                AnchorButton(anchor: .center, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .center }
                                }
                                AnchorButton(anchor: .right, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .right }
                                }
                            }
                            HStack(spacing: 4) {
                                AnchorButton(anchor: .bottomLeft, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .bottomLeft }
                                }
                                AnchorButton(anchor: .bottom, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .bottom }
                                }
                                AnchorButton(anchor: .bottomRight, selected: selectedSegment.effects.compositionAnchor) {
                                    updateSegmentEffects { effects in effects.compositionAnchor = .bottomRight }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                
                Rectangle()
                    .fill(AppColors.panelBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.vertical, 8)
                
                // Audio Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    // Volume
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(AppColors.tealAccent)
                                .font(.system(size: 12))
                            Text("Volume")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.0f%%", selectedSegment.effects.audioVolume * 100))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.audioVolume },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.audioVolume = newValue
                                    }
                                }
                            ),
                            in: 0.0...2.0
                        )
                        .tint(AppColors.tealAccent)
                    }
                    
                    // Fade In
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(AppColors.orangeAccent)
                                .font(.system(size: 12))
                            Text("Fade In")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.1fs", selectedSegment.effects.audioFadeInDuration))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.audioFadeInDuration },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.audioFadeInDuration = newValue
                                    }
                                }
                            ),
                            in: 0.0...5.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    // Fade Out
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(AppColors.orangeAccent)
                                .font(.system(size: 12))
                                .scaleEffect(x: -1, y: 1)
                            Text("Fade Out")
                                .font(.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Text(String(format: "%.1fs", selectedSegment.effects.audioFadeOutDuration))
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 50)
                        }
                        Slider(
                            value: Binding(
                                get: { selectedSegment.effects.audioFadeOutDuration },
                                set: { newValue in
                                    updateSegmentEffects { effects in
                                        effects.audioFadeOutDuration = newValue
                                    }
                                }
                            ),
                            in: 0.0...5.0
                        )
                        .tint(AppColors.orangeAccent)
                    }
                    
                    // Mute button
                    Button(action: {
                        updateSegmentEffects { effects in
                            effects.audioVolume = effects.audioVolume > 0 ? 0.0 : 1.0
                        }
                    }) {
                        HStack {
                            Image(systemName: selectedSegment.effects.audioVolume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            Text(selectedSegment.effects.audioVolume > 0 ? "Mute" : "Unmute")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(selectedSegment.effects.audioVolume > 0 ? AppColors.tealAccent.opacity(0.6) : AppColors.orangeAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // No selection
                VStack(spacing: 12) {
                    Text("No segment selected")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.subheadline)
                    
                    Text("Select a segment in the timeline to apply effects")
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }
    
    private func updateSegmentEffects(_ update: (inout SegmentEffects) -> Void) {
        guard var segment = projectViewModel.selectedSegment else {
            print("SkipSlate: [Transform DEBUG] No selected segment to update effects")
            return
        }
        
        // STEP 2.1: Debug logging before and after UI update
        print("SkipSlate: [Transform DEBUG] Before UI update – segment id=\(segment.id), effects: scale=\(segment.effects.scale), pos=(\(segment.effects.positionX), \(segment.effects.positionY)), rot=\(segment.effects.rotation), scaleToFill=\(segment.transform.scaleToFillFrame)")
        
        update(&segment.effects)
        
        print("SkipSlate: [Transform DEBUG] After UI update – segment id=\(segment.id), effects: scale=\(segment.effects.scale), pos=(\(segment.effects.positionX), \(segment.effects.positionY)), rot=\(segment.effects.rotation), scaleToFill=\(segment.transform.scaleToFillFrame)")
        
        // CRITICAL: Use immediate rebuild for transform effects to enable real-time preview
        // Transform effects (scale, position, rotation) need immediate visual feedback
        projectViewModel.updateSegmentImmediate(segment)
    }
}

// MARK: - Helper Views

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(AppColors.secondaryText)
                .font(.caption)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.primaryText)
                .font(.caption)
        }
    }
}

// MARK: - Legacy Inspector Components (for DaVinciStyleLayout)

struct MediaClipRow: View {
    let clip: MediaClip
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(AppColors.podcastColor)
                .frame(width: 24)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.fileName)
                    .font(.caption)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text("\(String(format: "%.1f", clip.duration))s • \(typeString)")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                    
                    // Audio indicator
                    if clip.hasAudioTrack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .help("This clip has an audio track")
                    } else {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .help("This clip has no audio track")
                    }
                }
            }
            
            Spacer()
        }
        .padding(10)
        .background(AppColors.cardBase)
        .cornerRadius(8)
    }
    
    private var iconName: String {
        switch clip.type {
        case .videoWithAudio, .videoOnly:
            return "video.fill"
        case .audioOnly:
            return "waveform"
        case .image:
            return "photo.fill"
        }
    }
    
    private var typeString: String {
        switch clip.type {
        case .videoWithAudio:
            return "Video+Audio"
        case .videoOnly:
            return "Video"
        case .audioOnly:
            return "Audio"
        case .image:
            return "Image"
        }
    }
}

struct AudioInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Audio Settings")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)
            
            // Noise reduction toggle
            Toggle("Clean noise", isOn: Binding(
                get: { projectViewModel.audioSettings.enableNoiseReduction },
                set: { 
                    var settings = projectViewModel.audioSettings
                    settings.enableNoiseReduction = $0
                    projectViewModel.updateAudioSettings(settings)
                }
            ))
            .foregroundColor(.white)
            
            // Compression toggle
            Toggle("Smooth dynamics", isOn: Binding(
                get: { projectViewModel.audioSettings.enableCompression },
                set: { 
                    var settings = projectViewModel.audioSettings
                    settings.enableCompression = $0
                    projectViewModel.updateAudioSettings(settings)
                }
            ))
            .foregroundColor(.white)
            
            // Master gain
            VStack(alignment: .leading, spacing: 8) {
                Text("Master Volume")
                    .foregroundColor(AppColors.primaryText)
                    .font(.caption)
                
                HStack {
                    Slider(
                        value: Binding(
                            get: { projectViewModel.audioSettings.masterGainDB },
                            set: { 
                                var settings = projectViewModel.audioSettings
                                settings.masterGainDB = $0
                                projectViewModel.updateAudioSettings(settings)
                            }
                        ),
                        in: -12.0...12.0
                    )
                    .tint(AppColors.orangeAccent)
                    
                    Text(String(format: "%.1f dB", projectViewModel.audioSettings.masterGainDB))
                        .foregroundColor(AppColors.secondaryText)
                        .font(.caption)
                        .frame(width: 50)
                }
            }
        }
    }
}

// MARK: - Crop Preset Button

struct CropPresetButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.panelBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppColors.tealAccent.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Inspector

struct ColorInspector: View {
    @ObservedObject var projectViewModel: ProjectViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Color Settings")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)
            
            // Color wheels in a grid
            HStack(spacing: 20) {
                // Exposure dial
                ColorDial(
                    label: "Exposure",
                    value: Binding(
                        get: { projectViewModel.colorSettings.exposure },
                        set: { 
                            var settings = projectViewModel.colorSettings
                            settings.exposure = $0
                            projectViewModel.colorSettings = settings
                        }
                    ),
                    range: -2.0...2.0,
                    format: { String(format: "%.1f", $0) + " EV" },
                    color: AppColors.tealAccent
                )
                
                // Contrast dial
                ColorDial(
                    label: "Contrast",
                    value: Binding(
                        get: { projectViewModel.colorSettings.contrast },
                        set: { 
                            var settings = projectViewModel.colorSettings
                            settings.contrast = $0
                            projectViewModel.colorSettings = settings
                        }
                    ),
                    range: 0.5...1.5,
                    format: { String(format: "%.2f", $0) },
                    color: AppColors.orangeAccent
                )
                
                // Saturation dial
                ColorDial(
                    label: "Saturation",
                    value: Binding(
                        get: { projectViewModel.colorSettings.saturation },
                        set: { 
                            var settings = projectViewModel.colorSettings
                            settings.saturation = $0
                            projectViewModel.colorSettings = settings
                        }
                    ),
                    range: 0.0...2.0,
                    format: { String(format: "%.2f", $0) },
                    color: Color.pink
                )
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .padding(.vertical, 8)
            
            // Color wheel for color grading
            ColorWheel(
                hue: Binding(
                    get: { projectViewModel.colorSettings.colorHue },
                    set: { 
                        var settings = projectViewModel.colorSettings
                        settings.colorHue = $0
                        projectViewModel.colorSettings = settings
                    }
                ),
                saturation: Binding(
                    get: { projectViewModel.colorSettings.colorSaturation },
                    set: { 
                        var settings = projectViewModel.colorSettings
                        settings.colorSaturation = $0
                        projectViewModel.colorSettings = settings
                    }
                )
            )
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Composition Mode Button

struct CompositionModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : color.opacity(0.4), lineWidth: isSelected ? 0 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Anchor Button (3x3 Grid)

struct AnchorButton: View {
    let anchor: CompositionAnchor
    let selected: CompositionAnchor
    let action: () -> Void
    
    private var isSelected: Bool { anchor == selected }
    
    private var iconName: String {
        switch anchor {
        case .topLeft: return "arrow.up.left"
        case .top: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .left: return "arrow.left"
        case .center: return "circle.fill"
        case .right: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottom: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: isSelected ? 14 : 12, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppColors.orangeAccent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : AppColors.tealAccent.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
