import Foundation
import Testing
@testable import TravelDiary

@MainActor struct DiaryAIRuntimeTests {
    private func envelope(task: UUID, adapter: String = "ark_responses_v1", endpoint: String = "https://provider.example/responses", parameters: [String: Any] = [:]) throws -> DiaryAITaskRuntime.Configuration {
        let object: [String: Any] = ["schema_version": 1, "task_id": task.uuidString, "release_id": UUID().uuidString,
            "config_hash": "test", "control_version": 1, "server_time": 0, "lease_expires_at": 900,
            "scenes": ["diary.layout": ["adapter_id": adapter, "provider_id": "p", "endpoint": endpoint, "model_id": "m", "credential_slot_id": "s", "parameters": parameters, "limits": ["request_timeout_seconds": 180]]],
            "credentials": ["s": ["version": 1, "auth_scheme": "bearer", "secret": "test-only-credential"]]]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(DiaryAITaskRuntime.Configuration.self, from: JSONSerialization.data(withJSONObject: object))
    }
    @Test func acceptsSupportedConfigurationAndKeepsParameterKeys() throws {
        let task = UUID()
        let value = try envelope(task: task, parameters: ["max_output_tokens": 1024, "thinking": ["type": "disabled"]])
        try DiaryAITaskRuntime.validate(value, task: task)
        #expect(value.scenes["diary.layout"]?.parameters["max_output_tokens"] != nil)
    }
    @Test func rejectsAnotherTaskOrUnknownProtocol() throws {
        let task = UUID(), value = try envelope(task: task)
        #expect(throws: (any Error).self) { try DiaryAITaskRuntime.validate(value, task: UUID()) }
        let unsupported = try envelope(task: task, adapter: "unimplemented")
        #expect(throws: (any Error).self) { try DiaryAITaskRuntime.validate(unsupported, task: task) }
    }
    @Test func rejectsCredentialInURLAndUnsafeParameters() throws {
        for address in ["http://provider.example/api", "https://user@provider.example/api", "https://provider.example/api?key=secret"] {
            let task = UUID(), value = try envelope(task: task, endpoint: address)
            #expect(throws: (any Error).self) { try DiaryAITaskRuntime.validate(value, task: task) }
        }
        for parameters: [String: Any] in [["headers": ["Authorization": "secret"]], ["max_output_tokens": 999999], ["max_output_tokens": true], ["thinking": ["type": "arbitrary"]]] {
            let task = UUID(), value = try envelope(task: task, parameters: parameters)
            #expect(throws: (any Error).self) { try DiaryAITaskRuntime.validate(value, task: task) }
        }
    }
    @Test func unboundRuntimeNeverProvidesCredentials() async {
        let runtime = DiaryAITaskRuntime()
        await #expect(throws: (any Error).self) { try await runtime.access("diary.layout") }
    }
}
