import SwiftUI
import UIKit

/// Uses the editor's renderer, so frames, crops, typography and source z-order match the sample book.
@MainActor
struct DiaryOnboardingArtwork {
    struct Piece: Identifiable {
        let id: UUID
        let image: UIImage
        let bounds: CGRect
        let stage: Int
        let order: Int
        let label: String
    }
    let size: CGSize
    let pieces: [Piece]

    private struct Scene: Decodable {
        let rootContentID: UUID
        let objects: [DiaryObjectContent]
        let assets: [DiaryAsset]
    }

    static func load() async throws -> Self {
        guard let url = Bundle.main.url(forResource: "DiaryOnboarding", withExtension: "bundle") else {
            throw DiaryEditorError.missingResource
        }
        let scene = try JSONDecoder().decode(Scene.self, from: Data(contentsOf: url.appendingPathComponent("scene.json")))
        let objects = Dictionary(uniqueKeysWithValues: scene.objects.map { ($0.id, $0) })
        guard let root = objects[scene.rootContentID] else { throw DiaryEditorError.invalidDocument }
        let assets = Dictionary(uniqueKeysWithValues: scene.assets.map { ($0.id, $0) })
        var images: [UUID: UIImage] = [:]
        for asset in scene.assets {
            guard let image = UIImage(contentsOfFile: url.appendingPathComponent(asset.path).path) else {
                throw DiaryEditorError.missingResource
            }
            images[asset.id] = image
            await Task.yield()
            try Task.checkCancellation()
        }
        var document = DiaryDocument(id: UUID(), title: "雨崩，慢一点", rootContentID: root.id, assets: assets, objects: objects)
        var pieces: [Piece] = []
        var counts: [Int: Int] = [:]
        for layer in root.layers where layer.visible {
            let role = layer.contentID.flatMap { objects[$0]?.role } ?? layer.kind
            let stage = layer.semanticKind == .background ? 1 : role == .photo ? 2 : role == .text ? 4 : 3
            let bounds = DiaryPageRenderer.bounds(layer, document: document, siblings: root.layers)
                .applying(layer.transform.matrix).insetBy(dx: -12, dy: -12)
                .intersection(CGRect(origin: .zero, size: root.referenceSize))
            guard !bounds.isEmpty, !bounds.isNull else { continue }
            var isolated = root
            isolated.background = nil
            isolated.layers = [layer]
            document.objects[root.id] = isolated
            let scale: CGFloat = 0.44
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale)), format: format).image { renderer in
                renderer.cgContext.scaleBy(x: scale, y: scale)
                renderer.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                DiaryPageRenderer.draw(document, images: images, in: renderer.cgContext, includeInk: false, cacheObjects: false)
            }
            let order = counts[stage, default: 0]
            counts[stage] = order + 1
            pieces.append(Piece(id: layer.id, image: image, bounds: bounds, stage: stage, order: order, label: layer.name))
            document.objects[root.id] = root
            await Task.yield()
            try Task.checkCancellation()
        }
        return Self(size: root.referenceSize, pieces: pieces)
    }
}

/// Alternating brush sweeps reveal the supplied background rather than fading it in.
nonisolated struct DiaryOnboardingBrushMask: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 12
        for row in 0..<rows {
            let fraction = min(1, max(0, progress * CGFloat(rows) - CGFloat(row)))
            let height = rect.height / CGFloat(rows)
            let width = rect.width * fraction
            path.addRoundedRect(in: CGRect(x: row.isMultiple(of: 2) ? 0 : rect.width - width,
                                           y: CGFloat(row) * height - 2, width: width, height: height + 4),
                                cornerSize: CGSize(width: 5, height: 5))
        }
        return path
    }
}
