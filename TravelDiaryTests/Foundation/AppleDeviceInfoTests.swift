import Testing
@testable import TravelDiary

@MainActor struct AppleDeviceInfoTests {
    @Test func resolvesKnownDuoAndUnknownModels() {
        #expect(AppleDeviceInfo.modelName(for: "iPhone19,2") == "iPhone 18 Pro")
        #expect(AppleDeviceInfo.modelName(for: "iPhone19,4") == "iPhone Duo")
        #expect(AppleDeviceInfo.modelName(for: "FutureDevice,99") == "FutureDevice,99")
        #expect(AppleDeviceInfo.isDuo(modelIdentifier: "iPhone19,4"))
        #expect(!AppleDeviceInfo.isDuo(modelIdentifier: "iPhone19,2"))
        #expect(SupportSystemInfo.shared.deviceModel == AppleDeviceInfo.modelIdentifier)
        #expect(SupportSystemInfo.shared.deviceModelName == AppleDeviceInfo.modelName)
    }
}
