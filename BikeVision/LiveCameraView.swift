// LiveCameraView.swift
// BikeVision
//
// Live camera view that uses QuickPose to overlay joint angle measurements
// in real time. The user taps "Stop" when they're done; the accumulated
// angle data is wrapped in a BikeSession and returned via onComplete.
// Annotated frames are captured to a video file via AVAssetWriter so the
// results screen can show and share the recording.

import SwiftUI
import AVFoundation
import QuickPoseCore
import QuickPoseCamera
import QuickPoseSwiftUI

struct LiveCameraView: View {
    let side: CyclingSide
    /// Called when the user stops the session and angle data is available.
    var onComplete: (BikeSession) -> Void

    @State private var quickPose = QuickPose(sdkKey: Config.quickPoseSDKKey)
    @State private var overlayImage: UIImage?
    @State private var statusMessage: String?
    @State private var accumulator = AngleAccumulator()
    @State private var isLive = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var frameRate: Double? = 60.0

    // Video recording
    @State private var assetWriter: AVAssetWriter?
    @State private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    @State private var recordingURL: URL?
    private let writeQueue = DispatchQueue(label: "ai.bikevision.videowrite", qos: .userInitiated)

    private var features: [QuickPose.Feature] {
        Config.cyclingFeatures(side: side)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Full-screen camera feed
                QuickPoseCameraView(
                    useFrontCamera: false,
                    delegate: quickPose,
                    frameRate: $frameRate
                )

                // QuickPose joint angle overlay
                QuickPoseOverlayView(overlayImage: $overlayImage)

                // "No person detected" / status banner
                if let message = statusMessage {
                    StatusBanner(message: message)
                        .padding(.top, geometry.safeAreaInsets.top + 16)
                }

                // Recording indicator
                VStack {
                    HStack {
                        Spacer()
                        RecordingIndicator(isLive: isLive)
                            .padding(.top, geometry.safeAreaInsets.top + 8)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }

                // Stop button
                VStack {
                    Spacer()
                    Button(action: stopAndFinish) {
                        Label("Stop & View Results", systemImage: "stop.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(radius: 8)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
            .frame(
                width: geometry.safeAreaInsets.leading + geometry.size.width + geometry.safeAreaInsets.trailing,
                height: geometry.safeAreaInsets.top + geometry.size.height + geometry.safeAreaInsets.bottom
            )
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Live Analysis")
        .onAppear {
            startQuickPose()
        }
        .onDisappear {
            quickPose.stop()
        }
        .alert("Session Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - QuickPose Start

    private func startQuickPose() {
        accumulator.reset()
        // overlayHasCameraAsBackground bakes the camera feed into the overlay
        // image, so the recorded video shows the actual person + skeleton lines,
        // and the live preview stays visible even when no person is detected.
        let allFeatures = features + [.overlayHasCameraAsBackground(darkenCamera: 0)]
        quickPose.start(
            features: allFeatures,
            modelConfig: Config.modelConfig,
            onFrame: { status, image, featuresResult, _, _ in
                // Always show whatever image QuickPose returns (camera + skeleton).
                overlayImage = image
                switch status {
                case .success(let info):
                    statusMessage = nil
                    isLive = true
                    for (feature, result) in featuresResult {
                        guard let name = feature.jointName, result.value > 0 else { continue }
                        accumulator.record(angle: result.value, displayAngle: result.stringValue, forJoint: name)
                    }
                    let (_, _, frameSize, timestamp) = info
                    if let frameImage = image {
                        if assetWriter == nil {
                            startRecording(size: frameSize, startTime: timestamp)
                        }
                        writeFrame(frameImage, at: timestamp)
                    }
                case .noPersonFound(let info):
                    statusMessage = "Position the cyclist fully in frame"
                    isLive = false
                    // Still record frames so we don't lose context footage.
                    let (_, _, frameSize, timestamp) = info
                    if let frameImage = image {
                        if assetWriter == nil {
                            startRecording(size: frameSize, startTime: timestamp)
                        }
                        writeFrame(frameImage, at: timestamp)
                    }
                case .sdkValidationError:
                    statusMessage = "SDK key invalid — see Config.swift"
                    isLive = false
                @unknown default:
                    break
                }
            }
        )
    }

    // MARK: - Recording Helpers

    private func startRecording(size: CGSize, startTime: CMTime) {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bikevision_live_\(Int(Date().timeIntervalSince1970)).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceAttributes
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: startTime)

        recordingURL = url
        assetWriter = writer
        pixelBufferAdaptor = adaptor
    }

    private func writeFrame(_ image: UIImage, at time: CMTime) {
        guard let adaptor = pixelBufferAdaptor,
              adaptor.assetWriterInput.isReadyForMoreMediaData,
              let pixelBuffer = image.toPixelBuffer() else { return }
        writeQueue.async {
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    // MARK: - Stop

    private func stopAndFinish() {
        quickPose.stop()
        isLive = false

        let stats = accumulator.jointStats
        guard !stats.isEmpty else {
            errorMessage = "No angle data was collected. Make sure the cyclist was fully visible during the session."
            showError = true
            return
        }

        let capturedURL = recordingURL
        let capturedWriter = assetWriter
        let capturedSide = side

        writeQueue.async {
            capturedWriter?.finishWriting {
                let videoURL: URL
                if let url = capturedURL, capturedWriter?.status == .completed {
                    videoURL = url
                } else {
                    videoURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("live_session_no_video")
                }
                let session = BikeSession(annotatedVideoURL: videoURL, stats: stats, side: capturedSide)
                DispatchQueue.main.async {
                    onComplete(session)
                }
            }
        }
    }
}

// MARK: - UIImage → CVPixelBuffer

private extension UIImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        ) == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        ctx?.translateBy(x: 0, y: size.height)
        ctx?.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx!)
        draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

// MARK: - Supporting Views

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
    }
}

private struct RecordingIndicator: View {
    let isLive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isLive ? "LIVE" : "WAITING")
                .font(.caption.bold())
                .foregroundStyle(isLive ? .green : .gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
    }
}
