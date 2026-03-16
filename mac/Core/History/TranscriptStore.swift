import Foundation

public enum TranscriptState: String, Codable {
    case success
    case pending
    case failed_transcription
}

public struct Transcript: Identifiable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let provider: String
    public let model: String
    public var state: TranscriptState
    
    public init(id: UUID = UUID(), createdAt: Date = Date(), text: String, provider: String, model: String, state: TranscriptState) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.provider = provider
        self.model = model
        self.state = state
    }
}

public class TranscriptStore: ObservableObject {
    @Published public var transcripts: [Transcript] = []
    
    public static let shared = TranscriptStore()
    
    private init() {}
    
    public func save(_ transcript: Transcript) {
        DispatchQueue.main.async {
            self.transcripts.insert(transcript, at: 0)
        }
    }
    
    public func popPending() -> Transcript? {
        // Find the first pending transcript
        if let index = transcripts.firstIndex(where: { $0.state == .pending }) {
            let pending = transcripts[index]
            DispatchQueue.main.async {
                self.transcripts[index].state = .success
            }
            return pending
        }
        return nil
    }
    
    public func getLastSuccessful() -> Transcript? {
        return transcripts.first(where: { $0.state == .success })
    }
}
