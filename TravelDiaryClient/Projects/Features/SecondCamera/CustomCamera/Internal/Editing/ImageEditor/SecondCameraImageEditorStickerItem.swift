//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

final class SecondCameraImageEditorStickerItem: SecondCameraImageEditorItem, SecondCameraImageEditorTransformable {
    let sticker: SecondCameraEditorSticker
    /// The timestamp for when the sticker item was created. Used for displaying clock stickers.
    ///
    /// This timestamp is stored so that the time displayed on a clock sticker
    /// does not change from when it's placed on the image to when it's
    /// rendered in the final image.
    let date: Date
    let referenceImageWidth: CGFloat
    let unitCenter: SecondCameraImageEditorSample
    let rotationRadians: CGFloat
    let scaling: CGFloat

    init(
        sticker: SecondCameraEditorSticker,
        referenceImageWidth: CGFloat,
        unitCenter: SecondCameraImageEditorSample = .unitMidpoint,
        rotationRadians: CGFloat,
        scaling: CGFloat,
    ) {
        self.sticker = sticker
        self.date = Date()
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemType: .sticker)
    }

    private init(
        itemId: String,
        sticker: SecondCameraEditorSticker,
        date: Date,
        referenceImageWidth: CGFloat,
        unitCenter: SecondCameraImageEditorSample,
        rotationRadians: CGFloat,
        scaling: CGFloat,
    ) {
        self.sticker = sticker
        self.date = date
        self.referenceImageWidth = referenceImageWidth
        self.unitCenter = unitCenter
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        super.init(itemId: itemId, itemType: .sticker)
    }

    func copy(unitCenter: SecondCameraImageEditorSample) -> SecondCameraImageEditorStickerItem {
        SecondCameraImageEditorStickerItem(
            itemId: self.itemId,
            sticker: self.sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: unitCenter,
            rotationRadians: self.rotationRadians,
            scaling: self.scaling,
        )
    }

    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> SecondCameraImageEditorStickerItem {
        SecondCameraImageEditorStickerItem(
            itemId: self.itemId,
            sticker: self.sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: self.unitCenter,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(sticker: SecondCameraEditorSticker) -> SecondCameraImageEditorStickerItem {
        SecondCameraImageEditorStickerItem(
            itemId: self.itemId,
            sticker: sticker,
            date: self.date,
            referenceImageWidth: self.referenceImageWidth,
            unitCenter: self.unitCenter,
            rotationRadians: self.rotationRadians,
            scaling: self.scaling,
        )
    }

    override func outputScale() -> CGFloat {
        return scaling
    }
}
