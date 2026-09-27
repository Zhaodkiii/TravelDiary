//
//  Public+CustomCameraTimerError.swift
//
//  Created by Tomasz Kurylik
//    - Twitter: https://twitter.com/tkurylik
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//
//  Copyright ©2023 Mijick. All rights reserved.




import Combine
import Foundation

internal enum CustomCameraTimerError: Error {
    case publisherTimeCannotBeLessThanZero
    case startTimeCannotBeTheSameAsEndTime, timeCannotBeLessThanZero
    case cannotResumeNotInitialisedTimer
    case timerIsAlreadyRunning, timerIsNotStarted
}
