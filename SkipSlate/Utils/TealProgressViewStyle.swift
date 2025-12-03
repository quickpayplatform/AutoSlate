//
//  TealProgressViewStyle.swift
//  SkipSlate
//
//  Created by Tee Forest on 12/3/25.
//
//

import SwiftUI

struct TealCircularProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        TealSpinnerView()
    }
}

struct TealSpinnerView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(AutoEditTheme.teal.opacity(0.3), lineWidth: 3)
            
            // Progress arc that spins
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(AutoEditTheme.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90 + rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

extension ProgressViewStyle where Self == TealCircularProgressViewStyle {
    static var tealCircular: TealCircularProgressViewStyle {
        TealCircularProgressViewStyle()
    }
}

