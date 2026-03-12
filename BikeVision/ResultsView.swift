// ResultsView.swift
// BikeVision
//
// Displays the annotated output video (upload flow) or a summary banner
// (live flow), plus per-joint angle statistics cards.
// Calls onDone() when the user taps "Done" to pop back to the home screen.

import SwiftUI
import AVKit

struct ResultsView: View {
    let session: BikeSession
    /// Called when the user taps Done — ContentView pops the entire stack.
    var onDone: () -> Void

    @State private var player: AVPlayer?

    /// True when the annotated video file actually exists on disk.
    private var hasVideoFile: Bool {
        FileManager.default.fileExists(atPath: session.annotatedVideoURL.path)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                videoSection
                SummaryHeader(side: session.side, statCount: session.stats.count)

                if session.stats.isEmpty {
                    ContentUnavailableView(
                        "No Data Collected",
                        systemImage: "waveform.slash",
                        description: Text("No joint angles were recorded. Ensure the cyclist was fully visible during the session.")
                    )
                    .padding(.top, 32)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(session.stats) { stat in
                            JointStatCard(stat: stat)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    onDone()
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - Video Section

    @ViewBuilder
    private var videoSection: some View {
        if hasVideoFile, let avPlayer = player {
            VideoPlayer(player: avPlayer)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .overlay(alignment: .bottomTrailing) {
                    Text("Annotated by QuickPose")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(20)
                }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No annotated video for live sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if hasVideoFile {
                ShareLink(item: session.annotatedVideoURL) {
                    Label("Share Annotated Video", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Button {
                onDone()
            } label: {
                Text("New Session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard hasVideoFile else { return }
        let avPlayer = AVPlayer(url: session.annotatedVideoURL)
        player = avPlayer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }
        avPlayer.play()
    }
}

// MARK: - Summary Header

private struct SummaryHeader: View {
    let side: CyclingSide
    let statCount: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.green)
                Text("Analysis Complete")
                    .font(.headline)
            }
            Text("\(statCount) joint\(statCount == 1 ? "" : "s") measured · \(side.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Joint Stat Card

private struct JointStatCard: View {
    let stat: JointStat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stat.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                StatRow(label: "Min", value: stat.minString, color: .blue)
                StatRow(label: "Max", value: stat.maxString, color: .orange)
                Divider()
                StatRow(label: "ROM", value: stat.romString, color: .green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
