//
//  CustomCameraTimerStateManager.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



import Combine
import SwiftUI

class CustomCameraTimerStateManager {
    private var internalTimer: Timer?
    var backgroundTransitionDate: Date? = nil
}

// MARK: Run Timer
extension CustomCameraTimerStateManager {
    func runTimer(_ configuration: CustomCameraTimerConfigurationManager, _ target: Any, _ completion: Selector) {
            stopTimer()
            runTimer(target, configuration.getPublisherTime(), completion)
            setTolerance(configuration.publisherTimeTolerance)
            updateInternalTimerStartAddToRunLoop()
    }
}
private extension CustomCameraTimerStateManager {
    func runTimer(_ target: Any, _ timeInterval: TimeInterval, _ completion: Selector) {
        internalTimer = .scheduledTimer(
            timeInterval: timeInterval,
            target: target,
            selector: completion,
            userInfo: nil,
            repeats: true
        )
    }
    func setTolerance(_ value: TimeInterval) {
       internalTimer?.tolerance = value
    }
    func updateInternalTimerStartAddToRunLoop() {
        #if os(macOS)
        guard let internalTimer = internalTimer else { return }
        RunLoop.main.add(internalTimer, forMode: .common)
        #endif
    }
}

// MARK: Stop Timer
extension CustomCameraTimerStateManager {
    func stopTimer() {
        internalTimer?.invalidate()
    }
}

// MARK: App State Handle
extension CustomCameraTimerStateManager {
    func didEnterBackground() {
        internalTimer?.invalidate()
        backgroundTransitionDate = .init()
    }
    func willEnterForeground() {
        backgroundTransitionDate = nil
    }
}
