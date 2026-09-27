//
//  CustomCameraTimerValidator.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



import Combine
import Foundation

class CustomCameraTimerValidator {
    static func checkRequirementsForInitializingTimer(_ publisherTime: TimeInterval) throws {
        if publisherTime < 0 { throw CustomCameraTimerError.publisherTimeCannotBeLessThanZero }
    }
    static func checkRequirementsForStartingTimer(_ startTime: TimeInterval, _ endTime: TimeInterval, _ state: CustomCameraTimerStateManager, _ status: CustomCameraTimerStatus) throws {
        if startTime < 0 || endTime < 0 { throw CustomCameraTimerError.timeCannotBeLessThanZero }
        if startTime == endTime { throw CustomCameraTimerError.startTimeCannotBeTheSameAsEndTime }
        if status == .running && state.backgroundTransitionDate == nil { throw CustomCameraTimerError.timerIsAlreadyRunning }
    }
    static func checkRequirementsForResumingTimer(_ callbacks: CustomCameraTimerCallbacks) throws {
        if callbacks.onRunningTimeChange == nil { throw CustomCameraTimerError.cannotResumeNotInitialisedTimer }
    }
    static func isCanBeSkipped(_ timerStatus: CustomCameraTimerStatus) throws {
        if timerStatus == .running || timerStatus == .paused { return }
        throw CustomCameraTimerError.timerIsNotStarted
    }
}
