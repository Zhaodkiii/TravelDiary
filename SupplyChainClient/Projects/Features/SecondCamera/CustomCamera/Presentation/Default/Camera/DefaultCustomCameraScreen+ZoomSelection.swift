import SwiftUI
import AVFoundation

extension DefaultCustomCameraScreen {
    struct ZoomSelection: View {
        let parent: DefaultCustomCameraScreen

        var body: some View {
            HStack(spacing: 4) {
                ForEach(parent.availableZoomPresets) { preset in
                    ZoomButton(
                        preset: preset,
                        isSelected: isPresetSelected(preset),
                        currentDisplayZoomFactor: parent.displayZoomFactor,
                        rotationAngle: parent.iconAngle,
                        action: { try? parent.setZoomPreset(preset) }
                    )
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.25))
            .clipShape(Capsule())
        }

        private func isPresetSelected(_ preset: CameraZoomPreset) -> Bool {
            parent.selectedZoomPreset?.id == preset.id
        }
    }
}

private extension DefaultCustomCameraScreen.ZoomSelection {
    struct ZoomButton: View {
        let preset: CameraZoomPreset
        let isSelected: Bool
        let currentDisplayZoomFactor: CGFloat
        let rotationAngle: Angle
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(.system(size: isSelected ? 20 : 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: isSelected ? 56 : 40, height: isSelected ? 56 : 40)
                    .background(Color.black.opacity(isSelected ? 0.55 : 0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(ButtonScaleStyle())
            .rotationEffect(rotationAngle)
        }

        private var label: String {
            CameraZoomPreset.zoomLabel(
                displayZoomFactor: preset.displayZoomFactor,
                currentDisplayZoomFactor: currentDisplayZoomFactor,
                isSelected: isSelected
            )
        }
    }
}

private extension DefaultCustomCameraScreen {
    var displayZoomFactor: CGFloat {
        cameraManager.displayZoomFactor(for: zoomFactor)
    }

    var selectedZoomPreset: CameraZoomPreset? {
        cameraManager.selectedZoomPreset(for: zoomFactor)
    }
}
