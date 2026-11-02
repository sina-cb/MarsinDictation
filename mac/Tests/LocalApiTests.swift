import XCTest
import Foundation
import Darwin
@testable import DictationTranscription

/// Exercises real loopback HTTP with synthetic PCM and fake inference; optional cached-model test runs offline.
final class LocalApiTests: XCTestCase {
    private final class InvocationCounter {
        let lock = NSLock(); var count = 0
        func value() -> Int { lock.lock(); defer { lock.unlock() }; return count }
        func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    }
    private func wav() -> Data {
        var data = Data("RIFF".utf8)
        func put(_ value: Int, _ count: Int) { for i in 0..<count { data.append(UInt8((value >> (8*i)) & 255)) } }
        put(38, 4); data.append(Data("WAVEfmt ".utf8)); put(16, 4); put(1, 2); put(1, 2)
        put(16000, 4); put(32000, 4); put(2, 2); put(16, 2); data.append(Data("data".utf8)); put(2, 4); put(0, 2)
        return data
    }
    private func call(_ port: UInt16, _ path: String = "/health", body: Data? = nil,
                      headers: [String: String] = [:], timeout: TimeInterval = 5) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.timeoutInterval = timeout
        if let body = body { req.httpMethod = "POST"; req.httpBody = body; req.setValue("audio/wav", forHTTPHeaderField: "Content-Type") }
        for (key,value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as! HTTPURLResponse).statusCode, try JSONSerialization.jsonObject(with: data) as! [String: Any])
    }
    private func expectStatus(_ expected: Int, _ actual: (Int, [String: Any])) async throws {
        XCTAssertEqual(actual.0, expected)
    }
    func testRoutesGuardsWavAndNoSpeech() async throws {
        let api = LocalTranscriptionApi(model: "/private/model.bin", language: "en", version: "test", modelAvailable: true,
            port: 16976, ready: { true }, transcribe: { _ in "hello" })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let health = try await call(16976);
        XCTAssertEqual(health.1["service"] as? String, "marsin-dictation")
        XCTAssertEqual(health.1["apiVersion"] as? Int, 1)
        XCTAssertEqual(health.1["backend"] as? String, "embedded-whisper")
        XCTAssertEqual(health.1["ready"] as? Bool, true)
         XCTAssertEqual(health.0, 200); XCTAssertEqual(health.1["model"] as? String, "model.bin")
        try await expectStatus(404, try await call(16976, "/missing"))
        try await expectStatus(403, try await call(16976, headers: ["Origin": "null"]))
        try await expectStatus(403, try await call(16976, headers: ["Host": "evil:16976"]))
        try await expectStatus(405, try await call(16976, "/transcribe"))
        try await expectStatus(400, try await call(16976, "/transcribe", body: Data([1,2])))
        let result = try await call(16976, "/transcribe", body: wav()); XCTAssertEqual(result.0, 200); XCTAssertEqual(result.1["text"] as? String, "hello")
        try await expectStatus(415, try await call(16976, "/transcribe", body: wav(), headers: ["Content-Type": "application/json"]))
    }
    func testMissingModelAndPortCollision() async throws {
        let api = LocalTranscriptionApi(model: "missing.bin", language: "en", version: "test", modelAvailable: false,
            port: 16977, ready: { true }, transcribe: { _ in XCTFail("Missing model must not infer/download"); return "" })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let collision = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: false,
            port: 16977, ready: { true }, transcribe: { _ in "" })
        XCTAssertFalse(collision.tryStart()); collision.stop()
        let health = try await call(16977); XCTAssertEqual(health.0, 503); XCTAssertEqual(health.1["reason"] as? String, "model_missing"); XCTAssertEqual(health.1["ready"] as? Bool, false)
        try await expectStatus(503, try await call(16977, "/transcribe", body: wav()))
    }
    func testBusyDeadlineAndShutdown() async throws {
        let counter = InvocationCounter()
        let api = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: true,
            port: 16978, requestSeconds: 0.15, ready: { true }, transcribe: { _ in
                if counter.next() == 1 {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { continuation.resume() }
                    }
                }
                return "complete"
            })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let first = Task { try await self.call(16978, "/transcribe", body: self.wav()) }
        try await Task.sleep(nanoseconds: 70_000_000)
        try await expectStatus(429, try await call(16978, "/transcribe", body: wav()))
        let timedOut = try await first.value; XCTAssertEqual(timedOut.0, 408)
        try await expectStatus(429, try await call(16978, "/transcribe", body: wav()))
        try await Task.sleep(nanoseconds: 550_000_000)
        try await expectStatus(200, try await call(16978, "/transcribe", body: wav()))
        api.stop()
        do { _ = try await call(16978); XCTFail("Stopped listener accepted a connection") } catch {}
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    private func raw(_ port: UInt16, _ request: String, endUpload: Bool = true, payload: Data = Data(), disconnect: Bool = false) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0); defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(connected, 0)
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        let bytes = Array(Data(request.utf8) + payload); _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        if disconnect { return "" }
        if endUpload { shutdown(fd, SHUT_WR) }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true { let n = recv(fd, &buffer, buffer.count, 0); if n <= 0 { break }; result.append(contentsOf: buffer.prefix(n)) }
        return String(decoding: result, as: UTF8.self)
    }

    func testRawUploadLimitsAndDeadlines() throws {
        let api = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: true,
            port: 16980, readSeconds: 0.15, ready: { true }, transcribe: { _ in "" })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let prefix = "POST /transcribe HTTP/1.1\r\nHost: 127.0.0.1:16980\r\nContent-Type: audio/wav\r\n"
        XCTAssertTrue(try raw(16980, prefix + "Transfer-Encoding: chunked\r\n\r\n").contains("411 Response"))
        XCTAssertTrue(try raw(16980, prefix + "Content-Length: 4194305\r\n\r\n").contains("audio_too_large"))
        XCTAssertTrue(try raw(16980, prefix + "Content-Length: 44\r\n\r\n").contains("incomplete_audio"))
        XCTAssertTrue(try raw(16980, prefix + "Content-Length: 44\r\n\r\n", endUpload: false).contains("transcription_timeout_or_shutdown"))
        XCTAssertTrue(try raw(16980, prefix + "Origin : null\r\nContent-Length: 0\r\n\r\n").contains("400 Response"))
        XCTAssertTrue(try raw(16980, prefix + "Origin: null\r\nOrigin: null\r\nContent-Length: 0\r\n\r\n").contains("400 Response"))
    }

    func testNoSpeechFailureAndBusyResult() async throws {
        for (index, status) in [422, 503, 429].enumerated() {
            let port = UInt16(16981 + index)
            let api = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: true,
                port: port, ready: { true }, transcribe: { _ in
                    if status == 503 { throw TranscriptionError.invalidEncoding }
                    return status == 429 ? nil : "[no audio]"
                })
            XCTAssertTrue(api.tryStart())
            try await expectStatus(status, try await call(port, "/transcribe", body: wav()))
            api.stop()
        }
    }


    func testDisconnectRetainsAdmissionAndFastRequestsRecover() async throws {
        let counter = InvocationCounter()
        let api = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: true,
            port: 16984, ready: { true }, transcribe: { _ in
                if counter.next() == 1 {
                    await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { continuation.resume() } }
                }
                return "hello"
            })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let body = wav()
        _ = try raw(16984, "POST /transcribe HTTP/1.1\r\nHost: 127.0.0.1:16984\r\nContent-Type: audio/wav\r\nContent-Length: \(body.count)\r\n\r\n", payload: body, disconnect: true)
        for _ in 0..<100 { if counter.value() > 0 { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(counter.value(), 1)
        try await expectStatus(429, try await call(16984, "/transcribe", body: body))
        try await Task.sleep(nanoseconds: 450_000_000)
        for _ in 0..<25 { try await expectStatus(200, try await call(16984, "/transcribe", body: body)) }
    }


    func testStopExactlyBeforeTaskRegistrationPreventsInference() async throws {
        let inferred = InvocationCounter(); let stopped = InvocationCounter()
        let api = LocalTranscriptionApi(model: "x", language: "en", version: "test", modelAvailable: true,
            port: 16986, ready: { true }, transcribe: { _ in _ = inferred.next(); return "unexpected" })
        api.beforeTaskRegistration = { api.beforeTaskRegistration = nil; api.stop(); _ = stopped.next() }
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        do { _ = try await call(16986, "/transcribe", body: wav()) } catch {}
        for _ in 0..<100 { if stopped.value() > 0 { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(stopped.value(), 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(inferred.value(), 0, "Shutdown before registration must cancel before inference starts")
    }

    func testWavAncillaryAndMalformedChunks() {
        let base = wav(); XCTAssertEqual(LocalTranscriptionApi.normalizedWav(base), base)
        var extra = base; extra.insert(contentsOf: Array("JUNK".utf8) + [1,0,0,0,9,0], at: 12); extra[4] += 10
        XCTAssertEqual(LocalTranscriptionApi.normalizedWav(extra), base)
        for index in [0,4,8,20,22,24,28,32,34,40] {
            var bad = base; bad[index] ^= 255; XCTAssertNil(LocalTranscriptionApi.normalizedWav(bad), "offset \(index)")
        }
        XCTAssertNil(LocalTranscriptionApi.normalizedWav(Data()))
    }
    func testOfflineExistingModelThroughHttpAndSharedGate() async throws {
        guard let model = ProcessInfo.processInfo.environment["MODEL_TEST_REAL_MODEL"] else { throw XCTSkip("Set MODEL_TEST_REAL_MODEL for offline inference") }
        // CI uses MODEL_TEST_AUDIO for its separate testing/dictation sentence.
        let audio = ProcessInfo.processInfo.environment["API_TEST_AUDIO"] ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("windows/MarsinDictation.Tests/TestData/FirstHello.wav").path
        let url = URL(fileURLWithPath: model)
        let client = WhisperTranscriptionClient.shared(modelURL: url)
        XCTAssertTrue(client === WhisperTranscriptionClient.shared(modelURL: url))
        try client.loadModel()
        let config = TranscriptionConfig(endpoint: "", apiKey: nil, model: url.lastPathComponent, language: "en")
        let api = LocalTranscriptionApi(model: model, language: "en", version: "test", modelAvailable: true,
            port: 16979, ready: { client.isModelLoaded }, transcribe: { try await client.tryTranscribe(wavData: $0, config: config) })
        XCTAssertTrue(api.tryStart()); defer { api.stop() }
        let wav = try Data(contentsOf: URL(fileURLWithPath: audio))
        let desktop = Task { try await client.transcribe(wavData: wav, config: config) }
        for _ in 0..<200 { if client.isInferenceBusy { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(client.isInferenceBusy)
        try await expectStatus(429, try await call(16979, "/transcribe", body: wav))
        _ = try await desktop.value
        let apiRequest = Task { try await self.call(16979, "/transcribe", body: wav, timeout: 135) }
        for _ in 0..<200 { if client.isInferenceBusy { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(client.isInferenceBusy)
        let completed = InvocationCounter()
        let waitingDesktop = Task { let text = try await client.transcribe(wavData: wav, config: config); _ = completed.next(); return text }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(completed.next(), 1, "Desktop inference must still wait behind API owner")
        let result = try await apiRequest.value
        _ = try await waitingDesktop.value
        XCTAssertEqual(result.0, 200)
        let text = (result.1["text"] as? String ?? "").lowercased()
        XCTAssertTrue(text.contains("hello")); XCTAssertTrue(text.contains("world"))
        let expiring = LocalTranscriptionApi(model: model, language: "en", version: "test", modelAvailable: true,
            port: 16985, requestSeconds: 0.05, ready: { client.isModelLoaded },
            transcribe: { try await client.tryTranscribe(wavData: $0, config: config) })
        XCTAssertTrue(expiring.tryStart()); defer { expiring.stop() }
        try await expectStatus(408, try await call(16985, "/transcribe", body: wav))
        // Native cancellation is cooperative; keep ownership until completion, within the API/client budget.
        let releaseDeadline = ProcessInfo.processInfo.systemUptime + 135
        while client.isInferenceBusy && ProcessInfo.processInfo.systemUptime < releaseDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(client.isInferenceBusy, "Native cancelled inference must eventually release the shared gate")
        try await expectStatus(200, try await call(16979, "/transcribe", body: wav, timeout: 135))
    }
}
