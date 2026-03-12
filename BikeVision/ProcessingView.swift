// ProcessingView.swift
// BikeVision
//
// Runs QuickPosePostProcessor on the selected (and optionally trimmed) video.
// Shows a progress bar during processing then calls onComplete(session).

import SwiftUI
import AVFoundation
import QuickPoseCore

struct ProcessingView: View {
    let videoURL: URL
    let side: CyclingSide
    /// Called on the main actor when processing finishes successfully.
    var onComplete: (BikeSession) -> Void

    @State private var progress: Double = 0
    @State private var statusText = "Preparing…"
    @State private var errorMessage: String?
    @State private var showError = false

    private let accumulator = AngleAccumulator()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)

            VStack(spacing: 8) {
                Text("Analysing Video")
                    .font(.title2.bold())
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: statusText)
            }

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut, value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startProcessing()
        }
        .alert("Processing Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Processing

    private func startProcessing() {
        let features = Config.cyclingFeatures(side: side)
        let outputURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bikevision_output_\(Int(Date().timeIntervalSince1970)).mov")

        Task.detached(priority: .userInitiated) {
            do {
                let postProcessor = QuickPosePostProcessor(sdkKey: Config.quickPoseSDKKey)

                let request = QuickPosePostProcessor.Request(
                    input: videoURL,
                    output: outputURL,
                    outputType: .mov
                )

                try postProcessor.process(
                    features: features,
                    modelConfig: Config.modelConfig,
                    isFrontCamera: false,
                    request: request
                ) { frameProgress, _, _, _, featuresResult, _, _ in

                    for (feature, result) in featuresResult {
                        guard let name = feature.jointName, result.value > 0 else { continue }
                        accumulator.record(angle: result.value, displayAngle: result.stringValue, forJoint: name)
                    }

                    let pct = frameProgress ?? 0
                    let text = progressStatusText(for: pct)
                    Task { @MainActor in
                        progress = pct
                        statusText = text
                    }
                }

                let stats = accumulator.jointStats
                let session = BikeSession(
                    annotatedVideoURL: outputURL,
                    stats: stats,
                    side: side
                )
                await MainActor.run {
                    onComplete(session)
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func progressStatusText(for progress: Double) -> String {
        switch progress {
        case 0..<0.1:   return "Loading video…"
        case 0.1..<0.4: return "Detecting pose…"
        case 0.4..<0.8: return "Measuring joint angles…"
        case 0.8..<1.0: return "Finalising output…"
        default:         return "Complete"
        }
    }
}

// MARK: - QuickPose.Feature Joint Name

extension QuickPose.Feature {
    /// Short display name used as the dictionary key in AngleAccumulator.
    /// Returns nil for non-measurement features (e.g. overlays) so those
    /// frames are not recorded into the accumulator.
    var jointName: String? {
        switch self {
        case .rangeOfMotion(let joint, _):
            switch joint {
            case .shoulder: return "Shoulder"
            case .elbow:    return "Elbow"
            case .hip:      return "Hip"
            case .knee:     return "Knee"
            case .ankle:    return "Ankle"
            default:        return nil
            }
        default:
            return nil
        }
    }
}
