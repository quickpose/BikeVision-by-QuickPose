// Config.swift
// BikeVision
//
// Central configuration for the QuickPose SDK key and cycling feature definitions.
// Replace QUICKPOSE_SDK_KEY with your key from https://dev.quickpose.ai

import Foundation
import QuickPoseCore

enum Config {
    // MARK: - SDK Key
    // Obtain a free key at https://dev.quickpose.ai and replace the placeholder below.
    static let quickPoseSDKKey = "Your QuickPose SDK Key"

    // MARK: - Bike Style
    // Slightly smaller arcs and text so multiple overlapping joints stay readable
    // on a full-frame cyclist video.
    static let bikeStyle = QuickPose.Style(
        relativeFontSize: 0.33,
        relativeArcSize: 0.4,
        relativeLineWidth: 0.3
    )

    // MARK: - Feature Builders

    /// Returns the five cycling features for the given riding direction.
    ///
    /// - Parameter side: Which side of the cyclist is facing the camera.
    ///   `.right` means the cyclist is travelling left-to-right in the frame (right side visible).
    ///   `.left`  means the cyclist is travelling right-to-left in the frame (left side visible).
    /// - Returns: Ordered array of QuickPose features: shoulder, elbow, hip, knee, ankle.
    static func cyclingFeatures(side: CyclingSide) -> [QuickPose.Feature] {
        let isLeftSide = side == .left
        let s: QuickPose.Side = isLeftSide ? .left : .right
        return [
            .rangeOfMotion(.shoulder(side: s, clockwiseDirection: isLeftSide), style: bikeStyle),
            .rangeOfMotion(.elbow(side: s, clockwiseDirection: isLeftSide), style: bikeStyle),
            .rangeOfMotion(.hip(side: s, clockwiseDirection: isLeftSide), style: bikeStyle),
            .rangeOfMotion(.knee(side: s, clockwiseDirection: !isLeftSide), style: bikeStyle),
            .rangeOfMotion(.ankle(side: s, clockwiseDirection: isLeftSide), style: bikeStyle),
        ]
    }

    // MARK: - Model Config
    // Disable face and hand tracking — not needed for cycling biomechanics.
    static let modelConfig = QuickPose.ModelConfig(
        detailedFaceTracking: false,
        detailedHandTracking: false
    )
}

// MARK: - Supporting Types

/// The side of the cyclist's body that is visible to the camera.
enum CyclingSide: String, CaseIterable, Identifiable {
    case left  = "Left Side"
    case right = "Right Side"
    

    var id: String { rawValue }

    /// Human-readable description shown in the UI.
    var displayName: String { rawValue }

    /// Icon name for the direction of travel illustrated on the side picker.
    var systemImage: String {
        switch self {
        case .left:  return "arrow.left"   // cyclist travels right-to-left; left side faces camera
        case .right: return "arrow.right"  // cyclist travels left-to-right; right side faces camera
        }
    }

    /// Short description shown below the icon in the picker.
    var description: String {
        switch self {
        case .right: return "Cyclist moving left → right\nRight side of body visible"
        case .left:  return "Cyclist moving right → left\nLeft side of body visible"
        }
    }
}

/// The flow that led to the side picker — determines what happens after selection.
enum SessionFlow {
    case record
    case upload(videoURL: URL)
}
