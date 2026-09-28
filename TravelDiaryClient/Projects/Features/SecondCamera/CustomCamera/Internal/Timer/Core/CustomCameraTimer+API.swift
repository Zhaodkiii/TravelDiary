//
//  Public+CustomCameraTimer.swift of Timer
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



// MARK: - Initialising Timer

import Combine
import SwiftUI

internal extension CustomCameraTimer {
    /// Configure the interval for publishing the timer status.
    ///
    /// - Parameters:
    ///   - time: timer status publishing interval
    ///   - tolerance: The amount of time after the scheduled fire date that the timer may fire.
    ///   - currentTime: A binding value that will be updated every **time** interval.
    ///
    /// - WARNING: Use the ``start()``  or ``start(from:to:)-1mvp1`` methods to start the timer.
    func publish(every time: TimeInterval, tolerance: TimeInterval = 0.4, currentTime: Binding<CustomCameraTime>) throws -> CustomCameraTimer {
        try publish(every: time, tolerance: tolerance) { currentTime.wrappedValue = $0 }
    }
    
    /// Configure the interval for publishing the timer status.
    ///
    /// - Parameters:
    ///   - time: timer status publishing interval
    ///   - tolerance: The amount of time after the scheduled fire date that the timer may fire.
    ///   - completion: A completion block that will be executed every **time** interval
    ///
    /// - WARNING: Use the ``start()`` or  ``start(from:to:)-1mvp1`` method to start the timer.
    func publish(every time: TimeInterval, tolerance: TimeInterval = 0.4, _ completion: @escaping (_ currentTime: CustomCameraTime) -> () = { _ in }) throws -> CustomCameraTimer {
        try CustomCameraTimerValidator.checkRequirementsForInitializingTimer(time)
        setupPublishers(time, tolerance, completion)
        return self
    }
}

// MARK: - Starting Timer
internal extension CustomCameraTimer {
    /**
     Starts the timer using the specified initial values.
     
     - Note: The timer can be run backwards - use any value **to** that is greater than **from**.
     
     ### Up-going timer
     ```swift
         CustomCameraTimer(.exampleId)
             .start(from: .zero, to: CustomCameraTime(seconds: 10))
     ```
     
     ### Down-going timer
     ```swift
         CustomCameraTimer(.exampleId)
             .start(from: CustomCameraTime(seconds: 10), to: .zero)
     ```
     */
    func start(from startTime: CustomCameraTime = .zero, to endTime: CustomCameraTime = .max) throws {
        try start(from: startTime.toTimeInterval(), to: endTime.toTimeInterval())
    }
    
    /**
     Starts the timer using the specified initial values.
     
     - Note: The timer can be run backwards - use any value **to** that is greater than **from**.
     
     ### Up-going timer
     ```swift
         CustomCameraTimer(.exampleId)
             .start(from: .zero, to: 10)
     ```
     
     ### Down-going timer
     ```swift
         CustomCameraTimer(.exampleId)
             .start(from: 10, to: .zero)
     ```
     */
    func start(from startTime: TimeInterval = 0, to endTime: TimeInterval = .infinity) throws {
        try CustomCameraTimerValidator.checkRequirementsForStartingTimer(startTime, endTime, state, timerStatus)
        assignInitialStartValues(startTime, endTime)
        startTimer()
    }
    
    /// Starts the up-going infinity timer
    func start() throws {
        try start(from: .zero, to: .infinity)
    }
}

// MARK: - Stopping Timer
internal extension CustomCameraTimer {
    /// Pause the timer.
    func pause() {
        guard timerStatus == .running else { return }
        pauseTimer()
    }
}

// MARK: - Resuming Timer
internal extension CustomCameraTimer {
    /// Resumes the paused timer.
    func resume() throws {
        try CustomCameraTimerValidator.checkRequirementsForResumingTimer(callbacks)
        startTimer()
    }
}

// MARK: - Aborting Timer
internal extension CustomCameraTimer {
    /// Stops the timer and resets its current time to the initial value.
    func cancel() {
        resetRunningTime()
        cancelTimer()
    }
}

// MARK: - Aborting Timer
internal extension CustomCameraTimer {
    /// Stops the timer and resets all timer states to default values.
    func reset() {
        resetTimer()
    }
}

// MARK: - Skip Timer
internal extension CustomCameraTimer {
    /// Stops the timer and updates its status to the final state.
    func skip() throws {
        guard timerStatus.isSkippable else { return }
        try CustomCameraTimerValidator.isCanBeSkipped(timerStatus)
        skipRunningTime()
        finishTimer()
    }
}

// MARK: - Publishing Timer Activity Status
internal extension CustomCameraTimer {
    /// Publishes timer status changes.
    ///  - Note: To configure the interval at which the state of the timer will be published, use method  ``publish(every:tolerance:currentTime:)``
    func onTimerStatusChange(_ action: @escaping (_ timerStatus: CustomCameraTimerStatus) -> ()) -> CustomCameraTimer {
        callbacks.onTimerStatusChange = action
        return self
    }
    /// Publishes timer status changes.
    /// - Note: To configure the interval at which the state of the timer will be published, use method  ``publish(every:tolerance:currentTime:)``
    func bindTimerStatus(timerStatus: Binding<CustomCameraTimerStatus>) -> CustomCameraTimer {
        onTimerStatusChange { timerStatus.wrappedValue = $0 }
    }
}

// MARK: - Publishing Timer Progress
internal extension CustomCameraTimer {
    /// Publishes timer progress changes.
    /// - Note: To configure the interval at which the timer's progress will be published, use method ``publish(every:tolerance:currentTime:)``
    func onTimerProgressChange(_ action: @escaping (_ progress: Double) -> ()) -> CustomCameraTimer {
        callbacks.onTimerProgressChange = action
        return self
    }
    /// Publishes timer progress changes.
    /// - Note: To configure the interval at which the timer's progress will be published, use method ``publish(every:tolerance:currentTime:)``
    func bindTimerProgress(progress: Binding<Double>) -> CustomCameraTimer {
        onTimerProgressChange { progress.wrappedValue = $0 }
    }
}
