//
//  ColorWheelComponents.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

/// Circular dial/wheel control for exposure, contrast, saturation
struct ColorDial: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let color: Color
    
    @State private var isDragging = false
    @State private var dragStartValue: Double = 0
    @State private var dragStartLocation: CGPoint = .zero
    
    private let dialSize: CGFloat = 80
    private let trackWidth: CGFloat = 6
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.primaryText)
            
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: size / 2, y: size / 2)
                
                ZStack {
                    // Background circle
                    Circle()
                        .fill(AppColors.panelBackground)
                        .frame(width: size, height: size)
                    
                    // Track (full circle)
                    Circle()
                        .trim(from: 0, to: 1)
                        .stroke(AppColors.panelBorder.opacity(0.3), lineWidth: trackWidth)
                        .frame(width: size, height: size)
                    
                    // Value arc (from 0 to current value)
                    let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    Circle()
                        .trim(from: 0, to: normalizedValue)
                        .stroke(color, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(-90)) // Start from top
                    
                    // Center value display
                    VStack(spacing: 2) {
                        Text(format(value))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                    }
                    .frame(width: size - 20, height: size - 20)
                }
                .frame(width: size, height: size)
                .contentShape(Circle()) // Make entire circle tappable
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                dragStartValue = value
                                dragStartLocation = gesture.location
                            }
                            
                            // Calculate angle from center using gesture location relative to geometry
                            let delta = CGPoint(
                                x: gesture.location.x - center.x,
                                y: gesture.location.y - center.y
                            )
                            
                            // Calculate angle (-180 to 180 degrees)
                            var angle = atan2(delta.y, delta.x) * 180 / .pi
                            angle += 90 // Adjust so 0 is at top
                            if angle < 0 { angle += 360 }
                            
                            // Convert angle (0-360) to value in range
                            let normalizedValue = angle / 360.0
                            let newValue = range.lowerBound + normalizedValue * (range.upperBound - range.lowerBound)
                            
                            // Update value - this will trigger the binding
                            value = max(range.lowerBound, min(range.upperBound, newValue))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(width: dialSize, height: dialSize)
        }
    }
}

/// Color wheel for hue/saturation selection
struct ColorWheel: View {
    @Binding var hue: Double // 0-360
    @Binding var saturation: Double // 0-1
    
    private let wheelSize: CGFloat = 200
    private let brightness: Double = 1.0 // Fixed brightness for color wheel
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Color Grade")
                .font(.caption)
                .foregroundColor(AppColors.primaryText)
            
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: size / 2, y: size / 2)
                let maxRadius = size / 2 - 10
                
                ZStack {
                    // Color wheel background (using gradient approximation)
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(hue: 0/360, saturation: 1, brightness: brightness),
                                    Color(hue: 60/360, saturation: 1, brightness: brightness),
                                    Color(hue: 120/360, saturation: 1, brightness: brightness),
                                    Color(hue: 180/360, saturation: 1, brightness: brightness),
                                    Color(hue: 240/360, saturation: 1, brightness: brightness),
                                    Color(hue: 300/360, saturation: 1, brightness: brightness),
                                    Color(hue: 360/360, saturation: 1, brightness: brightness)
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: size, height: size)
                        .overlay(
                            // Radial gradient for saturation (center = white, edges = full color)
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(1 - saturation)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: maxRadius
                            )
                        )
                        .clipShape(Circle())
                    
                    // Center circle (neutral/white)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.3), lineWidth: 1)
                        )
                    
                    // Selection indicator
                    let angle = (hue * .pi / 180.0) - (.pi / 2.0) // Convert to radians, offset for top start
                    let radius = maxRadius * saturation
                    let x = cos(angle) * radius
                    let y = sin(angle) * radius
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .offset(x: x, y: y)
                }
                .frame(width: size, height: size)
                .contentShape(Circle()) // Make entire circle tappable
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let delta = CGPoint(
                                x: gesture.location.x - center.x,
                                y: gesture.location.y - center.y
                            )
                            
                            // Calculate distance from center (saturation)
                            let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
                            let newSaturation = min(1.0, max(0.0, distance / maxRadius))
                            
                            // Calculate angle (hue)
                            var angle = atan2(delta.y, delta.x) * 180 / .pi
                            angle += 90 // Adjust so 0 is at top
                            if angle < 0 { angle += 360 }
                            
                            // Update bindings - this will trigger the setters
                            saturation = newSaturation
                            hue = angle
                        }
                )
            }
            .frame(width: wheelSize, height: wheelSize)
            
            // Reset button
            Button("Reset") {
                hue = 0
                saturation = 0
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

