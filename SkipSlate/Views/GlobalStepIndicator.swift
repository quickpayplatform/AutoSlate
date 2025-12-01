//
//  GlobalStepIndicator.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import SwiftUI

struct GlobalStepIndicator: View {
    let currentStep: WizardStep
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                StepIndicatorItem(
                    step: step,
                    isCurrent: currentStep == step,
                    isCompleted: step.rawValue < currentStep.rawValue
                )
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(AppColors.panelBackground)
    }
}

struct StepIndicatorItem: View {
    let step: WizardStep
    let isCurrent: Bool
    let isCompleted: Bool
    
    // Use teal/orange theme when on Auto Edit screen or later
    private var useTealOrangeTheme: Bool {
        // Use teal/orange for Auto Edit step and beyond
        step.rawValue >= 5
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if isCompleted {
                    Circle()
                        .fill(useTealOrangeTheme ? AutoEditTheme.teal : AppColors.podcastColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .font(.system(size: 14))
                } else if isCurrent {
                    Circle()
                        .fill(useTealOrangeTheme ? AutoEditTheme.teal : AppColors.podcastColor)
                        .frame(width: 40, height: 40)
                    Text("\(step.rawValue)")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(
                                    useTealOrangeTheme ? AutoEditTheme.orange.opacity(0.6) : AppColors.secondaryText.opacity(0.3),
                                    lineWidth: 2
                                )
                        )
                    Text("\(step.rawValue)")
                        .foregroundColor(useTealOrangeTheme ? AutoEditTheme.secondaryText : AppColors.secondaryText)
                        .fontWeight(.regular)
                }
            }
            
            Text(step.label)
                .font(.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundColor(
                    isCurrent || isCompleted
                        ? (useTealOrangeTheme ? AutoEditTheme.primaryText : AppColors.primaryText)
                        : (useTealOrangeTheme ? AutoEditTheme.secondaryText : AppColors.secondaryText)
                )
        }
        .frame(width: 80)
    }
}

