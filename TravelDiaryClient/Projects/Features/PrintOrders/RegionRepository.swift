import Foundation
import Combine
import CryptoKit

nonisolated struct RegionManifest: Codable, Sendable {
    let schema_version: Int
    let release_sequence: Int
    let dataset_version: String
    let client_check_after_seconds: Int
    let download_url: String
    let sha256: String
    let byte_size: Int
    let capabilities: [String]?
}

nonisolated struct RegionCache: Codable, Sendable {
    var data: Data?
    var manifest: RegionManifest?
    var etag: String?
    var lastChecked: Date?
    var retryAfter: Date?
    var failures = 0
}

@MainActor
final class RegionRepository: ObservableObject {
    static let shared = RegionRepository()
    typealias Fetch = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    @Published private(set) var dataset: RegionDataset?
    @Published private(set) var updating = false
    @Published private(set) var error: String?
    private var cache = RegionCache()
    private var baseURL: URL?
    private var folder: URL?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastForcedCheck: Date?
    private let bundled: Data?
    private let fetch: Fetch
    private let clock: () -> Date
    private let cacheRoot: URL

    init(bundled: Data? = nil, cacheRoot: URL? = nil, fetch: @escaping Fetch = RegionRepository.download, clock: @escaping () -> Date = Date.init) {
        self.bundled = bundled ?? Bundle.main.url(forResource: "mainland-regions", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        self.cacheRoot = cacheRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RegionDatasets", isDirectory:true)
        self.fetch = fetch; self.clock = clock
        dataset = self.bundled.flatMap { try? Self.decode($0) }
    }
    var supportsStructuredAddress: Bool { cache.manifest?.capabilities?.contains("structured_print_address_v1") == true }
    func configure(baseURL: URL) {
        guard self.baseURL != baseURL else { return }
        task?.cancel(); task=nil; updating=false; generation=UUID(); lastForcedCheck=nil
        self.baseURL=baseURL
        let name=Self.hash(Data(baseURL.absoluteString.utf8))
        folder=cacheRoot.appendingPathComponent(name,isDirectory:true)
        cache=RegionCache(); dataset=bundled.flatMap { try? Self.decode($0) }
        for name in ["active.json", "previous.json"] {
            guard let path=folder?.appendingPathComponent(name), let data=try? Data(contentsOf:path),
                  let saved=try? JSONDecoder().decode(RegionCache.self,from:data) else { continue }
            if saved.data == nil, saved.manifest == nil {
                cache=saved
                continue
            }
            if let bytes=saved.data, let manifest=saved.manifest,
               Self.hash(bytes)==manifest.sha256, let decoded=try? Self.decode(bytes), decoded.dataset_version==manifest.dataset_version {
                dataset=decoded; cache=saved; break
            }
        }
    }
    func checkForUpdates(force: Bool = false) async {
        if let task { await task.value; return }
        guard let baseURL, let folder else { return }
        let now=clock()
        if force {
            if let lastForcedCheck, now.timeIntervalSince(lastForcedCheck)>=0, now.timeIntervalSince(lastForcedCheck)<60 { return }
            lastForcedCheck=now
        } else {
            if let retry=cache.retryAfter, retry>now, retry.timeIntervalSince(now)<=86400 { return }
            let interval=Double(min(30*86400,max(86400,cache.manifest?.client_check_after_seconds ?? 7*86400)))
            if let checked=cache.lastChecked, now.timeIntervalSince(checked)>=0, now.timeIntervalSince(checked)<interval { return }
        }
        let token=generation
        updating=true; error=nil
        task=Task { [weak self] in
            guard let self else { return }
            do {
                let url=baseURL.appendingPathComponent("api/v1/regions/manifest/")
                var req=URLRequest(url:url);req.timeoutInterval=20;req.cachePolicy = .reloadIgnoringLocalCacheData
                if let etag=cache.etag { req.setValue(etag,forHTTPHeaderField:"If-None-Match") }
                let (bytes,response)=try await fetch(req,64*1024)
                try Task.checkCancellation();guard generation==token else { return }
                var updated=cache
                if response.statusCode==304 {
                    guard cache.manifest != nil, cache.data != nil else { throw PrintFailure("地区缓存需要重新下载") }
                } else {
                    guard response.statusCode==200 else { throw PrintFailure("地区更新暂不可用，已保留本地数据") }
                    let manifest=try JSONDecoder().decode(RegionManifest.self,from:bytes)
                    guard manifest.schema_version==1,manifest.byte_size>0,manifest.byte_size<=10*1024*1024 else { throw PrintFailure("地区更新格式不受支持") }
                    if let installed=cache.manifest, manifest.release_sequence<installed.release_sequence {
                        throw PrintFailure("地区发布信息暂未同步，已保留当前版本")
                    }
                    // The installed App may already contain the exact published file.
                    if let bundled, Self.hash(bundled)==manifest.sha256,
                       (try? Self.decode(bundled).dataset_version)==manifest.dataset_version {
                        updated.data=bundled
                    }
                    // Compare equality, not version dates: a new release can roll back.
                    if updated.data.map(Self.hash) != manifest.sha256 {
                        guard let target=URL(string:manifest.download_url,relativeTo:baseURL)?.absoluteURL,
                              target.user==nil,target.password==nil,
                              target.scheme=="https" || (target.scheme==baseURL.scheme && target.host==baseURL.host) else { throw PrintFailure("地区下载地址无效") }
                        var download=URLRequest(url:target);download.timeoutInterval=30
                        let (data,result)=try await fetch(download,10*1024*1024)
                        try Task.checkCancellation();guard generation==token else { return }
                        guard result.statusCode==200,data.count==manifest.byte_size,Self.hash(data)==manifest.sha256 else { throw PrintFailure("地区文件校验失败，已保留本地数据") }
                        let decoded=try Self.decode(data)
                        guard decoded.dataset_version==manifest.dataset_version else { throw PrintFailure("地区版本不一致") }
                        updated.data=data
                    }
                    guard let data=updated.data, try Self.decode(data).dataset_version==manifest.dataset_version else { throw PrintFailure("地区版本不一致") }
                    updated.manifest=manifest;updated.etag=response.value(forHTTPHeaderField:"ETag")
                }
                updated.lastChecked=clock();updated.retryAfter=nil;updated.failures=0
                try persist(updated,folder:folder)
                cache=updated
                if let data=updated.data { dataset=try Self.decode(data) }
            } catch is CancellationError { }
            catch {
                guard generation==token else { return }
                self.error=error.localizedDescription
                cache.failures += 1
                cache.retryAfter=clock().addingTimeInterval(Double([3600,21600,86400][min(cache.failures-1,2)]))
                // Do not advance lastChecked/ETag when the artifact failed to install.
                try? persist(cache,folder:folder)
            }
            guard generation==token else { return }
            updating=false;task=nil
        }
        await task?.value
    }
    private func persist(_ value: RegionCache, folder: URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let active=folder.appendingPathComponent("active.json")
        if let previous=try? Data(contentsOf:active), let decoded=try? JSONDecoder().decode(RegionCache.self,from:previous),
           let bytes=decoded.data, let manifest=decoded.manifest, Self.hash(bytes)==manifest.sha256, (try? Self.decode(bytes)) != nil {
            try previous.write(to:folder.appendingPathComponent("previous.json"),options:.atomic)
        }
        try JSONEncoder().encode(value).write(to:active,options:.atomic)
    }
    nonisolated static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    nonisolated static func decode(_ data: Data) throws -> RegionDataset {
        guard data.count<=10*1024*1024 else { throw PrintFailure("地区文件过大") }
        return try JSONDecoder().decode(RegionDataset.self,from:data).validated()
    }
    nonisolated static func download(_ request: URLRequest, _ limit: Int) async throws -> (Data, HTTPURLResponse) {
        let (stream,response)=try await URLSession.shared.bytes(for:request)
        guard let http=response as? HTTPURLResponse, response.expectedContentLength<=Int64(limit) else { throw PrintFailure("地区服务响应无效") }
        var data=Data()
        for try await byte in stream {
            if data.count>=limit { throw PrintFailure("地区文件过大") }
            data.append(byte)
        }
        return (data,http)
    }
}
