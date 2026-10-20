import SwiftUI
import UIKit

/// Native interactive movement distinguishes horizontal scrolling from long press,
/// and scrolls at the edges while dragging. IDs stay scoped to this editor object.
struct DiaryLayerThumbnailRail: UIViewRepresentable {
    @ObservedObject var session: DiaryEditorSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 76, height: 84)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 3, left: 20, bottom: 3, right: 20)
        let view = RailCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false
        view.register(Cell.self, forCellWithReuseIdentifier: "layer")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        view.addGestureRecognizer(press)
        context.coordinator.collection = view
        view.onResize = { [weak coordinator = context.coordinator] in coordinator?.centerSelection() }
        return view
    }
    func updateUIView(_ view: UICollectionView, context: Context) { context.coordinator.update() }
    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        view.cancelInteractiveMovement()
        coordinator.cancelMovement()
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        let session: DiaryEditorSession
        weak var collection: UICollectionView?
        private var layers: [DiaryLayer] = []
        private let cache = DiaryCanvasRenderCache()
        private var generation: UInt64?
        private var selected: UUID?
        private var selectedPosition: Int?
        private var moving = false
        init(session: DiaryEditorSession) { self.session = session }

        func update() {
            guard let collection, !moving else { return }
            if generation != session.renderGeneration {
                generation = session.renderGeneration
                layers = session.scopeLayers
                // Hidden/transparent layers remain recognizable and selectable in the rail.
                var document = session.document
                for index in layers.indices {
                    document.objects[session.contentID]?.layers[index].visible = true
                    document.objects[session.contentID]?.layers[index].opacity = nil
                }
                cache.synchronize(document: document, images: session.images, contentID: session.contentID)
                collection.reloadData()
            } else {
                for case let cell as Cell in collection.visibleCells {
                    if let index = collection.indexPath(for: cell)?.item, layers.indices.contains(index) {
                        configure(cell, layer: layers[index])
                    }
                }
            }
            let position = layers.firstIndex(where: { $0.id == session.selectedID })
            if selected != session.selectedID || selectedPosition != position {
                selected = session.selectedID
                selectedPosition = position
                if position != nil {
                    centerSelection()
                }
            }
        }
        func centerSelection() {
            guard !moving, let collection, collection.bounds.width > 0,
                  let index = layers.firstIndex(where: { $0.id == session.selectedID }) else { return }
            collection.layoutIfNeeded()
            guard let attributes = collection.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
            // Explicit positioning includes our leading/trailing centering space.
            collection.setContentOffset(CGPoint(x: attributes.center.x - collection.bounds.width / 2,
                                                y: collection.contentOffset.y), animated: false)
        }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { layers.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "layer", for: indexPath) as! Cell
            configure(cell, layer: layers[indexPath.item])
            return cell
        }
        private func configure(_ cell: Cell, layer: DiaryLayer) {
            if let entry = cache.entries[layer.id] {
                entry.requestedScale = min(2, 152 / max(1, max(entry.rect.width, entry.rect.height)))
                cache.rasterize(entry)
                cell.image.image = entry.image
            } else { cell.image.image = nil }
            cell.label.text = layer.name
            cell.badge.text = [layer.visible ? nil : "隐藏", layer.locked ? "锁定" : nil].compactMap { $0 }.joined(separator: " · ")
            cell.image.alpha = layer.visible ? 1 : 0.45
            cell.showSelection(session.selectedID == layer.id)
            cell.setNeedsLayout()
            cell.accessibilityLabel = "\(layer.name)\(layer.visible ? "" : "，已隐藏")\(layer.locked ? "，已锁定" : "")"
            cell.accessibilityTraits = session.selectedID == layer.id ? [.button, .selected] : [.button]
        }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            session.select(layers[indexPath.item].id)
        }
        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            !layers[indexPath.item].locked && !layers[indexPath.item].isPhotoFrame
        }
        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            let layer = layers.remove(at: sourceIndexPath.item)
            layers.insert(layer, at: destinationIndexPath.item)
            session.previewLayerOrder(layer.id, to: destinationIndexPath.item)
            session.finishInteraction()
        }
        func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                            toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
            session.previewLayerOrder(layers[originalIndexPath.item].id, to: proposedIndexPath.item)
            return proposedIndexPath
        }
        func cancelMovement() {
            if moving { session.cancelInteraction() }
            moving = false
        }
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collection else { return }
            switch gesture.state {
            case .began:
                guard let index = collection.indexPathForItem(at: gesture.location(in: collection)),
                      self.collectionView(collection, canMoveItemAt: index) else { return }
                session.select(layers[index.item].id)
                moving = collection.beginInteractiveMovementForItem(at: index)
            case .changed:
                if moving { collection.updateInteractiveMovementTargetPosition(gesture.location(in: collection)) }
            case .ended:
                if moving { collection.endInteractiveMovement() }
                session.finishInteraction()
                moving = false
                update()
            case .cancelled, .failed:
                collection.cancelInteractiveMovement()
                cancelMovement()
                update()
            default: break
            }
        }
    }

    final class RailCollectionView: UICollectionView {
        var onResize: (() -> Void)?
        private var previousSize = CGSize.zero
        override func layoutSubviews() {
            let resized = previousSize != bounds.size
            previousSize = bounds.size
            if resized, let layout = collectionViewLayout as? UICollectionViewFlowLayout {
                let side = max(20, (bounds.width - layout.itemSize.width) / 2)
                layout.sectionInset = UIEdgeInsets(top: 3, left: side, bottom: 3, right: side)
            }
            super.layoutSubviews()
            if resized { onResize?() }
        }
    }

    final class Cell: UICollectionViewCell {
        let image = UIImageView()
        let label = UILabel()
        let badge = UILabel()
        private let selectionBorder = UIView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 10
            contentView.clipsToBounds = true
            contentView.backgroundColor = UIColor(patternImage: Self.checker)
            image.contentMode = .scaleAspectFit
            label.font = .systemFont(ofSize: 10)
            label.textAlignment = .center
            label.backgroundColor = .secondarySystemBackground
            badge.font = .systemFont(ofSize: 9, weight: .semibold)
            badge.textAlignment = .center
            badge.textColor = .white
            badge.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            selectionBorder.isUserInteractionEnabled = false
            selectionBorder.layer.cornerRadius = 10
            selectionBorder.layer.borderWidth = 3
            selectionBorder.layer.borderColor = UIColor.systemPurple.cgColor
            [image, label, badge, selectionBorder].forEach { contentView.addSubview($0) }
            isAccessibilityElement = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func showSelection(_ selected: Bool) {
            selectionBorder.isHidden = !selected
            label.textColor = selected ? .systemPurple : .label
            label.font = .systemFont(ofSize: 10, weight: selected ? .semibold : .regular)
            contentView.layer.borderWidth = selected ? 0 : 1
            contentView.layer.borderColor = UIColor.separator.cgColor
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            selectionBorder.frame = contentView.bounds
            image.frame = CGRect(x: 4, y: 4, width: bounds.width - 8, height: bounds.height - 24)
            label.frame = CGRect(x: 3, y: bounds.height - 19, width: bounds.width - 6, height: 16)
            badge.frame = CGRect(x: 3, y: 3, width: bounds.width - 6, height: badge.text?.isEmpty == false ? 14 : 0)
        }
        private static let checker: UIImage = {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { _ in
                UIColor.systemBackground.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 16))
                UIColor.systemGray5.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: 8, height: 8))
                UIRectFill(CGRect(x: 8, y: 8, width: 8, height: 8))
            }
        }()
    }
}
