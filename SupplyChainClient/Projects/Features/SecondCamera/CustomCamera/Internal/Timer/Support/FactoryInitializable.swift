//
//  FactoryInitializable.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



import Combine
import SwiftUI

@MainActor protocol FactoryInitializable { }

extension FactoryInitializable where Self: CustomCameraTimer {
    /// Registers or returns registered Timer
     internal init(_ id: CustomCameraTimerID) {
         let timer = CustomCameraTimer(identifier: id)
         let registeredTimer = CustomCameraTimerContainer.register(timer)
         self = registeredTimer as! Self
    }
}
