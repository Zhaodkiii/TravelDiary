// 构建时只校验已经转换的素材，不调用 Python、不解析 PSD。
import Foundation
import CryptoKit

func fail(_ message: String) -> Never { fputs("error: 预设资源校验失败：\(message)\n", stderr); exit(1) }
let root = URL(fileURLWithPath: CommandLine.arguments[1])
func json(_ url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw NSError(domain: "JSON", code: 1) }
    return value
}
func safe(_ path: String, _ base: URL) -> URL {
    let result = base.appendingPathComponent(path).resolvingSymlinksInPath()
    guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), result.path.hasPrefix(base.resolvingSymlinksInPath().path + "/") else { fail("非法路径 \(path)") }
    return result
}
do {
    let series = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("series.json"))) as! [[String: Any]]
    var ids = Set<String>()
    for category in series {
        let folder = safe(category["directory"] as! String, root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            fail("缺少系列目录 \(category["directory"] ?? "")")
        }
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let packages = enumerator?.allObjects as? [URL] ?? []
        for package in packages where package.pathExtension == "diarypreset" {
            let m = try json(package.appendingPathComponent("package.json"))
            guard m["format"] as? String == "TravelDiary.PresetBook", [1, 2].contains(m["schemaVersion"] as? Int ?? 0),
                  let layerSchema = m["layerSchemaVersion"] as? Int, [1, 2].contains(layerSchema),
                  m["seriesID"] as? String == category["id"] as? String,
                  let id = m["templateBookID"] as? String, ids.insert(id).inserted,
                  let files = m["files"] as? [[String: Any]], let pages = m["pages"] as? [[String: Any]], !pages.isEmpty,
                  let objects = m["objectTable"] as? [String: String], let assets = m["assetTable"] as? [String: [String: Any]] else { fail(package.path) }
            var paths = Set<String>()
            for file in files {
                guard let path = file["path"] as? String, paths.insert(path).inserted else { fail("重复文件") }
                let data = try Data(contentsOf: safe(path, package))
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard data.count == file["byteCount"] as? Int, sha == file["sha256"] as? String else { fail("\(id)/\(path) 摘要不匹配") }
            }
            let pageIDs = pages.compactMap { $0["id"] as? String }
            guard Set(pageIDs).count == pages.count, pageIDs.contains(m["coverPageID"] as? String ?? "") else { fail("封面或页 ID 错误") }
            for page in pages {
                guard let path = page["path"] as? String, paths.contains(path) else { fail("页面缺失") }
                let p = try json(safe(path, package))
                guard p["id"] as? String == page["id"] as? String,
                      let preview = p["preview"] as? [String: String], preview.values.allSatisfy({ paths.contains($0) }) else { fail("页面预览缺失") }
                var seen = Set<String>()
                func visit(_ cid: String, _ depth: Int) throws {
                    guard depth <= 30, seen.insert(cid).inserted, let file = objects[cid], paths.contains(file) else { fail("对象循环或缺失 \(cid)") }
                    let object = try json(safe(file, package))
                    guard object["id"] as? String == cid, let layers = object["layers"] as? [[String: Any]], layers.count <= 200 else { fail("对象无效") }
                    for layer in layers {
                        let semanticKind = layer["kind"] as? String ?? ""
                        let renderType = layerSchema == 1 ? semanticKind : (layer["renderType"] as? String ?? "")
                        if layerSchema == 2 {
                            let categories: [String: Set<String>] = [
                                "background": ["paper_texture", "page", "scene"],
                                "photo": ["slot", "fixed", "frame", "photo_card"],
                                "paper": ["note", "checklist", "route", "ticket", "title_card"],
                                "text": ["title", "body", "date", "quote", "caption"],
                                "illustration": ["scene", "object", "botanical", "tape", "stamp", "ornament"],
                                "branding": ["logo", "seal", "series_mark"]
                            ]
                            guard let subcategory = layer["subcategory"] as? String,
                                  categories[semanticKind]?.contains(subcategory) == true,
                                  ["group", "image", "native_text", "canvas", "frame"].contains(renderType) else { fail("图层分类无效") }
                        }
                        if renderType == "object" || renderType == "group" {
                            guard let child = layer["contentID"] as? String else { fail("缺少子对象") }; try visit(child, depth + 1)
                        } else if ["photo", "sticker", "image"].contains(renderType) {
                            guard let aid = layer["assetID"] as? String, let asset = assets[aid], let path = asset["path"] as? String, paths.contains(path) else { fail("素材引用缺失") }
                        } else if renderType == "native_text" {
                            guard semanticKind == "text", layer["text"] is String else { fail("原生文字分类无效") }
                        } else if !["text", "frame", "canvas"].contains(renderType) {
                            fail("绘制类型无效")
                        }
                    }
                }
                try visit(p["rootContentID"] as? String ?? "", 0)
            }
        }
    }
    print("预设资源校验通过：\(ids.count) 本")
} catch { fail(error.localizedDescription) }
