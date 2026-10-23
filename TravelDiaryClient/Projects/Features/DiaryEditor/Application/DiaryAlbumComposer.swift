import Foundation
import SwiftUI
import PhotosUI
import ImageIO
import CryptoKit

@MainActor @Observable
final class DiaryAlbumComposer {
    var draft = DiaryAlbumDraft()
    var busy = false
    private(set) var saving = false
    var progress = ""
    var message: String?
    var undoStack: [DiaryAlbumDraft] = []
    var redoStack: [DiaryAlbumDraft] = []
    let directory: URL
    let ownerID: String
    private var cancellation = DiaryPresetCancellation()
    private(set) var restored = false
    private var finished = false
    private var unreadableDraft = false

    init(ownerID: String, baseDirectory: URL? = nil) {
        self.ownerID = ownerID
        directory = (baseDirectory ?? StoragePaths.system.diaryOwner(ownerID)).appendingPathComponent("album-draft", isDirectory: true)
        let url = directory.appendingPathComponent("draft.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                draft = try JSONDecoder().decode(DiaryAlbumDraft.self, from: Data(contentsOf: url))
                restored = true
            } catch {
                unreadableDraft = true
                message = "上次草稿无法读取。请在整理照片中选择重新开始，旧草稿会保留备份。"
            }
        }
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func change(_ body: (inout DiaryAlbumDraft) -> Void) {
        guard !finished, !unreadableDraft else { return }
        let old = draft
        body(&draft)
        draft.normalizeSpreads()
        guard old != draft else { return }
        undoStack.append(old); if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll(); persist()
    }
    func undo() {
        guard let value = undoStack.popLast() else { return }
        redoStack.append(draft); draft = value; persist()
    }
    func redo() {
        guard let value = redoStack.popLast() else { return }
        undoStack.append(draft); draft = value; persist()
    }
    func persist() {
        guard !finished, !unreadableDraft else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("draft.json"), options: .atomic)
        } catch { message = "草稿暂未保存：" + error.localizedDescription }
    }
    func discard() {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                if unreadableDraft { try FileManager.default.moveItem(at: directory, to: directory.deletingLastPathComponent().appendingPathComponent("album-draft-backup-" + UUID().uuidString)) }
                else { try FileManager.default.removeItem(at: directory) }
            }
        }
        catch { message = error.localizedDescription; return }
        draft = DiaryAlbumDraft(); undoStack = []; redoStack = []; restored = false; unreadableDraft = false; finished = false
    }
    func removePhoto(_ id: UUID) {
        guard !draft.pages.contains(where: { $0.locked && $0.placements.contains(where: { $0.photoID == id }) }) else {
            message = "这张照片用于锁定页面，请先解锁该页。"; return
        }
        change { value in
            value.photos.removeAll { $0.id == id }
            for i in value.pages.indices { value.pages[i].placements.removeAll { $0.photoID == id } }
        }
    }
    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !busy, !unreadableDraft, !items.isEmpty else { return }
        busy = true; defer { busy = false }
        var imported: [DiaryAlbumPhoto] = []
        var fingerprints = Set(draft.photos.map(\.fingerprint))
        var failures = 0, duplicates = 0
        let start = (draft.photos.map(\.selectionOrder).max() ?? -1) + 1
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            progress = "正在读取照片 \(index + 1) / \(items.count)…"
            do {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                let folder = directory
                let photo = try await Task.detached(priority: .userInitiated) {
                    try Self.prepare(bytes, directory: folder, order: start + index)
                }.value
                if fingerprints.insert(photo.fingerprint).inserted { imported.append(photo) }
                else { duplicates += 1 }
            } catch { failures += 1 }
        }
        change { value in
            value.photos.append(contentsOf: imported)
            // 仅初次导入按拍摄时间排序；追加不会打乱用户已调整的顺序。
            if value.photos.count == imported.count { value.sortPhotos(byDate: true) }
        }
        if failures > 0 || duplicates > 0 {
            message = "已添加 \(imported.count) 张照片。" + (duplicates > 0 ? "已跳过 \(duplicates) 张重复照片。" : "")
                + (failures > 0 ? "\(failures) 张读取失败，请检查 iCloud 下载或重新选择；已读入的照片已保留。" : "")
        }
    }
    private nonisolated static func prepare(_ bytes: Data, directory: URL, order: Int) throws -> DiaryAlbumPhoto {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw DiaryEditorError.invalidImage }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swaps = (5...8).contains(orientation)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let file = digest + ".image"
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let rawDate = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let date = rawDate.flatMap { formatter.date(from: $0) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) { try bytes.write(to: url, options: .atomic) }
        return DiaryAlbumPhoto(filename: file, pixelSize: CGSize(width: swaps ? height.doubleValue : width.doubleValue,
            height: swaps ? width.doubleValue : height.doubleValue), date: date, selectionOrder: order, fingerprint: digest)
    }
    func finish() async -> DiaryBook? {
        guard !busy else { return nil }
        busy = true; saving = true; cancellation = DiaryPresetCancellation()
        defer { busy = false; saving = false }
        do {
            let book = try await DiaryDocumentStore(ownerID: ownerID).createAlbum(draft, photoDirectory: directory,
                cancellation: cancellation, progress: { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                })
            finished = true
            try? FileManager.default.removeItem(at: directory)
            return book
        } catch is CancellationError { message = "已取消保存，制作草稿仍保留。" }
        catch { message = "保存未完成，草稿仍保留。" + error.localizedDescription }
        return nil
    }
    func cancelSaving() { cancellation.cancel() }
}
