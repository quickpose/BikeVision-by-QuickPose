// SidePickerView.swift
// BikeVision
//
// Lets the user pick which side of the cyclist is visible to the camera.
// Calls onContinue(side) when the user taps Continue — the parent
// ContentView decides what to push onto the navigation stack next.

import SwiftUI

struct SidePickerView: View {
    let flow: SessionFlow
    /// Called with the selected side when the user taps the continue button.
    var onContinue: (CyclingSide) -> Void

    @State private var selectedSide: CyclingSide = .right

    var body: some View {
        VStack(spacing: 0) {
            // Instruction header
            VStack(spacing: 8) {
                Text("Which side is visible?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Position the camera so the full cyclist is in frame,\nthen choose which side of the body faces the lens.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Side selection cards
            VStack(spacing: 16) {
                ForEach(CyclingSide.allCases) { side in
                    SideOptionCard(
                        side: side,
                        isSelected: selectedSide == side
                    ) {
                        selectedSide = side
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Direction of travel diagram
            DirectionDiagram(side: selectedSide)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Continue button
            Button {
                onContinue(selectedSide)
            } label: {
                Label(
                    flow == .record ? "Start Recording" : "Analyse Video",
                    systemImage: flow == .record ? "record.circle" : "waveform.badge.magnifyingglass"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationTitle("Camera Side")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Side Option Card

private struct SideOptionCard: View {
    let side: CyclingSide
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                        .frame(width: 44, height: 44)
                    Image(systemName: side.systemImage)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(side.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(side.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color(.separator).opacity(0.5),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Direction Diagram

/// Simple schematic showing the direction of cyclist travel relative to the camera.
private struct DirectionDiagram: View {
    let side: CyclingSide

    var body: some View {
        HStack(spacing: 0) {
            if side == .right {
                cameraIcon
                Spacer()
                cyclistIcon(facingLeft: false)
                directionArrow(pointingRight: true)
            } else {
                cameraIcon
                Spacer()
                directionArrow(pointingRight: false)
                cyclistIcon(facingLeft: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var cameraIcon: some View {
        VStack(spacing: 4) {
            Image(systemName: "video.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("Camera")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func cyclistIcon(facingLeft: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.title2)
                .foregroundStyle(.primary)
                .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            Text("Cyclist")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func directionArrow(pointingRight: Bool) -> some View {
        Image(systemName: pointingRight ? "arrow.right" : "arrow.left")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }
}
