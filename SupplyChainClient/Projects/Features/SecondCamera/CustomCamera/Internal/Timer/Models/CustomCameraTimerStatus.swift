//
//  Public+CustomCameraTimerStatus.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import Combine

internal enum CustomCameraTimerStatus {
    /// Initial timer status
    /// ## Triggered by methods
    /// - ``CustomCameraTimer/reset()``
    case notStarted
    
    /// Timer is in a progress
    ///
    /// ## Triggered by methods
    ///  - ``CustomCameraTimer/start()``
    ///  - ``CustomCameraTimer/start(from:to:)-1mvp1``
    ///  - ``CustomCameraTimer/resume()``
    case running
    
    /// Timer is in a paused state
    ///
    ///  ## Triggered by methods
    ///  - ``CustomCameraTimer/pause()``
    case paused
    
    /// The timer was terminated by running out of time or calling the function
    ///
    /// ## Triggered by methods
    ///  - ``CustomCameraTimer/skip()``
    case finished
}

extension CustomCameraTimerStatus {
    var isTimerRunning: Bool { self == .running }
    var isNeededReset: Bool { self == .notStarted || self == .finished }
    var isSkippable: Bool { self == .running || self == .paused }
}
