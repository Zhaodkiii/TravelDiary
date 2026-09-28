//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

@MainActor
public class SecondCameraEditorSelectionHapticFeedback {
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    public init() {
        SecondCameraEditorAssertIsOnMainThread()
        feedbackGenerator.prepare()
    }

    public func selectionChanged() {
        DispatchQueue.main.async {
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
    }
}

@MainActor
public class SecondCameraEditorNotificationHapticFeedback {
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    public init() {
        SecondCameraEditorAssertIsOnMainThread()
        feedbackGenerator.prepare()
    }

    public func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            self.feedbackGenerator.notificationOccurred(notificationType)
            self.feedbackGenerator.prepare()
        }
    }
}

public class SecondCameraEditorImpactHapticFeedback {

    public class func impactOccurred(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    public class func impactOccurred(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred(intensity: intensity)
        }
    }
}
