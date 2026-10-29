import XCTest
@testable import DictationTranscription

/// Real local HTTP and filesystem tests; synthetic speech optionally exercises the real engine.
final class ModelTests: XCTestCase {
    private func fixture() throws -> (WhisperModelManager, URL) {
        guard let base = ProcessInfo.processInfo.environment["MODEL_TEST_BASE_URL"] else {
            throw XCTSkip("Run python3 devtool/test_mac_models.py to start the local HTTP fixture")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (WhisperModelManager(directory: directory, baseURL: URL(string: base)!), directory)
    }

    func testDownloadThenReuseOfflineCache() async throws {
        let (manager, dir) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        print("SETUP: Empty model directory, local HTTP fixture. EXPECT: download once, reuse without network.")
        let url = try await manager.downloadModel("ggml-valid.bin") { _, _ in }
        XCTAssertTrue(manager.isModelAvailable("ggml-valid.bin"))
        let offline = WhisperModelManager(directory: dir, baseURL: URL(string: "http://127.0.0.1:1")!)
        let cached = try await offline.downloadModel("ggml-valid.bin") { _, _ in XCTFail("Cached model must not download") }
        XCTAssertEqual(cached, url)
        print("PASS: Missing model downloaded; cached model reused with unreachable server.")
    }

    func testInvalidAndHTTPFailuresLeaveNoInstalledModel() async throws {
        let (manager, dir) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["ggml-html.bin", "ggml-missing.bin", "ggml-short.bin"] {
            do { _ = try await manager.downloadModel(name) { _, _ in }; XCTFail("Expected failure: \(name)") }
            catch { XCTAssertFalse(FileManager.default.fileExists(atPath: manager.modelURL(for: name).path)) }
        }
        print("PASS: HTML, truncated header and HTTP 404 never became installed model files.")
    }

    func testCorruptCacheIsReplaced() async throws {
        let (manager, dir) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("incomplete".utf8).write(to: manager.modelURL(for: "ggml-valid.bin"))
        XCTAssertFalse(manager.isModelAvailable("ggml-valid.bin"))
        _ = try await manager.downloadModel("ggml-valid.bin") { _, _ in }
        XCTAssertTrue(manager.isModelAvailable("ggml-valid.bin"))
        print("PASS: Invalid cache replaced by validated download.")
    }

    func testFailedDownloadCanRetry() async throws {
        let (manager, dir) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        do { _ = try await manager.downloadModel("ggml-retry.bin") { _, _ in }; XCTFail("Expected initial HTTP 503") }
        catch { XCTAssertFalse(manager.isModelAvailable("ggml-retry.bin")) }
        _ = try await manager.downloadModel("ggml-retry.bin") { _, _ in }
        XCTAssertTrue(manager.isModelAvailable("ggml-retry.bin"))
        print("PASS: Transient HTTP failure recovered on next attempt.")
    }

    func testRejectsPathsAndURLs() async throws {
        let (manager, dir) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["../ggml-valid.bin", "/ggml-valid.bin", "https://example.com/model.bin", ""] {
            do { _ = try await manager.downloadModel(name) { _, _ in }; XCTFail("Expected invalid filename") }
            catch {}
        }
        print("PASS: Model settings cannot choose a download URL or escape the cache directory.")
    }

    func testRealSyntheticSpeech() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let model = env["MODEL_TEST_REAL_MODEL"], let audio = env["MODEL_TEST_AUDIO"] else {
            throw XCTSkip("Provide MODEL_TEST_REAL_MODEL and MODEL_TEST_AUDIO for real-engine verification")
        }
        let client = WhisperTranscriptionClient(modelURL: URL(fileURLWithPath: model))
        try client.loadModel()
        let text = try await client.transcribe(wavData: Data(contentsOf: URL(fileURLWithPath: audio)),
            config: TranscriptionConfig(endpoint: "embedded", apiKey: nil, model: "ggml-base.en.bin", language: "en"))
        XCTAssertTrue(text.lowercased().contains("testing"), "Synthetic test sentence should contain testing")
        XCTAssertTrue(text.lowercased().contains("dictation"), "Synthetic test sentence should contain dictation")
        print("PASS: Real engine transcribed generated test speech; no microphone or cloud service used.")
    }
}
