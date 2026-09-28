import Combine
import Foundation
import UIKit

/// 公共只读预览会话状态：只允许选择与按需加载，不提供增删改 API。
@MainActor
final class SecondCameraReadOnlyPreviewStore: ObservableObject {
    @Published private(set) var items: [SecondCameraReadOnlyPreviewItem]
    @Published private(set) var selectedID: UUID?

    private let loader: any SecondCameraPreviewImageLoading
    private var fullImageTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    private var fullImageRequestIDs: [UUID: UUID] = [:]
    private var thumbnailRequestIDs: [UUID: UUID] = [:]

    init(
        inputs: [SecondCameraMediaPreviewInput],
        selectedID: UUID?,
        loader: any SecondCameraPreviewImageLoading = SecondCameraPreviewImageLoader.shared
    ) {
        self.items = inputs.map { input in
            SecondCameraReadOnlyPreviewItem(
                id: input.id,
                fileURL: input.fileURL,
                displayName: input.resolvedDisplayName
            )
        }
        self.loader = loader

        if let selectedID, self.items.contains(where: { $0.id == selectedID }) {
            self.selectedID = selectedID
        } else {
            self.selectedID = self.items.first?.id
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "Public media preview opened count=\(self.items.count) selectedFound=\(self.selectedID != nil)"
        )

        if selectedID != nil, self.selectedID != selectedID {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "Public media preview selectedID missing, fallback to first"
            )
        }
    }

    var selectedItem: SecondCameraReadOnlyPreviewItem? {
        guard let selectedID else { return nil }
        return items.first(where: { $0.id == selectedID })
    }

    var selectedDisplayItem: SecondCameraMediaPreviewDisplayItem? {
        selectedItem?.displayItem
    }

    func select(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        guard selectedID != id else {
            loadSelectedIfNeeded()
            return
        }
        selectedID = id
        cancelDistantFullImageLoads(keepingNeighborOf: id)
        loadSelectedIfNeeded()
        prefetchNeighbors()
    }

    func loadSelectedIfNeeded() {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return }
        if item.loadState == .loaded, item.image != nil { return }
        if item.loadState == .loading, fullImageTasks[selectedID] != nil { return }
        startFullImageLoad(for: selectedID)
        if item.thumbnail == nil {
            startThumbnailLoad(for: selectedID)
        }
    }

    func prefetchNeighbors() {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID })
        else { return }

        let neighborIndexes = [index - 1, index + 1].filter { items.indices.contains($0) }
        for neighborIndex in neighborIndexes {
            let neighborID = items[neighborIndex].id
            if items[neighborIndex].thumbnail == nil {
                startThumbnailLoad(for: neighborID)
            }
        }
    }

    func cancelOutstandingLoads() {
        for task in fullImageTasks.values {
            task.cancel()
        }
        for task in thumbnailTasks.values {
            task.cancel()
        }
        fullImageTasks.removeAll()
        thumbnailTasks.removeAll()
        fullImageRequestIDs.removeAll()
        thumbnailRequestIDs.removeAll()
    }

    private func startFullImageLoad(for id: UUID) {
        fullImageTasks[id]?.cancel()
        let requestID = UUID()
        fullImageRequestIDs[id] = requestID

        updateItem(id: id) { item in
            if item.image == nil {
                item.loadState = .loading
            }
        }

        let fileURL = items.first(where: { $0.id == id })?.fileURL
        let maxPixelSize = SecondCameraPreviewImageSizePolicy.previewMaxPixelSize
        guard let fileURL else { return }

        fullImageTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.loader.loadPreviewImage(from: fileURL, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                guard self.fullImageRequestIDs[id] == requestID else { return }
                self.updateItem(id: id) { item in
                    item.image = image
                    item.loadState = .loaded
                    item.revision += 1
                    if item.thumbnail == nil {
                        item.thumbnail = SecondCameraPreviewThumbnailBuilder.makeThumbnail(from: image)
                    }
                }
            } catch let error as SecondCameraMediaPreviewLoadError {
                guard !Task.isCancelled else { return }
                guard self.fullImageRequestIDs[id] == requestID else { return }
                if error == .cancelled { return }
                SparkLogger.log(
                    level: .info,
                    module: .camera,
                    message: "Public media preview decode failed code=\(error.logCode) ext=\(fileURL.pathExtension)"
                )
                self.updateItem(id: id) { item in
                    item.loadState = .failed(error)
                    item.revision += 1
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard self.fullImageRequestIDs[id] == requestID else { return }
                SparkLogger.log(
                    level: .info,
                    module: .camera,
                    message: "Public media preview decode failed code=unknown ext=\(fileURL.pathExtension)"
                )
                self.updateItem(id: id) { item in
                    item.loadState = .failed(.cannotDecodeImage)
                    item.revision += 1
                }
            }
            self.fullImageTasks[id] = nil
        }
    }

    private func startThumbnailLoad(for id: UUID) {
        guard items.contains(where: { $0.id == id && $0.thumbnail == nil }) else { return }
        if thumbnailTasks[id] != nil { return }

        thumbnailTasks[id]?.cancel()
        let requestID = UUID()
        thumbnailRequestIDs[id] = requestID

        let fileURL = items.first(where: { $0.id == id })?.fileURL
        let maxPixelSize = SecondCameraPreviewImageSizePolicy.thumbnailMaxPixelSize
        guard let fileURL else { return }

        thumbnailTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.loader.loadThumbnail(from: fileURL, maxPixelSize: maxPixelSize)
                guard !Task.isCancelled else { return }
                guard self.thumbnailRequestIDs[id] == requestID else { return }
                self.updateItem(id: id) { item in
                    item.thumbnail = image
                }
            } catch {
                // 缩略图失败保留占位，仍允许选择查看大图错误态。
            }
            self.thumbnailTasks[id] = nil
        }
    }

    private func cancelDistantFullImageLoads(keepingNeighborOf selectedID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        let keepIDs = Set(
            [index - 1, index, index + 1]
                .filter { items.indices.contains($0) }
                .map { items[$0].id }
        )
        for (id, task) in fullImageTasks where keepIDs.contains(id) == false {
            task.cancel()
            fullImageTasks[id] = nil
            fullImageRequestIDs[id] = nil
        }
    }

    private func updateItem(id: UUID, mutate: (inout SecondCameraReadOnlyPreviewItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        mutate(&item)
        items[index] = item
    }
}
