import Foundation
import Testing
@testable import TravelDiary

private actor RegionHTTPStub {
    struct Reply: Sendable { let status: Int; let data: Data; var etag: String? = nil }
    var replies: [Reply]
    var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies=replies }
    func send(_ request: URLRequest, _ limit: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply=replies.removeFirst()
        let headers=reply.etag.map { ["ETag":$0] } ?? [:]
        return (reply.data,HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:nil,headerFields:headers)!)
    }
    func count() -> Int { requests.count }
    func request(_ i: Int) -> URLRequest { requests[i] }
}

@MainActor
private final class RegionClock { var date=Date(timeIntervalSince1970:1_800_000_000) }

@MainActor
struct RegionTests {
    private func seed() throws -> Data {
        // This also asserts that the offline dataset is included in the actual App bundle.
        try Data(contentsOf:#require(Bundle.main.url(forResource:"mainland-regions",withExtension:"json")))
    }
    private func modified(_ data: Data, version: String) throws -> Data {
        var value=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        value["dataset_version"]=version
        return try JSONSerialization.data(withJSONObject:value,options:.sortedKeys)
    }
    private func manifest(_ data: Data, sequence: Int = 1, badHash: Bool = false) throws -> Data {
        let dataset=try RegionRepository.decode(data)
        return try JSONEncoder().encode(RegionManifest(schema_version:1,release_sequence:sequence,dataset_version:dataset.dataset_version,
            client_check_after_seconds:604800,download_url:"/api/v1/regions/datasets/\(dataset.dataset_version).json",
            sha256:badHash ? "invalid" : RegionRepository.hash(data),byte_size:data.count,capabilities:["structured_print_address_v1"]))
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private var base: URL { URL(string:"https://regions.example.test")! }
    private func repository(_ bytes: Data, _ root: URL, _ stub: RegionHTTPStub, _ clock: RegionClock) -> RegionRepository {
        let value=RegionRepository(bundled:bytes,cacheRoot:root,fetch:{ req,limit in try await stub.send(req,limit) },clock:{ clock.date })
        value.configure(baseURL:base)
        return value
    }
    @Test func mainlandBundleIsCompleteAndSpecialPathsUseRealCodes() throws {
        let dataset=try RegionRepository.decode(seed())
        #expect(dataset.regions.filter{$0.level=="province"}.count==31)
        for (p,c,d) in [("330000","330100","330106"),("110000",nil,"110101"),("410000",nil,"419001"),("440000","441900",nil)] {
            let picker=RegionPickerModel(dataset:dataset,province:p,city:c,district:d)
            let selection=try #require(picker.selection)
            #expect(selection.province.code==p);#expect(selection.city?.code==c);#expect(selection.district?.code==d)
            #expect(selection.leaf.selectable_leaf)
        }
    }
    @Test func changingParentRepairsChildrenAndSnapshotDoesNotChange() throws {
        let dataset=try RegionRepository.decode(seed())
        var model=RegionPickerModel(dataset:dataset,province:"330000",city:"330100",district:"330106")
        let snapshot=model
        model.select("310000",component:0)
        let selection=try #require(model.selection)
        #expect(selection.province.code=="310000")
        #expect(selection.city==nil)
        #expect(selection.district?.parent_code=="310000")
        #expect(snapshot.selection?.district?.code=="330106")
    }
    @Test func compatibilitySerializationDoesNotDuplicateOrMutateDraft() throws {
        let dataset=try RegionRepository.decode(seed())
        let selected=try #require(RegionPickerModel(dataset:dataset,province:"330000",city:"330100",district:"330106").selection)
        var address=PrintAddress(name:"test",phone:"13800000000",detail:"测试街道1号")
        address.select(selected,shippingRegions:["中国大陆"])
        let wire=address.submissionAddress(structured:false)
        #expect(wire.region=="中国大陆");#expect(wire.province_code==nil)
        #expect(wire.detail=="浙江省 杭州市 西湖区 测试街道1号")
        #expect(wire.submissionAddress(structured:false)==wire)
        #expect(address.detail=="测试街道1号")
        #expect(address.submissionAddress(structured:true).district_code=="330106")
    }
    @Test func oldAddressStillDecodesAndIsNotGuessed() throws {
        let data=Data(#"{"name":"test","phone":"13800000000","region":"中国大陆","detail":"原始完整地址"}"#.utf8)
        let address=try JSONDecoder().decode(PrintAddress.self,from:data)
        #expect(!address.hasAdministrativeRegion)
        #expect(address.detail=="原始完整地址")
        #expect(address.submissionAddress(structured:false)==address)
    }
    @Test func successfulUpdatePersistsAndSevenDayChecksUseETag() async throws {
        let seed=try seed(), newer=try modified(seed,version:"test-newer")
        let clock=RegionClock(), path=root();defer { try? FileManager.default.removeItem(at:path) }
        let stub=RegionHTTPStub([.init(status:200,data:try manifest(newer),etag:"v1"),.init(status:200,data:newer),.init(status:304,data:Data())])
        let repo=repository(seed,path,stub,clock)
        await repo.checkForUpdates()
        #expect(repo.dataset?.dataset_version=="test-newer");#expect(repo.supportsStructuredAddress)
        await repo.checkForUpdates();#expect(await stub.count()==2)
        clock.date.addTimeInterval(7*86400+1)
        await repo.checkForUpdates();#expect(await stub.count()==3)
        #expect(await stub.request(2).value(forHTTPHeaderField:"If-None-Match")=="v1")
        let restarted=repository(seed,path,stub,clock)
        #expect(restarted.dataset?.dataset_version=="test-newer")
        await restarted.checkForUpdates();#expect(await stub.count()==3)
    }
    @Test func failedArtifactKeepsOldDatasetAndDoesNotAdvanceCheckDate() async throws {
        let seed=try seed(), newer=try modified(seed,version:"test-download")
        let clock=RegionClock(), path=root();defer { try? FileManager.default.removeItem(at:path) }
        let stub=RegionHTTPStub([.init(status:200,data:try manifest(newer)),.init(status:503,data:Data()),
                                 .init(status:200,data:try manifest(newer)),.init(status:200,data:newer)])
        let repo=repository(seed,path,stub,clock)
        await repo.checkForUpdates();#expect(repo.dataset?.dataset_version != "test-download")
        #expect(repo.error != nil)
        let restarted=repository(seed,path,stub,clock)
        await restarted.checkForUpdates();#expect(await stub.count()==2)
        clock.date.addTimeInterval(3601)
        await restarted.checkForUpdates();#expect(restarted.dataset?.dataset_version=="test-download")
        #expect(await stub.count()==4)
    }
    @Test func checksumFailureAndCorruptActiveCacheFallBackSafely() async throws {
        let seed=try seed(), a=try modified(seed,version:"version-a"), b=try modified(seed,version:"version-b")
        let clock=RegionClock(), path=root();defer { try? FileManager.default.removeItem(at:path) }
        let stub=RegionHTTPStub([.init(status:200,data:try manifest(a)),.init(status:200,data:a),
            .init(status:200,data:try manifest(b,sequence:2)),.init(status:200,data:b),
            .init(status:200,data:try manifest(seed,sequence:3,badHash:true)),.init(status:200,data:seed)])
        let repo=repository(seed,path,stub,clock)
        await repo.checkForUpdates();clock.date.addTimeInterval(7*86400+1)
        await repo.checkForUpdates();#expect(repo.dataset?.dataset_version=="version-b")
        clock.date.addTimeInterval(7*86400+1)
        await repo.checkForUpdates();#expect(repo.dataset?.dataset_version=="version-b")
        let dir=path.appendingPathComponent(RegionRepository.hash(Data(base.absoluteString.utf8)))
        try Data("broken".utf8).write(to:dir.appendingPathComponent("active.json"))
        let recovered=repository(seed,path,stub,clock)
        #expect(recovered.dataset != nil)
        #expect(recovered.dataset?.dataset_version=="version-b")
    }
    @Test func rollbackAcceptsOlderVersionAndConcurrentChecksShareWorker() async throws {
        let seed=try seed(), newer=try modified(seed,version:"version-new")
        let clock=RegionClock(), path=root();defer { try? FileManager.default.removeItem(at:path) }
        let stub=RegionHTTPStub([.init(status:200,data:try manifest(newer,sequence:2)),.init(status:200,data:newer),
                                .init(status:200,data:try manifest(seed,sequence:3)),.init(status:200,data:seed)])
        let repo=repository(seed,path,stub,clock)
        async let first: Void=repo.checkForUpdates()
        async let second: Void=repo.checkForUpdates()
        _ = await(first,second)
        #expect(await stub.count()==2)
        clock.date.addTimeInterval(7*86400+1)
        await repo.checkForUpdates()
        #expect(repo.dataset?.dataset_version==(try RegionRepository.decode(seed).dataset_version))
    }
    @Test func matchingBundledVersionNeedsOnlyManifestAndNoArtifactDownload() async throws {
        let seed=try seed(), path=root(), clock=RegionClock()
        defer { try? FileManager.default.removeItem(at:path) }
        let stub=RegionHTTPStub([.init(status:200,data:try manifest(seed),etag:"bundled")])
        let repo=repository(seed,path,stub,clock)
        await repo.checkForUpdates()
        #expect(await stub.count()==1)
        #expect(repo.supportsStructuredAddress)
        #expect(repo.error==nil)
        let offline=repository(seed,path,stub,clock)
        #expect(offline.dataset?.dataset_version==repo.dataset?.dataset_version)
        await offline.checkForUpdates();#expect(await stub.count()==1)
    }

}
