// BikeSession.swift
// BikeVision
//
// Lightweight model that carries the results of a completed biomechanics session
// from LiveCameraView / ProcessingView through to ResultsView.

import Foundation

/// A single joint's angle statistics captured over a session.
struct JointStat: Identifiable {
    let id = UUID()
    /// Display name shown in the results card, e.g. "Knee".
    let name: String
    /// Minimum angle recorded (degrees).
    let minAngle: Double
    /// Maximum angle recorded (degrees).
    let maxAngle: Double

    /// Range of motion = max − min.
    var rangeOfMotion: Double { maxAngle - minAngle }

    /// Formatted string for the minimum angle.
    var minString: String { String(format: "%.0f°", minAngle) }
    /// Formatted string for the maximum angle.
    var maxString: String { String(format: "%.0f°", maxAngle) }
    /// Formatted string for the range of motion.
    var romString: String { String(format: "%.0f°", rangeOfMotion) }
}

/// Accumulates raw angle samples per joint during a live or post-processed session.
/// Once data collection is complete, call `jointStats` to obtain the final summary.
final class AngleAccumulator {
    // jointName → [angle values]
    private var samples: [String: [Double]] = [:]

    /// Record a new angle reading for a named joint.
    /// - Parameters:
    ///   - angle: The raw `result.value` from QuickPose (degrees).
    ///   - displayAngle: The rendered `result.stringValue` from QuickPose (e.g. "92°").
    ///                   When non-nil this is parsed and used instead of `angle` so the
    ///                   results card always matches exactly what is drawn on the video.
    func record(angle: Double, displayAngle: String? = nil, forJoint name: String) {
        let value: Double
        if let display = displayAngle,
           let parsed = Double(display.trimmingCharacters(in: .init(charactersIn: "° "))) {
            value = parsed
        } else {
            value = angle
        }
        samples[name, default: []].append(value)
    }

    /// Returns the collected `JointStat` array, sorted by a canonical display order.
    var jointStats: [JointStat] {
        let order = ["Shoulder", "Elbow", "Hip", "Knee", "Ankle"]
        return samples.compactMap { name, values -> JointStat? in
            guard !values.isEmpty else { return nil }
            return JointStat(
                name: name,
                minAngle: values.min()!,
                maxAngle: values.max()!
            )
        }
        .sorted { a, b in
            let ai = order.firstIndex(of: a.name) ?? Int.max
            let bi = order.firstIndex(of: b.name) ?? Int.max
            return ai < bi
        }
    }

    /// Resets all accumulated data.
    func reset() {
        samples.removeAll()
    }
}

/// The completed output of a BikeVision session, passed to `ResultsView`.
struct BikeSession {
    /// URL of the annotated output video written by QuickPosePostProcessor,
    /// or of the live recording captured via camera.
    let annotatedVideoURL: URL

    /// Per-joint angle statistics collected during the session.
    let stats: [JointStat]

    /// Which side of the cyclist was visible.
    let side: CyclingSide
}
