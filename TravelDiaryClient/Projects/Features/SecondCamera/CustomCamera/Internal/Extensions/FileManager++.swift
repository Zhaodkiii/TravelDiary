//
//  FileManager++.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: Prepare Place for Video Output

import SwiftUI

extension FileManager {
    static func prepareURLForVideoOutput() -> URL? {
        guard let fileUrl = getFileUrl() else { return nil }

        clearPlaceIfTaken(fileUrl)
        return fileUrl
    }
}
private extension FileManager {
    static func getFileUrl() -> URL? {
        let directory = StoragePaths.system.camera
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return nil }
        return directory.appendingPathComponent(UUID().uuidString + ".mp4")
    }
    static func clearPlaceIfTaken(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
