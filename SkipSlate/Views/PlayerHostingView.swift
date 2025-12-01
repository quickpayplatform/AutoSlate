//
//  PlayerHostingView.swift
//  SkipSlate
//
//  Created by Cursor on 11/25/25.
//

import AppKit
import AVFoundation

/// Custom NSView that hosts an AVPlayerLayer for video playback
/// Ensures the player layer fills the view bounds and is properly configured
final class PlayerHostingView: NSView {
    lazy var playerLayer: AVPlayerLayer = {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        // Attach playerLayer to the view's layer
        if self.layer == nil {
            self.wantsLayer = true
        }
        self.layer?.addSublayer(layer)
        return layer
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Ensure playerLayer is attached
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        // Log bounds for debugging - always log, even if zero
        print("SkipSlate: PlayerHostingView layout, bounds = \(bounds), frame = \(frame)")
        
        // Always set the frame, even if bounds are zero (they'll be updated later)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Use frame instead of bounds to ensure proper positioning
        if bounds.width > 0 && bounds.height > 0 {
            playerLayer.frame = bounds
            print("SkipSlate: PlayerHostingView - Set playerLayer frame to \(bounds)")
        } else {
            // Set a minimum frame to prevent zero bounds error
            playerLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            print("SkipSlate: PlayerHostingView - WARNING: Zero bounds, using minimum frame")
        }
        
        CATransaction.commit()
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            print("SkipSlate: PlayerHostingView moved to superview, bounds = \(bounds), frame = \(frame)")
            // Force layout update after a short delay to ensure bounds are set
            DispatchQueue.main.async { [weak self] in
                self?.needsLayout = true
            }
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            print("SkipSlate: PlayerHostingView moved to window, bounds = \(bounds), frame = \(frame)")
            // Force layout update when window is available
            DispatchQueue.main.async { [weak self] in
                self?.needsLayout = true
            }
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        print("SkipSlate: PlayerHostingView frame size changed to \(newSize)")
        // Update player layer frame when view size changes
        if newSize.width > 0 && newSize.height > 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = CGRect(origin: .zero, size: newSize)
            CATransaction.commit()
        }
    }
}

