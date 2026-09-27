//
//  CustomCameraTimerContainer.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import Combine

@MainActor class CustomCameraTimerContainer {
    private static var timers: [CustomCameraTimer] = []
}

extension CustomCameraTimerContainer {
    static func register(_ timer: CustomCameraTimer) -> CustomCameraTimer  {
        if let timer = getTimer(timer.id) { return timer }
        timers.append(timer)
        return timer
    }
}
private extension CustomCameraTimerContainer {
    static func getTimer(_ id: CustomCameraTimerID) -> CustomCameraTimer? {
        timers.first(where: { $0.id == id })
    }
}

extension CustomCameraTimerContainer {
    static func resetAll() { timers.forEach { $0.reset() }}
}
