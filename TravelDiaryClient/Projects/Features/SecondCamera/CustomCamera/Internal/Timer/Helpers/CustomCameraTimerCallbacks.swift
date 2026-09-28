//
//  CustomCameraTimerCallbacks.swift
//  MijickTimer
//
//  Created by Alina Petrovska
//    - Mail: alina.petrovska@mijick.com
//    - GitHub: https://github.com/Mijick
//
//  Copyright ©2024 Mijick. All rights reserved.



import Combine
import SwiftUI

class CustomCameraTimerCallbacks {
    var onRunningTimeChange: ((CustomCameraTime) -> ())?
    var onTimerStatusChange: ((CustomCameraTimerStatus) -> ())?
    var onTimerProgressChange: ((Double) -> ())?
}
