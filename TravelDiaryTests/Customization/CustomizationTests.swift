import Testing
import Foundation
@testable import TravelDiary

@MainActor
struct CustomizationTests {
    @Test func requestWorkflowDecodesOldAndNewServerFieldsWithoutMixingProductionBasis() throws {
        var json: [String: Any] = ["id":UUID().uuidString,"number":"C20261020-12345678","title":"主题", "brief":["description":"故事"],
            "status":"in_production","revision":2,"event_sequence":1,"last_read_sequence":0,"revision_round":0,
            "assets":[],"submissions":[],"events":[],"deliveries":[]]
        let old = try JSONDecoder().decode(CustomRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.pending_submission == nil)
        #expect(old.permits("cancel"))
        json["accepted_submission_id"] = 1
        json["latest_submission_id"] = 2
        json["pending_submission"] = true
        json["cancellation_requested"] = true
        json["allowed_actions"] = ["delete"]
        let updated = try JSONDecoder().decode(CustomRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(updated.accepted_submission_id == 1)
        #expect(updated.latest_submission_id == 2)
        #expect(updated.pending_submission == true)
        #expect(updated.cancellation_requested == true)
        #expect(!updated.permits("cancel"))
        #expect(updated.permits("delete"))
    }

    @Test func photoPutRetryAcceptsOnlySuccessfulPutOrExistingSessionObject() {
        #expect(CustomPhotoUploadResponse.accepted(status: 200, body: Data()))
        #expect(CustomPhotoUploadResponse.accepted(status: 409, body: Data("<Error><Code>FileAlreadyExists</Code></Error>".utf8)))
        #expect(!CustomPhotoUploadResponse.accepted(status: 409, body: Data("<Error><Code>FileImmutable</Code></Error>".utf8)))
        #expect(!CustomPhotoUploadResponse.accepted(status: 403, body: Data()))
        #expect(!CustomPhotoUploadResponse.accepted(status: 500, body: Data()))
    }

    @Test func oldPhotoUploadRecordsDecodeWithoutNewAcknowledgementAndDimensions() throws {
        let original = CustomUploadJob(id: UUID(), owner: "A", requestID: UUID().uuidString,
            file: URL(fileURLWithPath: "/tmp/photo.jpg"), size: 7, sha256: String(repeating: "a", count: 64),
            mime: "image/jpeg", uploadID: UUID().uuidString, state: "正在校验")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(CustomUploadJob.self, from: data)
        #expect(restored.width == nil)
        #expect(restored.height == nil)
        #expect(restored.uploadedToOSS == nil)
        var acknowledged = restored
        acknowledged.uploadedToOSS = true
        let resumed = try JSONDecoder().decode(CustomUploadJob.self, from: JSONEncoder().encode(acknowledged))
        #expect(resumed.uploadedToOSS == true)
        #expect(resumed.uploadID == original.uploadID)
    }

    @Test func emptyPickerResetDoesNotImportOrErasePreviousFailure() async {
        let state = CustomPhotoImportState()
        state.report(CustomFailure("请先绑定正式账号"), stage: "account")
        let added = await state.add([Int](), load: { _ in
            Issue.record("Empty selection must not read a photo")
            return Data()
        }, enqueue: { _ in Issue.record("Empty selection must not enqueue a photo") })
        #expect(added == 0)
        #expect(state.error == "请先绑定正式账号")
        #expect(state.showError)
        #expect(!state.isImporting)
    }

    @Test func photoImportShowsProgressAndAcknowledgesQueuedPhotos() async {
        let state = CustomPhotoImportState()
        var queued: [Data] = []
        let added = await state.add([1, 2], load: { index in
            #expect(state.isImporting)
            #expect(state.message == "正在读取照片 \(index)/2…")
            return Data([UInt8(index)])
        }, enqueue: { queued.append($0) })
        #expect(added == 2)
        #expect(queued == [Data([1]), Data([2])])
        #expect(state.message?.contains("已添加 2 张照片") == true)
        #expect(state.error == nil)
        #expect(!state.isImporting)
    }

    @Test func unreadablePhotoRetainsErrorWithoutEnqueueing() async {
        let state = CustomPhotoImportState()
        let added = await state.add([1], load: { _ in nil }, enqueue: { _ in
            Issue.record("Unreadable photo must not be enqueued")
        })
        #expect(added == 0)
        #expect(state.message == nil)
        #expect(state.error?.contains("无法读取所选照片") == true)
        #expect(state.showError)
        #expect(!state.isImporting)
    }

    @Test func failedEnqueueDoesNotHidePartialSuccessOrLaterPhotos() async {
        let state = CustomPhotoImportState()
        var queued: [Data] = []
        let added = await state.add([1, 2, 3], load: { Data([UInt8($0)]) }, enqueue: { data in
            if data == Data([2]) { throw CustomFailure("照片太大或无法读取") }
            queued.append(data)
        })
        #expect(added == 2)
        #expect(queued == [Data([1]), Data([3])])
        #expect(state.message?.contains("已添加 2 张照片") == true)
        #expect(state.error?.contains("第 2 张照片：照片太大或无法读取") == true)
        #expect(state.showError)
        #expect(!state.isImporting)
    }

    @Test func concurrentPhotoImportCannotStartAnotherBatch() async {
        let state = CustomPhotoImportState()
        let added = await state.add([1], load: { _ in
            let overlapping = await state.add([2], load: { _ in
                Issue.record("Concurrent batch must not read photos")
                return Data()
            }, enqueue: { _ in Issue.record("Concurrent batch must not enqueue photos") })
            #expect(overlapping == 0)
            return Data([1])
        }, enqueue: { _ in })
        #expect(added == 1)
        #expect(!state.isImporting)
    }

    @Test func pushOnlyAcceptsTypedReadOnlyActionsAndValidIDs() {
        let payload: [AnyHashable: Any] = ["schema_version":1,"request_id":UUID().uuidString,"event_id":UUID().uuidString,"action":"open_customization_delivery"]
        #expect(CustomPushPayload(payload) != nil)
        var malicious = payload; malicious["action"] = "confirm"
        #expect(CustomPushPayload(malicious) == nil)
        malicious = payload; malicious["request_id"] = "https://example.test/private"
        #expect(CustomPushPayload(malicious) == nil)
        malicious = payload; malicious["schema_version"] = 999
        #expect(CustomPushPayload(malicious) == nil)
    }
    @Test func privateCacheCannotBePreparedOrAdvertisedForAnotherAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        let manifest = try JSONSerialization.data(withJSONObject: ["format":"TravelDiary.PresetBook","schemaVersion":1,"layerSchemaVersion":2,
            "templateBookID":"private-book","packageVersion":1,"title":"private","seriesID":"city","tags":[],"sortOrder":0,
            "pageSize":["width":100,"height":100],"coverPageID":"page","pages":[["id":"page","title":"Page","path":"page.json"]],
            "objectTable":[:],"assetTable":[:],"requiredCapabilities":[],"files":[]] as [String:Any])
        let id = UUID(); try FileManager.default.createDirectory(at: root.appendingPathComponent(id.uuidString),withIntermediateDirectories: true)
        var job = PresetDownloadJob(id: id,owner: "A",planID: "plan",title: "private",manifestData: manifest,wholeBook: true,targetID: nil,afterPageID: nil,expectedRevision: nil)
        job.privateOwner = "A"; job.status = "completed"
        try JSONEncoder().encode([job]).write(to: root.appendingPathComponent("jobs.json"))
        let manager = PresetDownloadManager(directory: root); await manager.waitUntilRestored()
        manager.activate(owner: "A")
        #expect(manager.preparedPackage(id) != nil)
        manager.activate(owner: "B")
        #expect(manager.preparedPackage(id) == nil)
        #expect(manager.cachedPackage(bookID: "private-book",version: 1,pageIDs: ["page"]) == nil)
        #expect(manager.availability.downloadedPageIDs(bookID: "private-book",version: 1).isEmpty)
        manager.deactivate()
        #expect(manager.preparedPackage(id) == nil)
    }
}
