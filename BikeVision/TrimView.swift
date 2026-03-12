// TrimView.swift
// BikeVision
//
// Lets the user preview the selected video and trim it using an iOS Photos-style
// filmstrip trim bar with draggable start/end handles.
// Trimming is performed with AVAssetExportSession on a background Task.
// Calls onContinue(trimmedURL) when the user is ready to proceed.

import SwiftUI
import AVKit
import AVFoundation

// MARK: - TrimView

struct TrimView: View {
    let videoURL: URL
    /// When non-nil, an inline side picker is shown and the button label changes.
    var selectedSide: Binding<CyclingSide>?
    var onContinue: (URL) -> Void

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 1
    @State private var isTrimming = false
    @State private var trimError: String?
    @State private var thumbnails: [UIImage] = []

    init(videoURL: URL, selectedSide: Binding<CyclingSide>? = nil, onContinue: @escaping (URL) -> Void) {
        self.videoURL = videoURL
        self.selectedSide = selectedSide
        self.onContinue = onContinue
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Trim bar section
            VStack(alignment: .leading, spacing: 12) {
                Text("Trim Video  (optional)")
                    .font(.headline)
                    .padding(.top, 12)

                if duration > 0 {
                    TrimRangeBar(
                        thumbnails: thumbnails,
                        duration: duration,
                        startTime: $startTime,
                        endTime: $endTime
                    ) { time in
                        seekPreview(to: time)
                    }

                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("Clip length: \(formatTime(endTime - startTime))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") {
                            startTime = 0
                            endTime = duration
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)

            // Inline side picker (shown when selectedSide binding is provided)
            if let sideBinding = selectedSide {
                inlineSidePicker(selection: sideBinding)
                    .padding(.top, 8)
            }

            if let error = trimError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            Spacer()

            // Continue button
            Button {
                let needsTrim = startTime > 0.01 || (duration > 0 && endTime < duration - 0.01)
                if needsTrim {
                    performTrim()
                } else {
                    onContinue(videoURL)
                }
            } label: {
                if isTrimming {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Label("Analyse Video", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .disabled(isTrimming)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle("Trim Video")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDuration()
        }
    }

    // MARK: - Inline Side Picker

    @ViewBuilder
    private func inlineSidePicker(selection: Binding<CyclingSide>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which side is visible?")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            HStack(spacing: 12) {
                ForEach(CyclingSide.allCases) { side in
                    let isSelected = selection.wrappedValue == side
                    Button {
                        selection.wrappedValue = side
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: side.systemImage)
                                .font(.headline)
                                .foregroundStyle(isSelected ? .white : .secondary)
                            Text(side.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color(.separator).opacity(0.5),
                                                      lineWidth: isSelected ? 0 : 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func loadDuration() {
        Task {
            let asset = AVAsset(url: videoURL)
            guard let seconds = try? await asset.load(.duration).seconds, seconds.isFinite else { return }
            await MainActor.run {
                duration = seconds
                endTime = seconds
            }
            let frames = await generateThumbnails(for: asset, count: 12)
            await MainActor.run {
                thumbnails = frames
            }
        }
    }

    private func seekPreview(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func performTrim() {
        isTrimming = true
        trimError = nil

        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bikevision_trimmed_\(Int(Date().timeIntervalSince1970)).mov")

        Task {
            do {
                let url = try await trimVideo(
                    sourceURL: videoURL,
                    outputURL: outputURL,
                    startSeconds: startTime,
                    endSeconds: endTime
                )
                await MainActor.run {
                    isTrimming = false
                    onContinue(url)
                }
            } catch {
                await MainActor.run {
                    isTrimming = false
                    trimError = "Trim failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Thumbnail Generation

private func generateThumbnails(for asset: AVAsset, count: Int) async -> [UIImage] {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 80)

    guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return [] }

    var times: [NSValue] = []
    for i in 0..<count {
        let t = duration.seconds * Double(i) / Double(max(count - 1, 1))
        times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
    }

    var images: [UIImage] = Array(repeating: UIImage(), count: count)
    await withTaskGroup(of: (Int, UIImage?).self) { group in
        for (index, timeValue) in times.enumerated() {
            group.addTask {
                let cgImage = try? await generator.image(at: timeValue.timeValue).image
                return (index, cgImage.map { UIImage(cgImage: $0) })
            }
        }
        for await (index, image) in group {
            if let image { images[index] = image }
        }
    }
    return images
}

// MARK: - TrimRangeBar

private struct TrimRangeBar: View {
    let thumbnails: [UIImage]
    let duration: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    var onSeek: (Double) -> Void

    private let barHeight: CGFloat = 56
    private let handleWidth: CGFloat = 20
    private let cornerRadius: CGFloat = 8
    private let minClipSeconds: Double = 1.0

    private enum DragTarget { case start, end }
    @State private var dragTarget: DragTarget? = nil
    @State private var barWidth: CGFloat = 0

    private var usable: CGFloat { max(barWidth - handleWidth, 1) }

    private func xForTime(_ t: Double) -> CGFloat {
        handleWidth / 2 + CGFloat(t / duration) * usable
    }

    private func timeForX(_ x: CGFloat) -> Double {
        Double((x - handleWidth / 2) / usable) * duration
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let _ = DispatchQueue.main.async { if barWidth != w { barWidth = w } }

            ZStack(alignment: .leading) {
                // Filmstrip
                filmstripView(width: w)

                // Overlay canvas: dims + yellow border
                Canvas { ctx, size in
                    let lx = xForTime(startTime) - handleWidth / 2
                    let rx = xForTime(endTime)   + handleWidth / 2
                    let h  = size.height
                    let cr = cornerRadius
                    let dimColor    = Color.black.opacity(0.55)
                    let borderColor = Color.yellow
                    let borderT: CGFloat = 3

                    if lx > 0 {
                        ctx.fill(
                            Path(roundedRect: CGRect(x: 0, y: 0, width: lx, height: h),
                                 cornerSize: CGSize(width: cr, height: cr)),
                            with: .color(dimColor)
                        )
                    }
                    if rx < size.width {
                        ctx.fill(
                            Path(roundedRect: CGRect(x: rx, y: 0, width: size.width - rx, height: h),
                                 cornerSize: CGSize(width: cr, height: cr)),
                            with: .color(dimColor)
                        )
                    }
                    ctx.fill(Path(CGRect(x: lx, y: 0, width: rx - lx, height: borderT)),
                             with: .color(borderColor))
                    ctx.fill(Path(CGRect(x: lx, y: h - borderT, width: rx - lx, height: borderT)),
                             with: .color(borderColor))
                }
                .allowsHitTesting(false)

                // Left handle
                handle(systemImage: "chevron.compact.left")
                    .position(x: xForTime(startTime), y: barHeight / 2)
                    .allowsHitTesting(false)

                // Right handle
                handle(systemImage: "chevron.compact.right")
                    .position(x: xForTime(endTime), y: barHeight / 2)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let currentW = w
                        let currentUsable = max(currentW - handleWidth, 1)
                        if dragTarget == nil {
                            let sx = handleWidth / 2 + CGFloat(startTime / duration) * currentUsable
                            let ex = handleWidth / 2 + CGFloat(endTime   / duration) * currentUsable
                            let distStart = abs(value.startLocation.x - sx)
                            let distEnd   = abs(value.startLocation.x - ex)
                            dragTarget = distStart <= distEnd ? .start : .end
                        }
                        let fraction = (value.location.x - handleWidth / 2) / currentUsable
                        let t = Double(fraction) * duration
                        switch dragTarget {
                        case .start:
                            startTime = t.clamped(to: 0...(endTime - minClipSeconds))
                            onSeek(startTime)
                        case .end:
                            endTime = t.clamped(to: (startTime + minClipSeconds)...duration)
                            onSeek(endTime)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in dragTarget = nil }
            )
        }
        .frame(height: barHeight)
    }

    // MARK: Filmstrip

    @ViewBuilder
    private func filmstripView(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(thumbnails.count), height: barHeight)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width, height: barHeight)
    }

    // MARK: Handle

    @ViewBuilder
    private func handle(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.yellow)
                .frame(width: handleWidth, height: barHeight)
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
        }
    }
}

// MARK: - AVAssetExportSession Trim

private func trimVideo(
    sourceURL: URL,
    outputURL: URL,
    startSeconds: Double,
    endSeconds: Double
) async throws -> URL {
    let asset = AVAsset(url: sourceURL)

    guard let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetHighestQuality
    ) else {
        throw TrimError.exportSessionCreationFailed
    }

    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mov
    exportSession.timeRange = CMTimeRange(
        start: CMTime(seconds: startSeconds, preferredTimescale: 600),
        end: CMTime(seconds: endSeconds, preferredTimescale: 600)
    )

    await exportSession.export()

    guard exportSession.status == .completed else {
        throw exportSession.error ?? TrimError.exportFailed
    }

    return outputURL
}

private enum TrimError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed: return "Could not create export session."
        case .exportFailed: return "Export session finished with an unknown error."
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
