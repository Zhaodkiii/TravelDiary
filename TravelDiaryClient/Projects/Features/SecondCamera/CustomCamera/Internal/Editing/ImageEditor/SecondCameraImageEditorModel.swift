//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


import UIKit
// Used to represent undo/redo operations.
//
// Because the image editor's "contents" and "items"
// are immutable, these operations simply take a
// snapshot of the current contents which can be used
// (multiple times) to preserve/restore editor state.
private class SecondCameraImageEditorOperation: NSObject {

    let operationId: String

    let contents: SecondCameraImageEditorContents

    init(contents: SecondCameraImageEditorContents) {
        self.operationId = UUID().uuidString
        self.contents = contents
    }
}

// MARK: -

protocol SecondCameraImageEditorModelObserver: AnyObject {
    // Used for large changes to the model, when the entire
    // model should be reloaded.
    func secondCameraImageEditorModelDidChange(
        before: SecondCameraImageEditorContents,
        after: SecondCameraImageEditorContents,
    )

    // Used for small narrow changes to the model, usually
    // to a single item.
    func secondCameraImageEditorModelDidChange(changedItemIds: [String])
}

// MARK: -

class SecondCameraImageEditorModel: NSObject {

    let srcImage: SecondCameraNormalizedImage
    let srcImageSizePixels: CGSize
    let srcSecondCameraEditorImageMetadata: SecondCameraEditorImageMetadata

    private var contents: SecondCameraImageEditorContents

    private var transform: SecondCameraImageEditorTransform

    private var undoStack = [SecondCameraImageEditorOperation]()
    private var redoStack = [SecondCameraImageEditorOperation]()

    typealias StickerImageCache = SecondCameraEditorLRUCache<String, SecondCameraEditorThreadSafeCacheHandle<UIImage>>
    var stickerViewCache = StickerImageCache(maxSize: 16, shouldEvacuateInBackground: true)

    var blurredSourceImage: CGImage?

    var color = SecondCameraColorPickerBarColor.defaultColor()

    init(normalizedImage: SecondCameraNormalizedImage) throws {
        self.srcImage = normalizedImage
        let srcSecondCameraEditorImageMetadata = try normalizedImage.dataSource.imageSource().imageMetadata()
        guard let srcSecondCameraEditorImageMetadata else {
            throw SecondCameraImageEditorError.invalidInput
        }
        self.srcSecondCameraEditorImageMetadata = srcSecondCameraEditorImageMetadata
        let srcImageSizePixels = srcSecondCameraEditorImageMetadata.pixelSize
        guard srcImageSizePixels.width > 0, srcImageSizePixels.height > 0 else {
            throw SecondCameraImageEditorError.invalidInput
        }
        self.srcImageSizePixels = srcImageSizePixels

        self.contents = SecondCameraImageEditorContents()
        self.transform = SecondCameraImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)

