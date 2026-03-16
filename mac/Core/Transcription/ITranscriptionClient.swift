import Foundation

public struct TranscriptionConfig {
    public let endpoint: String
    public let apiKey: String?
    public let model: String
    public let language: String?
    
    public init(endpoint: String, apiKey: String?, model: String, language: String?) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }
}

public protocol ITranscriptionClient {
    func transcribe(wavData: Data, config: TranscriptionConfig) async throws -> String
}

public enum TranscriptionError: Error {
    case invalidURL
    case networkError(Error)
    case apiError(String)
    case emptyResponse
    case invalidEncoding
}
