//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//


// SecondCameraImageEditorContents represents a snapshot of canvas
// state.
//
// Instances of SecondCameraImageEditorContents should be treated
// as immutable, once configured.
class SecondCameraImageEditorContents {

    typealias ItemMapType = SecondCameraEditorOrderedDictionary<String, SecondCameraImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    private(set) var itemMap: ItemMapType

    // Used to clone copies of instances of this class.
    init(itemMap: ItemMapType? = nil) {
        self.itemMap = itemMap ?? ItemMapType()
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    func clone() -> SecondCameraImageEditorContents {
        return SecondCameraImageEditorContents(itemMap: itemMap)
    }

    func item(forId itemId: String) -> SecondCameraImageEditorItem? {
        return itemMap[itemId]
    }

    func append(item: SecondCameraImageEditorItem) {
        itemMap.append(key: item.itemId, value: item)
    }

    func replace(item: SecondCameraImageEditorItem) {
        itemMap.replace(key: item.itemId, value: item)
    }

    func remove(item: SecondCameraImageEditorItem) {
        itemMap.remove(key: item.itemId)
    }

    func remove(itemId: String) {
        itemMap.remove(key: itemId)
    }

    func itemCount() -> Int {
        return itemMap.count
    }

    func items() -> [SecondCameraImageEditorItem] {
        return itemMap.orderedValues
    }

    func itemIds() -> [String] {
        return itemMap.orderedKeys
    }
}
