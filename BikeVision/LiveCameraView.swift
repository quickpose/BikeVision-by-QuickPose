// LiveCameraView.swift
// BikeVision
//
// Live camera view that uses QuickPose to overlay joint angle measurements
// in real time. The user first positions the cyclist using the bounding box
// guide, taps "Start Recording", then taps "Stop & View Results" when done.
// Annotated frames are captured to a video file via AVAssetWriter so the
// results screen can show and share the recording.

import SwiftUI
import AVFoundation
import QuickPoseCore
import QuickPoseCamera
import QuickPoseSwiftUI

struct LiveCameraView: View {
    let side: CyclingSide
    var onComplete: (BikeSession) -> Void

    private let quickPose = QuickPose(sdkKey: Config.quickPoseSDKKey)
    @State private var overlayImage: UIImage?
    @State private var statusMessage: String?
    @State private var accumulator = AngleAccumulator()
    @State private var isLive = false
    @State private var isRecording = false
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
            let fullWidth  = geometry.safeAreaInsets.leading + geometry.size.width  + geometry.safeAreaInsets.trailing
            let fullHeight = geometry.safeAreaInsets.top     + geometry.size.height + geometry.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                // Full-screen camera feed
                QuickPoseCameraView(
                    useFrontCamera: false,
                    delegate: quickPose,
                    frameRate: $frameRate
                )

                // QuickPose joint angle overlay
                QuickPoseOverlayView(overlayImage: $overlayImage)

                // Bounding box guide — always visible so the user can frame up
                CyclistFramingGuide(
                    screenSize: CGSize(width: fullWidth, height: fullHeight),
                    isLive: isLive,
                    side: side
                )

                // Status banner ("Position cyclist…" / SDK error)
                if let message = statusMessage {
                    StatusBanner(message: message)
                        .padding(.top, geometry.safeAreaInsets.top + 16)
                }

                // Top-right indicator
                VStack {
                    HStack {
                        Spacer()
                        RecordingIndicator(isLive: isLive, isRecording: isRecording)
                            .padding(.top, geometry.safeAreaInsets.top + 8)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }

                // Bottom action button
                VStack {
                    Spacer()
                    if isRecording {
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
                    } else {
                        Button(action: beginRecording) {
                            Label("Start Recording", systemImage: "record.circle")
                                .font(.headline)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(isLive ? Color.accentColor : Color.gray)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(radius: 8)
                        }
                        .disabled(!isLive)
                    }
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
            .frame(width: fullWidth, height: fullHeight)
            .edgesIgnoringSafeArea(.all)
        }
        .navigationBarHidden(true)
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
        let allFeatures = features + [.overlayHasCameraAsBackground(darkenCamera: 0)]
        quickPose.start(
            features: allFeatures,
            modelConfig: Config.modelConfig,
            onFrame: { status, image, featuresResult, _, _ in
                switch status {
                case .success(let info):
                    let (_, _, frameSize, timestamp) = info
                    if isRecording {
                        for (feature, result) in featuresResult {
                            guard let name = feature.jointName, result.value > 0 else { continue }
                            accumulator.record(angle: result.value, displayAngle: result.stringValue, forJoint: name)
                        }
                        if let frameImage = image {
                            if assetWriter == nil {
                                startRecording(size: frameSize, startTime: timestamp)
                            }
                            writeFrame(frameImage, at: timestamp)
                        }
                    }
                    DispatchQueue.main.async {
                        overlayImage = image
                        statusMessage = nil
                        isLive = true
                    }
                case .noPersonFound(let info):
                    let (_, _, frameSize, timestamp) = info
                    if isRecording, let frameImage = image {
                        if assetWriter == nil {
                            startRecording(size: frameSize, startTime: timestamp)
                        }
                        writeFrame(frameImage, at: timestamp)
                    }
                    DispatchQueue.main.async {
                        overlayImage = image
                        statusMessage = "Position the cyclist fully in frame"
                        isLive = false
                    }
                case .sdkValidationError:
                    DispatchQueue.main.async {
                        overlayImage = image
                        statusMessage = "SDK key invalid — see Config.swift"
                        isLive = false
                    }
                @unknown default:
                    DispatchQueue.main.async {
                        overlayImage = image
                    }
                }
            }
        )
    }

