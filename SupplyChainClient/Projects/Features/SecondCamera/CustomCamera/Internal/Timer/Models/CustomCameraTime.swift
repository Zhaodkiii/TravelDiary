//
//  CustomCameraTime.swift
//
//  Created by Tomasz Kurylik
//    - Twitter: https://twitter.com/tkurylik
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//
//  Copyright ©2023 Mijick. All rights reserved.




import Combine
import Foundation

internal struct CustomCameraTime: Equatable {
    internal let hours: Int
    internal let minutes: Int
    internal let seconds: Int
    internal let milliseconds: Int
}

// MARK: - Helpers
extension CustomCameraTime {
    var defaultTimeFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.maximumUnitCount = 0
        formatter.allowsFractionalUnits = false
        formatter.collapsesLargestUnit = false

        return formatter
    }
}