        super.init()
    }

    @MainActor
    func renderOutput() -> UIImage? {
        return SecondCameraImageEditorCanvasView.renderForOutput(model: self, transform: currentTransform())
    }

    func currentTransform() -> SecondCameraImageEditorTransform {
        return transform
    }

    func isDirty() -> Bool {
        if itemCount() > 0 {
            return true
        }
        return transform != SecondCameraImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)
    }

    func itemCount() -> Int {
        return contents.itemCount()
    }

    func items() -> [SecondCameraImageEditorItem] {
        return contents.items()
    }

    func itemIds() -> [String] {
        return contents.itemIds()
    }

    func has(itemForId itemId: String) -> Bool {
        return item(forId: itemId) != nil
    }

    func item(forId itemId: String) -> SecondCameraImageEditorItem? {
        return contents.item(forId: itemId)
    }

    func canUndo() -> Bool {
        return !undoStack.isEmpty
    }

    func canRedo() -> Bool {
        return !redoStack.isEmpty
    }

    func currentUndoOperationId() -> String? {
        guard let operation = undoStack.last else {
            return nil
        }
        return operation.operationId
    }

    // MARK: - Observers

    private var observers = [SecondCameraEditorWeak<SecondCameraImageEditorModelObserver>]()

    func add(observer: SecondCameraImageEditorModelObserver) {
        observers.append(SecondCameraEditorWeak(value: observer))
    }

    private func fireModelDidChange(
        before: SecondCameraImageEditorContents,
        after: SecondCameraImageEditorContents,
    ) {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.secondCameraImageEditorModelDidChange(
                before: before,
                after: after,
            )
        }
    }

    private func fireModelDidChange(changedItemIds: [String]) {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.secondCameraImageEditorModelDidChange(changedItemIds: changedItemIds)
        }
    }

    // MARK: -

    func undo() {
        guard let undoOperation = undoStack.popLast() else {
            secondCameraEditorFailDebug("Cannot undo.")
            return
        }

        let redoOperation = SecondCameraImageEditorOperation(contents: contents)
        redoStack.append(redoOperation)

        let oldContents = self.contents
        self.contents = undoOperation.contents

        // We could diff here and yield a more narrow change event.
        fireModelDidChange(before: oldContents, after: self.contents)
    }

    func redo() {
        guard let redoOperation = redoStack.popLast() else {
            secondCameraEditorFailDebug("Cannot redo.")
            return
        }

        let undoOperation = SecondCameraImageEditorOperation(contents: contents)
        undoStack.append(undoOperation)

        let oldContents = self.contents
        self.contents = redoOperation.contents

        // We could diff here and yield a more narrow change event.
        fireModelDidChange(before: oldContents, after: self.contents)
    }

    func append(item: SecondCameraImageEditorItem) {
        performAction({ oldContents in
            let newContents = oldContents.clone()
            newContents.append(item: item)
            return newContents
        }, changedItemIds: [item.itemId])
    }

    func replace(
        item: SecondCameraImageEditorItem,
        suppressUndo: Bool = false,
    ) {
        performAction(
            { oldContents in
                let newContents = oldContents.clone()
                newContents.replace(item: item)
                return newContents
            },
            changedItemIds: [item.itemId],
            suppressUndo: suppressUndo,
        )
    }

    func remove(item: SecondCameraImageEditorItem) {
        performAction({ oldContents in
            let newContents = oldContents.clone()
            newContents.remove(item: item)
            return newContents
        }, changedItemIds: [item.itemId])
    }

    func replace(transform: SecondCameraImageEditorTransform) {
        self.transform = transform

        // The contents haven't changed, but this event prods the
        // observers to reload everything, which is necessary if
        // the transform changes.
        fireModelDidChange(before: self.contents, after: self.contents)
    }

    // MARK: - Temp Files

    private var temporaryFilePaths = [String]()

    func temporaryFilePath(fileExtension: String) -> String {
        SecondCameraEditorAssertIsOnMainThread()

        let filePath = SecondCameraEditorFileSystem.temporaryFilePath(
            fileExtension: fileExtension,
            isAvailableWhileDeviceLocked: false,
        )
        temporaryFilePaths.append(filePath)
        return filePath
    }

    deinit {
        SecondCameraEditorAssertIsOnMainThread()

        let temporaryFilePaths = self.temporaryFilePaths

        DispatchQueue.secondCameraEditor_sharedUtility.async {
            for filePath in temporaryFilePaths {
                do {
                    try SecondCameraEditorFileSystem.deleteFile(url: URL(fileURLWithPath: filePath))
                } catch {
                    SecondCameraEditorLogger.error("Could not delete temp file: \(filePath)")
                }
            }
        }
    }

    private func performAction(
        _ action: (SecondCameraImageEditorContents) -> SecondCameraImageEditorContents,
        changedItemIds: [String]?,
        suppressUndo: Bool = false,
    ) {
        if !suppressUndo {
            let undoOperation = SecondCameraImageEditorOperation(contents: contents)
            undoStack.append(undoOperation)
            redoStack.removeAll()
        }

        let oldContents = self.contents
        let newContents = action(oldContents)
        contents = newContents

        if let changedItemIds {
            fireModelDidChange(changedItemIds: changedItemIds)
        } else {
            fireModelDidChange(
                before: oldContents,
                after: self.contents,
            )
        }
    }
}
