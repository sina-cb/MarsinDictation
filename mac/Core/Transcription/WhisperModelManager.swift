import Foundation

/// Downloads missing models to Application Support, publishing only complete GGML files.
public final class WhisperModelManager {
    public static let shared = WhisperModelManager()
    private let directory: URL
    private let baseURL: URL
    private let session: URLSession

    public var modelsDirectory: URL { directory }

    init(directory: URL? = nil,
         baseURL: URL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main")!,
         session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first!.appendingPathComponent("MarsinDictation/models", isDirectory: true)
        self.baseURL = baseURL
        self.session = session
    }

    public func modelURL(for modelName: String) -> URL {
        if let bundled = Bundle.main.url(forResource: (modelName as NSString).deletingPathExtension,
                                         withExtension: (modelName as NSString).pathExtension) {
            return bundled
        }
        return directory.appendingPathComponent(modelName)
    }

    public func isModelAvailable(_ modelName: String) -> Bool {
        (try? validateModel(at: modelURL(for: modelName))) != nil
    }

    /// Rejects empty/HTML/partial-header downloads before handing them to the native engine.
    private func validateModel(at url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 4)
        let size = try file.seekToEnd()
        guard header == Data([0x6c, 0x6d, 0x67, 0x67]), size > 1024 else {
            throw TranscriptionError.apiError("Invalid speech model. Retry the download.")
        }
    }

    public func downloadModel(_ modelName: String,
                              progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        guard !modelName.isEmpty, modelName == (modelName as NSString).lastPathComponent,
              modelName.hasPrefix("ggml-"), modelName.hasSuffix(".bin"),
              modelName.unicodeScalars.allSatisfy({ CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }) else {
            throw TranscriptionError.apiError("Use a GGML model filename, not a path or URL.")
        }
        let destination = modelURL(for: modelName)
        if isModelAvailable(modelName) { return destination }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let delegate = ModelDownloadProgress(progress: progress)
        let (temporary, response) = try await session.download(
            from: baseURL.appendingPathComponent(modelName), delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TranscriptionError.apiError("Model download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Try again.")
        }
        try validateModel(at: temporary)
        // Replace a corrupt cached file only after a successful, validated download.
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return destination
    }
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate {
    private var lastUnit: Int64 = -1
    let progress: (Int64, Int64) -> Void
    init(progress: @escaping (Int64, Int64) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let unit = totalBytesExpectedToWrite > 0
            ? totalBytesWritten * 100 / totalBytesExpectedToWrite : totalBytesWritten / 1_000_000
        guard unit != lastUnit else { return }
        lastUnit = unit
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
