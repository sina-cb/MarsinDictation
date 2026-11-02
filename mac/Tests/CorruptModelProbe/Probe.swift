import Foundation
@testable import DictationTranscription

/// Intentionally runs native corrupt-model initialization outside the test runner process.
@main struct CorruptModelProbe {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Public base.en architecture header, with tensor/vocabulary contents deliberately absent.
        // This is synthetic, not any user's audio/model. All fixtures pass the shallow GGML cache check.
        for mode in ["truncated", "unsupported-ftype", "removed-after-preflight"] {
            let values = [1734831468, 51864, 1500, 512, 8, 6, 448, 512, 8, 6, 80, mode == "unsupported-ftype" ? 999 : 1]
            var model = Data()
            for value in values { for i in 0..<4 { model.append(UInt8((value >> (i*8)) & 255)) } }
            // Complete public-format prefix; no synthetic tensor data is ever handed to native code.
            for value in [80, 201] { for i in 0..<4 { model.append(UInt8((value >> (i*8)) & 255)) } }
            model.append(Data(repeating: 0, count: mode == "truncated" ? 4096 : 128 * 1024))
            let url = directory.appendingPathComponent("ggml-corrupt.bin")
            try model.write(to: url)
            let client = WhisperTranscriptionClient(modelURL: url)
            if mode == "removed-after-preflight" {
                client.beforeNativeLoad = { try! FileManager.default.removeItem(at: url) }
            }
            do { try client.loadModel(); fatalError("Corrupt model was accepted") }
            catch { guard !client.isModelLoaded else { fatalError("Failed model became ready") } }
            let api = LocalTranscriptionApi(model: url.lastPathComponent, language: "en", version: "probe",
                modelAvailable: true, port: 16987, ready: { client.isModelLoaded },
                transcribe: { _ in fatalError("Unloaded model inferred") })
            guard api.tryStart() else { fatalError("Probe port unavailable") }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:16987/transcribe")!)
            request.httpMethod = "POST"; request.httpBody = Data([0]); request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 503,
                  String(decoding: data, as: UTF8.self).contains("embedded_model_not_ready") else {
                fatalError("Unloaded model did not return503")
            }
            api.stop()
        }
        print("PASS: truncated/unsupported GGML metadata and native NULL after controlled temporary-file removal were handled; host survived and API returned503")
    }
}
