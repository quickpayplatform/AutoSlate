//
//  ExportStepView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//
//  MODULE: Export UI
//  - Export UI that calls ExportService
//  - Reads Project data from ProjectViewModel
//  - Does NOT depend on PlayerViewModel or preview
//  - Communication: ExportStepView → ExportService.export(project:) → file output
//

import SwiftUI
import AppKit

struct ExportStepView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var projectViewModel: ProjectViewModel
    
    @State private var exportFormat: ExportFormat = .mp4
    @State private var selectedResolution: ResolutionPreset?
    @State private var quality: ExportQuality = .balanced
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0.0
    @State private var showSuccess: Bool = false
    @State private var exportedURL: URL?
    @State private var exportError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // App Logo in top-left
            HStack {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .compositingGroup()
                    .padding(.leading, 20)
                    .padding(.top, 12)
                
                Spacer()
            }
            
            // Step indicator
            GlobalStepIndicator(currentStep: .export)
            
            Divider()
                .background(AutoEditTheme.hairlineDivider)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export your video")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(AutoEditTheme.primaryText)
                        
                        Text("Choose format, resolution, and quality for your final file.")
                            .font(.system(size: 14))
                            .foregroundColor(AutoEditTheme.secondaryText)
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 40)
                    
                    // Export settings sections
                    VStack(alignment: .leading, spacing: 20) {
                        // Format
                        formatSection
                        
                        // Resolution
                        resolutionSection
                        
                        // Quality
                        qualitySection
                        
                        // Summary
                        summarySection
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .background(AutoEditTheme.bg)
            
            Divider()
                .background(AutoEditTheme.hairlineDivider)
            
            // Navigation
            HStack {
                Button("Back") {
                    appViewModel.previousStep()
                }
                .buttonStyle(BackButtonStyle())
                .disabled(isExporting)
                
                Spacer()
                
                HStack(spacing: 12) {
                    if isExporting {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.tealCircular)
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                Text("Exporting... \(Int(exportProgress * 100))%")
                                    .font(.system(size: 12))
                                    .foregroundColor(AutoEditTheme.secondaryText)
                            }
                        }
                    }
                    
                    if let error = exportError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .padding(.trailing, 8)
                    }
                    
                    if showSuccess {
                        Button("Reveal in Finder") {
                            if let url = exportedURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Back to Edit") {
                            appViewModel.currentStep = .edit
                        }
                        .buttonStyle(RunAutoEditButtonStyle(isDisabled: false))
                    } else {
                        Button("Export…") {
                            exportVideo()
                        }
                        .buttonStyle(RunAutoEditButtonStyle(isDisabled: isExporting || projectViewModel.segments.isEmpty))
                        .disabled(isExporting || projectViewModel.segments.isEmpty)
                    }
                }
            }
            .padding(30)
            .background(AutoEditTheme.panel)
        }
        .background(AutoEditTheme.bg)
        .onAppear {
            // Initialize resolution to project resolution
            selectedResolution = nil // nil means use project resolution
        }
    }
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Format")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar - TEAL
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(action: { exportFormat = format }) {
                        Text(format.displayName)
                            .font(.system(size: 14, weight: exportFormat == format ? .medium : .regular))
                            .foregroundColor(exportFormat == format ? .white : AutoEditTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if exportFormat == format {
                                        AutoEditTheme.teal
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(
                                        exportFormat == format ? Color.clear : AutoEditTheme.teal.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(999)
                            .shadow(color: exportFormat == format ? AutoEditTheme.teal.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    // MARK: - Resolution Section
    
    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            resolutionSectionHeader
            resolutionSectionBody
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var resolutionSectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Resolution & Aspect")
                    .autoEditSectionTitle()
                Spacer()
            }
            Rectangle()
                .fill(AutoEditTheme.orange)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
        }
    }
    
    private var resolutionSectionBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            resolutionProjectInfo
            Text("Export as:")
                .autoEditHint()
                .padding(.top, 4)
            resolutionButtonsRow
        }
    }
    
    private var resolutionProjectInfo: some View {
        HStack {
            Text("Project:")
                .autoEditHint()
            Text("\(projectViewModel.resolution.width)×\(projectViewModel.resolution.height) (\(projectViewModel.aspectRatio.displayName))")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AutoEditTheme.primaryText)
            Spacer()
        }
    }
    
    private var resolutionButtonsRow: some View {
        let availableResolutions = ResolutionPreset.presetsForAspectRatio(projectViewModel.aspectRatio)
        let resolutionOptions = buildResolutionOptions(from: availableResolutions)
        let isOriginalSelected = selectedResolution == nil
        let projectWidth = projectViewModel.resolution.width
        let projectHeight = projectViewModel.resolution.height
        
        return HStack(spacing: 12) {
            originalResolutionButton(isSelected: isOriginalSelected, width: projectWidth, height: projectHeight)
            ForEach(Array(resolutionOptions.enumerated()), id: \.offset) { index, option in
                resolutionOptionButton(option: option, isSelected: selectedResolution?.id == option.preset?.id)
            }
        }
    }
    
    private func originalResolutionButton(isSelected: Bool, width: Int, height: Int) -> some View {
        Button(action: { selectedResolution = nil }) {
            Text("Original (\(width)×\(height))")
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : AutoEditTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(height: 36)
                .background(isSelected ? AutoEditTheme.orange : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isSelected ? Color.clear : AutoEditTheme.orange.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(999)
                .shadow(color: isSelected ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func resolutionOptionButton(option: ResolutionOption, isSelected: Bool) -> some View {
        Button(action: { selectedResolution = option.preset }) {
            Text(option.label)
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : AutoEditTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(height: 36)
                .background(isSelected ? AutoEditTheme.orange : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(isSelected ? Color.clear : AutoEditTheme.orange.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(999)
                .shadow(color: isSelected ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Quality Section
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Quality")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar - ORANGE
            Rectangle()
                .fill(AutoEditTheme.orange)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            HStack(spacing: 12) {
                ForEach(ExportQuality.allCases, id: \.self) { q in
                    Button(action: { quality = q }) {
                        Text(q.label)
                            .font(.system(size: 14, weight: quality == q ? .medium : .regular))
                            .foregroundColor(quality == q ? .white : AutoEditTheme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: 36)
                            .background(
                                Group {
                                    if quality == q {
                                        AutoEditTheme.orange
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(
                                        quality == q ? Color.clear : AutoEditTheme.orange.opacity(0.5),
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(999)
                            .shadow(color: quality == q ? AutoEditTheme.orange.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Summary")
                    .autoEditSectionTitle()
                Spacer()
            }
            
            // Accent bar - TEAL
            Rectangle()
                .fill(AutoEditTheme.teal)
                .frame(width: 50, height: 3)
                .cornerRadius(1.5)
            
            VStack(alignment: .leading, spacing: 8) {
                SummaryRow(label: "Format", value: exportFormat.displayName)
                SummaryRow(label: "Resolution", value: resolutionDisplayName)
                SummaryRow(label: "Aspect Ratio", value: projectViewModel.aspectRatio.displayName)
                SummaryRow(label: "Quality", value: quality.label)
                SummaryRow(label: "Audio cleanup", value: projectViewModel.audioSettings.enableNoiseReduction ? "On" : "Off")
                SummaryRow(label: "Volume", value: String(format: "%.1f dB", projectViewModel.audioSettings.masterGainDB))
            }
        }
        .padding(20)
        .background(AutoEditTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AutoEditTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var resolutionDisplayName: String {
        if let resolution = selectedResolution {
            return "\(resolution.width)×\(resolution.height)"
        }
        return "\(projectViewModel.resolution.width)×\(projectViewModel.resolution.height)"
    }
    
    private func buildResolutionOptions(from presets: [ResolutionPreset]) -> [ResolutionOption] {
        // Filter out resolutions that are higher than project resolution (only allow downscaling)
        let projectWidth = projectViewModel.resolution.width
        let projectHeight = projectViewModel.resolution.height
        
        return presets.compactMap { preset in
            // Only show options that are same or smaller than project resolution
            if preset.width <= projectWidth && preset.height <= projectHeight && (preset.width != projectWidth || preset.height != projectHeight) {
                return ResolutionOption(preset: preset, label: "\(preset.label) (\(preset.width)×\(preset.height))")
            }
            return nil
        }
    }
    
    // MARK: - Export Functionality
    
    private func exportVideo() {
        // CRASH-PROOF: Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.exportVideo()
            }
            return
        }
        
        // CRASH-PROOF: Validate segments exist
        guard !projectViewModel.segments.isEmpty else {
            exportError = "No segments to export. Please add segments to the timeline first."
            return
        }
        
        // CRASH-PROOF: Validate project name
        let fileName = projectViewModel.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            exportError = "Invalid project name. Please set a project name first."
            return
        }
        
        // Show file picker first with crash-proof error handling
        autoreleasepool {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [exportFormat == .mp4 ? .mpeg4Movie : .quickTimeMovie]
            
            // CRASH-PROOF: Safe file name construction
            let fileExtension = exportFormat == .mp4 ? "mp4" : "mov"
            let safeFileName = fileName.isEmpty ? "Untitled" : fileName
            panel.nameFieldStringValue = "\(safeFileName).\(fileExtension)"
            panel.canCreateDirectories = true
            panel.title = "Export Video"
            panel.message = "Choose where to save your exported video"
            
            // CRASH-PROOF: Get window safely with error handling
            do {
                if let window = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow {
                    panel.beginSheetModal(for: window) { response in
                        // CRASH-PROOF: Validate response and URL
                        guard response == .OK else { return }
                        guard let url = panel.url else {
                            self.exportError = "Invalid save location selected."
                            return
                        }
                        
                        self.startExport(to: url)
                    }
                } else {
                    // Fallback to runModal if no window available
                    let response = panel.runModal()
                    guard response == .OK, let url = panel.url else {
                        exportError = "Export cancelled or invalid location selected."
                        return
                    }
                    
                    startExport(to: url)
                }
            } catch {
                exportError = "Failed to open save dialog: \(error.localizedDescription)"
                print("SkipSlate: ❌ Save panel error: \(error)")
            }
        }
    }
    
    private func startExport(to url: URL) {
        // CRASH-PROOF: Validate inputs before starting export
        guard !projectViewModel.segments.isEmpty else {
            exportError = "No segments to export. Please add segments to the timeline first."
            return
        }
        
        // CRASH-PROOF: Validate URL path exists (NSSavePanel should handle permissions)
        // Don't check writability here - NSSavePanel grants write access automatically in sandbox
        let directoryURL = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            exportError = "Selected directory does not exist. Please choose a valid location."
            return
        }
        
        isExporting = true
        exportProgress = 0.0
        exportError = nil
        showSuccess = false
        
        // Determine export resolution with validation
        let exportResolution = selectedResolution ?? projectViewModel.resolution
        
        // CRASH-PROOF: Validate resolution
        guard exportResolution.width > 0 && exportResolution.height > 0 else {
            exportError = "Invalid export resolution. Please select a valid resolution."
            isExporting = false
            return
        }
        
        Task {
            // CRASH-PROOF: Access security-scoped resource for NSSavePanel URL
            // NSSavePanel URLs automatically grant write access, but we need to access the resource
            var accessing = false
            autoreleasepool {
                accessing = url.startAccessingSecurityScopedResource()
                if !accessing {
                    print("SkipSlate: ⚠️ Warning - Could not start accessing security-scoped resource for URL: \(url.path)")
                    // Continue anyway - might still work without explicit access
                }
            }
            
            defer {
                if accessing {
                    autoreleasepool {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            
            do {
                // CRASH-PROOF: Validate URL before export
                // Ensure URL path is valid
                guard !url.path.isEmpty else {
                    throw NSError(
                        domain: "ExportService",
                        code: -100,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid export URL: path is empty"]
                    )
                }
                
                // Validate URL scheme
                guard url.scheme == "file" || url.isFileURL else {
                    throw NSError(
                        domain: "ExportService",
                        code: -101,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid export URL: must be a file URL"]
                    )
                }
                
                // CRASH-PROOF: Export with comprehensive error handling and validation
                try await ExportService.shared.export(
                    project: projectViewModel.project,
                    to: url,
                    format: exportFormat,
                    resolution: exportResolution,
                    quality: quality,
                    progressHandler: { progress in
                        Task { @MainActor in
                            // CRASH-PROOF: Validate progress value
                            autoreleasepool {
                                let clampedProgress = min(max(0.0, progress), 1.0)
                                guard clampedProgress.isFinite && !clampedProgress.isNaN else {
                                    print("SkipSlate: ⚠️ Invalid progress value: \(progress), ignoring")
                                    return
                                }
                                self.exportProgress = clampedProgress
                            }
                        }
                    }
                )
                
                // CRASH-PROOF: Validate export completed successfully with retries
                var fileExists = false
                for attempt in 0..<3 {
                    autoreleasepool {
                        fileExists = FileManager.default.fileExists(atPath: url.path)
                    }
                    if fileExists {
                        break
                    }
                    // Small delay before retry (file system might need a moment)
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                
                guard fileExists else {
                    throw NSError(
                        domain: "ExportService",
                        code: -102,
                        userInfo: [NSLocalizedDescriptionKey: "Export completed but file was not created at the expected location: \(url.path)"]
                    )
                }
                
                await MainActor.run {
                    autoreleasepool {
                        isExporting = false
                        exportProgress = 1.0
                        showSuccess = true
                        exportedURL = url
                        exportError = nil
                        
                        // CRITICAL: Open Finder to show exported file (with error handling)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            autoreleasepool {
                                do {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                    print("SkipSlate: ✅ Opened Finder to show exported file")
                                } catch {
                                    print("SkipSlate: ⚠️ Could not open Finder: \(error)")
                                    // Non-fatal - export succeeded, just couldn't open Finder
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    autoreleasepool {
                        isExporting = false
                        
                        // CRASH-PROOF: Provide user-friendly error messages
                        if let nsError = error as NSError? {
                            var errorMessage = nsError.localizedDescription
                            if errorMessage.isEmpty {
                                errorMessage = "Export failed. Please try again or check available disk space."
                            }
                            
                            // Provide more specific error messages for common issues
                            if nsError.domain == "ExportService" {
                                switch nsError.code {
                                case -100, -101, -102:
                                    errorMessage = "Failed to write file. Please choose a different location and try again."
                                case -1:
                                    errorMessage = "Export failed: \(errorMessage)"
                                default:
                                    break
                                }
                            }
                            
                            exportError = errorMessage
                            print("SkipSlate: ❌ Export error: \(errorMessage)")
                            print("SkipSlate: Error domain: \(nsError.domain), code: \(nsError.code)")
                        } else {
                            exportError = "Export failed: \(error.localizedDescription)"
                            print("SkipSlate: ❌ Export error: \(error)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Resolution Option Helper

private struct ResolutionOption {
    let preset: ResolutionPreset?
    let label: String
}

enum ExportQuality: CaseIterable {
    case high
    case balanced
    case small
    
    var label: String {
        switch self {
        case .high: return "High"
        case .balanced: return "Balanced"
        case .small: return "Small"
        }
    }
    
    var bitrateMultiplier: Double {
        switch self {
        case .high: return 1.0
        case .balanced: return 0.75
        case .small: return 0.5
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .autoEditHint()
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AutoEditTheme.primaryText)
        }
    }
}

