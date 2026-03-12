// UploadFlowView.swift
// BikeVision
//
// Manages the four-step upload flow as horizontal pages:
//   1. Pick Video  2. Trim  3. Side  4. Processing
// Uses a TabView with PageTabViewStyle so each step slides in from the right.
// Calls onComplete(session) when processing finishes, or onCancel() to go home.

import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Upload Step

private enum UploadStep: Int, CaseIterable {
    case pick = 0, trim, processing
}

// MARK: - UploadFlowView

struct UploadFlowView: View {
    var onComplete: (BikeSession) -> Void
    var onCancel: () -> Void

    @State private var step: UploadStep = .pick
    @State private var videoURL: URL?
    @State private var trimmedURL: URL?
    @State private var selectedSide: CyclingSide = .right

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    pickPage
                        .frame(width: w)
                        .offset(x: CGFloat(UploadStep.pick.rawValue - step.rawValue) * w)

                    Group {
                        if step == .trim, let url = videoURL {
                            TrimView(videoURL: url, selectedSide: $selectedSide) { trimmed in
                                trimmedURL = trimmed
                                advance(to: .processing)
                            }
                        } else if step != .trim {
                            Color.clear
                        }
                    }
                    .frame(width: w)
                    .offset(x: CGFloat(UploadStep.trim.rawValue - step.rawValue) * w)

                    Group {
                        if step == .processing, let url = trimmedURL ?? videoURL {
                            ProcessingView(videoURL: url, side: selectedSide) { session in
                                onComplete(session)
                            }
                        } else if step != .processing {
                            Color.clear
                        }
                    }
                    .frame(width: w)
                    .offset(x: CGFloat(UploadStep.processing.rawValue - step.rawValue) * w)
                }
                .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step != .pick)
        .toolbar {
            if step == .trim {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
    }

    // MARK: Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(UploadStep.allCases, id: \.rawValue) { s in
                let isCurrent = s == step
                let isDone    = s.rawValue < step.rawValue

                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(isDone ? Color.accentColor : isCurrent ? Color.accentColor : Color(.tertiarySystemBackground))
                            .frame(width: 28, height: 28)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(s.rawValue + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(isCurrent ? .white : .secondary)
                        }
                    }

                    if s != UploadStep.allCases.last {
                        Rectangle()
                            .fill(isDone ? Color.accentColor : Color(.separator))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: Pick Page

    private var pickPage: some View {
        PickVideoPage(onPicked: { url in
            videoURL = url
            trimmedURL = nil
            advance(to: .trim)
        }, onCancel: onCancel)
    }

    // MARK: Navigation

    private func advance(to next: UploadStep) {
        withAnimation(.easeInOut(duration: 0.35)) {
            step = next
        }
    }

    private func goBack() {
        guard let prev = UploadStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            step = prev
        }
    }
}

// MARK: - UploadStep helpers

private extension UploadStep {
    var title: String {
        switch self {
        case .pick:       return "Pick Video"
        case .trim:       return "Trim & Side"
        case .processing: return "Analysing…"
        }
    }
}

// MARK: - Pick Video Page

private struct PickVideoPage: View {
    var onPicked: (URL) -> Void
    var onCancel: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.indigo)

            VStack(spacing: 8) {
                Text("Select a Cycling Video")
                    .font(.title2.bold())
                Text("Choose a video from your library that shows\nthe cyclist from the side.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(
                selection: $photoItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Choose from Library", systemImage: "photo.stack")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 32)
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                loadVideo(from: item)
            }

            if isLoading {
                ProgressView("Loading video…")
            }

            if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
    }

    private func loadVideo(from item: PhotosPickerItem) {
        isLoading = true
        loadError = nil

        Task {
            do {
                guard let movie = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                    await MainActor.run {
                        loadError = "Could not load the selected video."
                        isLoading = false
                    }
                    return
                }
                await MainActor.run {
                    isLoading = false
                    onPicked(movie.url)
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load video: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Transferable Wrapper

private struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let destination = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoFileTransferable(url: destination)
        }
    }
}
