//
//  CustomCameraTimer.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



import Combine
import SwiftUI

internal final class CustomCameraTimer: ObservableObject, FactoryInitializable {
    /// Timer time publisher.
    /// - important: The frequency for updating this property can be configured with function ``CustomCameraTimer/publish(every:tolerance:currentTime:)``
    /// - NOTE: By default, updates are triggered each time the timer status is marked as **finished**
    @Published internal private(set) var timerTime: CustomCameraTime = .init()
    
    /// Timer status publisher.
    @Published internal private(set) var timerStatus: CustomCameraTimerStatus = .notStarted
    
    /// Timer progress publisher.
    /// - important: The frequency for updating this property can be configured with function ``CustomCameraTimer/publish(every:tolerance:currentTime:)``
    /// - NOTE: By default, updates are triggered each time the timer status is marked as **finished**
    @Published internal private(set) var timerProgress: Double = 0
    
    /// Unique id that enables an access to the registered timer from any location.
    internal let id: CustomCameraTimerID
    
    let callbacks = CustomCameraTimerCallbacks()
    let state = CustomCameraTimerStateManager()
    let configuration = CustomCameraTimerConfigurationManager()
    
    init(identifier: CustomCameraTimerID) { self.id = identifier }
}

// MARK: - Initialising Timer
extension CustomCameraTimer {
    func setupPublishers(_ time: TimeInterval, _ tolerance: TimeInterval, _ completion: @escaping (CustomCameraTime) -> ()) {
        configuration.setPublishers(time: time, tolerance: tolerance)
        callbacks.onRunningTimeChange = completion
        resetTimerPublishers()
    }
}

// MARK: - Starting Timer
extension CustomCameraTimer {
    func assignInitialStartValues(_ startTime: TimeInterval, _ endTime: TimeInterval) {
        configuration.setInitialTime(startTime: startTime, endTime: endTime)
        resetRunningTime()
        resetTimerPublishers()
    }
    func startTimer() {
        handleTimer(status: .running)
    }
}

// MARK: - Timer State Control
extension CustomCameraTimer {
    func pauseTimer() { handleTimer(status: .paused) }
    func cancelTimer() { handleTimer(status: .notStarted) }
    func finishTimer() { handleTimer(status: .finished) }
}

// MARK: - Reset Timer
extension CustomCameraTimer {
    func resetTimer() {
        configuration.reset()
        updateInternalTimer(false)
        timerStatus = .notStarted
        updateObservers(false)
        resetTimerPublishers()
        publishTimerStatus()
    }
}

// MARK: - Running Time Updates
extension CustomCameraTimer {
    func resetRunningTime() { configuration.setCurrentTimeToStart() }
    func skipRunningTime() { configuration.setCurrentTimeToEnd() }
}

// MARK: - Handling Timer
private extension CustomCameraTimer {
    func handleTimer(status: CustomCameraTimerStatus) { if status != .running || configuration.canTimerBeStarted {
        timerStatus = status
        updateInternalTimer(isTimerRunning)
        updateObservers(isTimerRunning)
        publishTimerStatus()
    }}
}
private extension CustomCameraTimer {
    func updateInternalTimer(_ start: Bool) {
        switch start {
            case true: updateInternalTimerStart()
            case false: updateInternalTimerStop()
    }}
    func updateObservers(_ start: Bool) {
        switch start {
            case true: addObservers()
            case false: removeObservers()
        }
    }
}
private extension CustomCameraTimer {
    func updateInternalTimerStart() { state.runTimer(configuration, self, #selector(handleTimeChange)) }
    func updateInternalTimerStop() { state.stopTimer() }
}

// MARK: - Handling Time Change
private extension CustomCameraTimer {
    @objc func handleTimeChange(_ timeChange: Any) {
        configuration.setNewCurrentTime(timeChange)
        stopTimerIfNecessary()
        publishRunningTimeChange()
    }
}
private extension CustomCameraTimer {
    func stopTimerIfNecessary() { if !configuration.canTimerBeStarted {
        finishTimer()
    }}
}

// MARK: - Handling Background Mode
private extension CustomCameraTimer {
    func addObservers() {
        NotificationCenter
            .addAppStateNotifications(self,
                                      onDidEnterBackground: #selector(didEnterBackgroundNotification),
                                      onWillEnterForeground: #selector(willEnterForegroundNotification))
    }
    func removeObservers() {
        NotificationCenter.removeAppStateChangedNotifications(self)
    }
}
private extension CustomCameraTimer {
    @objc func willEnterForegroundNotification() {
        handleReturnFromBackgroundWhenTimerIsRunning()
        state.willEnterForeground()
    }
    @objc func didEnterBackgroundNotification() {
        state.didEnterBackground()
    }
}
private extension CustomCameraTimer {
    func handleReturnFromBackgroundWhenTimerIsRunning() {
        guard let backgroundTransitionDate = state.backgroundTransitionDate, isTimerRunning else { return }
        let timeChange = Date().timeIntervalSince(backgroundTransitionDate)
        
        handleTimeChange(timeChange)
        resumeTimerAfterReturningFromBackground()
    }
}
private extension CustomCameraTimer {
    func resumeTimerAfterReturningFromBackground() { if configuration.canTimerBeStarted {
        updateInternalTimer(true)
    }}
}

// MARK: - Publishers
private extension CustomCameraTimer {
    func publishTimerStatus() {
        publishTimerStatusChange()
        publishRunningTimeChange()
    }
    func resetTimerPublishers() {
        guard isNeededReset else { return }
        timerStatus = .notStarted
        timerProgress = 0
        timerTime = .init(timeInterval: configuration.time.start)
    }
}

private extension CustomCameraTimer {
    func publishTimerStatusChange() { DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
        guard let self else { return }
        callbacks.onTimerStatusChange?(timerStatus)
    }}
    func publishRunningTimeChange() { DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
        guard let self else { return }
        callbacks.onRunningTimeChange?(.init(timeInterval: configuration.currentTime))
        callbacks.onTimerProgressChange?(configuration.getTimerProgress())
        timerTime = .init(timeInterval: configuration.currentTime)
        timerProgress = configuration.getTimerProgress()
    }}
}

// MARK: - Helpers
private extension CustomCameraTimer {
    var isTimerRunning: Bool { timerStatus.isTimerRunning }
    var isNeededReset: Bool { timerStatus.isNeededReset }
}
