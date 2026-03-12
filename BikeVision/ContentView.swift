// ContentView.swift
// BikeVision
//
// Home screen — entry point offering Record (live camera) and Upload (video file) flows.
// Uses a NavigationStack with a path so ResultsView can pop all the way back to home.

import SwiftUI

/// Destinations in the main navigation stack.
enum AppRoute: Hashable {
    case sidePicker(flow: SessionFlow)
    case liveCamera(side: CyclingSide)
    case uploadFlow
    case processing(videoURL: URL, side: CyclingSide)
    case results(session: BikeSession)
}

// MARK: - Hashable / Equatable conformances for route-associated types

extension SessionFlow: Hashable {
    static func == (lhs: SessionFlow, rhs: SessionFlow) -> Bool {
        switch (lhs, rhs) {
        case (.record, .record): return true
        case (.upload(let a), .upload(let b)): return a == b
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .record: hasher.combine(0)
        case .upload(let url): hasher.combine(1); hasher.combine(url)
        }
    }
}

extension BikeSession: Hashable {
    static func == (lhs: BikeSession, rhs: BikeSession) -> Bool {
        lhs.annotatedVideoURL == rhs.annotatedVideoURL
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(annotatedVideoURL)
    }
}

struct ContentView: View {
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            homeView
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
        }
    }

    // MARK: - Home View

    private var homeView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Hero header
                VStack(spacing: 8) {
                    Image(systemName: "figure.outdoor.cycle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .padding(.bottom, 4)
                    Text("BikeVision")
                        .font(.largeTitle.bold())
                    Text("Cycling Biomechanics Analysis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 56)
                .padding(.bottom, 48)

                // Action cards
                VStack(spacing: 20) {
                    Button {
                        path.append(.sidePicker(flow: .record))
                    } label: {
                        ActionCard(
                            title: "Record",
                            subtitle: "Analyse in real-time using the camera",
                            systemImage: "video.fill",
                            accentColor: .accentColor
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        path.append(.uploadFlow)
                    } label: {
                        ActionCard(
                            title: "Upload",
                            subtitle: "Select an existing cycling video",
                            systemImage: "photo.on.rectangle.angled",
                            accentColor: .indigo
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("Powered by QuickPose")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Route → View

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .sidePicker(let flow):
            SidePickerView(flow: flow, onContinue: { side in
                switch flow {
                case .record:
                    path.append(.liveCamera(side: side))
                case .upload(let url):
                    path.append(.processing(videoURL: url, side: side))
                }
            })

        case .liveCamera(let side):
            LiveCameraView(side: side, onComplete: { session in
                path.append(.results(session: session))
            })

        case .uploadFlow:
            UploadFlowView(
                onComplete: { session in
                    path.append(.results(session: session))
                },
                onCancel: {
                    path.removeAll()
                }
            )

        case .processing(let url, let side):
            ProcessingView(videoURL: url, side: side, onComplete: { session in
                path.append(.results(session: session))
            })

        case .results(let session):
            ResultsView(session: session, onDone: {
                path.removeAll()
            })
        }
    }
}

// MARK: - Action Card

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }
}

#Preview {
    ContentView()
}
