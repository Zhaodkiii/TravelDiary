//
//  Public+CustomCameraTimerID.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.

/// Unique id that enables an access to the registered timer from any location.

import Combine

internal struct CustomCameraTimerID: Equatable, Sendable {
    internal let rawValue: String
    
    internal init(rawValue: String) { self.rawValue = rawValue }
}
