import Foundation

public class GenericTranscriptionClient: ITranscriptionClient {
    public init() {}
    
    public func transcribe(wavData: Data, config: TranscriptionConfig) async throws -> String {
        guard let url = URL(string: config.endpoint) else {
            throw TranscriptionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let token = config.apiKey, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Append model
        body.append(String(format: "--%@\r\n", boundary).data(using: .utf8)!)
        body.append(String(format: "Content-Disposition: form-data; name=\"model\"\r\n\r\n").data(using: .utf8)!)
        body.append(String(format: "%@\r\n", config.model).data(using: .utf8)!)
        
        // Append language if any
        if let lang = config.language, !lang.isEmpty {
            body.append(String(format: "--%@\r\n", boundary).data(using: .utf8)!)
            body.append(String(format: "Content-Disposition: form-data; name=\"language\"\r\n\r\n").data(using: .utf8)!)
            body.append(String(format: "%@\r\n", lang).data(using: .utf8)!)
        }
        
        // Append file
        body.append(String(format: "--%@\r\n", boundary).data(using: .utf8)!)
        body.append(String(format: "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n").data(using: .utf8)!)
        body.append(String(format: "Content-Type: audio/wav\r\n\r\n").data(using: .utf8)!)
        body.append(wavData)
        body.append(String(format: "\r\n").data(using: .utf8)!)
        
        // Close boundary
        body.append(String(format: "--%@--\r\n", boundary).data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.networkError(NSError(domain: "Network", code: 0, userInfo: nil))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown HTTP Error \(httpResponse.statusCode)"
            throw TranscriptionError.apiError(errorString)
        }
        
        struct Response: Decodable {
            let text: String
        }
        
        let decoder = JSONDecoder()
        do {
            let res = try decoder.decode(Response.self, from: data)
            let final = res.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if final.isEmpty {
                throw TranscriptionError.emptyResponse
            }
            return final
        } catch {
            throw TranscriptionError.invalidEncoding
        }
    }
}
