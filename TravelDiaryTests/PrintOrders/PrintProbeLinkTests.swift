import Foundation
import Testing
@testable import TravelDiary

@MainActor
struct PrintProbeLinkTests {
    @Test func launchUsesCanonicalUUIDsForRouteAndToken() throws {
        let id = "4B7D4462-DB95-421B-8E3C-47FB18DBC40A"
        let token = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let url = try #require(URL(string: "traveldiary-paytest://launch?id=\(id)&token=\(token)&origin=https%3A%2F%2Fdiary.dreamwhale.top"))
        let link = try #require(PrintProbeLink(url))
        let request = try link.launchRequest()
        #expect(request.url?.absoluteString == "https://diary.dreamwhale.top/api/v1/print/payment-probes/\(id.lowercased())/launch/")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(body?["token"] == token.lowercased())
    }

    @Test func refusesSendingTokenToOtherOrigins() throws {
        let id = UUID().uuidString
        for origin in ["http://diary.dreamwhale.top", "https://example.com", "https://diary.dreamwhale.top:8443", "https://user@diary.dreamwhale.top"] {
            var parts = URLComponents(string: "traveldiary-paytest://launch")!
            parts.queryItems = [.init(name: "id", value: id), .init(name: "token", value: id), .init(name: "origin", value: origin)]
            #expect(PrintProbeLink(try #require(parts.url)) == nil)
        }
    }
}