    // MARK: - Recording Control

    private func beginRecording() {
        guard isLive else { return }
        accumulator.reset()
        isRecording = true
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
        isRecording = false

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

// MARK: - Cyclist Framing Guide

/// A full-screen overlay that draws a rounded rectangle showing the ideal
/// position for the cyclist. The box turns green when a person is detected.
private struct CyclistFramingGuide: View {
    let screenSize: CGSize
    let isLive: Bool
    let side: CyclingSide

    // The guide occupies most of the screen height and a wide landscape strip
    private var boxRect: CGRect {
        let w = screenSize.width * 0.82
        let h = screenSize.height * 0.78
        let x = (screenSize.width - w) / 2
        let y = (screenSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var body: some View {
        let color: Color = isLive ? .green : .white
        ZStack {
            // Dimmed surround outside the box
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .frame(width: boxRect.width, height: boxRect.height)
                                .offset(
                                    x: boxRect.midX - screenSize.width / 2,
                                    y: boxRect.midY - screenSize.height / 2
                                )
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                )

            // Dashed border
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    color.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                )
                .frame(width: boxRect.width, height: boxRect.height)
                .offset(
                    x: boxRect.midX - screenSize.width / 2,
                    y: boxRect.midY - screenSize.height / 2
                )
                .animation(.easeInOut(duration: 0.3), value: isLive)

            // Corner accents
            CornerAccents(rect: boxRect, screenSize: screenSize, color: color)
                .animation(.easeInOut(duration: 0.3), value: isLive)

            // Label at the bottom of the box
            VStack {
                Spacer()
                    .frame(height: boxRect.maxY + 10)
                Text(isLive ? "Cyclist detected ✓" : "Position cyclist within the box")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.3), value: isLive)
                Spacer()
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
    }
}

/// Draws bold L-shaped corner marks at each corner of the framing box.
private struct CornerAccents: View {
    let rect: CGRect
    let screenSize: CGSize
    let color: Color

    private let armLength: CGFloat = 22
    private let lineWidth: CGFloat = 3.5
    private let radius: CGFloat = 16

    var body: some View {
        Canvas { ctx, _ in
            let ox = rect.minX - screenSize.width / 2
            let oy = rect.minY - screenSize.height / 2

            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                // top-left
                (CGPoint(x: ox + armLength, y: oy + radius),
                 CGPoint(x: ox + radius,    y: oy + radius),
                 CGPoint(x: ox + radius,    y: oy + armLength)),
                // top-right
                (CGPoint(x: ox + rect.width - armLength, y: oy + radius),
                 CGPoint(x: ox + rect.width - radius,    y: oy + radius),
                 CGPoint(x: ox + rect.width - radius,    y: oy + armLength)),
                // bottom-left
                (CGPoint(x: ox + armLength, y: oy + rect.height - radius),
                 CGPoint(x: ox + radius,    y: oy + rect.height - radius),
                 CGPoint(x: ox + radius,    y: oy + rect.height - armLength)),
                // bottom-right
                (CGPoint(x: ox + rect.width - armLength, y: oy + rect.height - radius),
                 CGPoint(x: ox + rect.width - radius,    y: oy + rect.height - radius),
                 CGPoint(x: ox + rect.width - radius,    y: oy + rect.height - armLength)),
            ]

            let resolved = ctx.resolve(SwiftUI.Image(systemName: "circle"))  // unused; just to satisfy Canvas
            _ = resolved

            for (a, mid, b) in corners {
                var path = Path()
                path.move(to: a)
                path.addLine(to: mid)
                path.addLine(to: b)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
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
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRecording ? Color.red : isLive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isRecording ? "REC" : isLive ? "READY" : "WAITING")
                .font(.caption.bold())
                .foregroundStyle(isRecording ? .red : isLive ? .green : .gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: isLive)
    }
}
