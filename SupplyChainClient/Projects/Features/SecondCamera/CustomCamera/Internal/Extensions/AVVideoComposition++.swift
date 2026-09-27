//
//  AVVideoComposition++.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: Apply Filters

import AVKit

extension AVVideoComposition {
    static func applyFilters(to asset: AVAsset, applyFiltersAction: @Sendable @escaping (AVAsynchronousCIImageFilteringRequest) -> ()) async throws -> AVVideoComposition {
        try await AVVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: applyFiltersAction)
    }
}
