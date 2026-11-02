import Foundation
import Darwin

/// A bounded, upload-only HTTP/1.1 listener. No desktop, storage, or downloader dependencies.
public final class LocalTranscriptionApi {
    public static let maxBodyBytes = 4 * 1024 * 1024
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var connections = Set<Int32>()
    private var busy = false
    private var activeTask: Task<Void, Never>?
    #if DEBUG
    internal var beforeTaskRegistration: (() -> Void)?
    #endif
    private var stopped = false
    private let port: UInt16
    private let model: String
    private let language: String
    private let version: String
    private let available: Bool
    private let ready: () -> Bool
    private let transcribe: (Data) async throws -> String?
    private let readSeconds: Double
    private let requestSeconds: Double

    public init(model: String, language: String, version: String, modelAvailable: Bool,
                port: UInt16 = 6976, readSeconds: Double = 10, requestSeconds: Double = 120,
                ready: @escaping () -> Bool, transcribe: @escaping (Data) async throws -> String?) {
        self.model = (model as NSString).lastPathComponent
        self.language = language; self.version = version; available = modelAvailable
        self.port = port; self.ready = ready; self.transcribe = transcribe
        self.readSeconds = readSeconds; self.requestSeconds = requestSeconds
    }

    public func tryStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard listener < 0, !stopped else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return false }
        listener = fd
        DispatchQueue.global().async { [self] in acceptLoop(fd) }
        return true
    }

    public func stop() {
        lock.lock(); stopped = true
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
        activeTask?.cancel()
        for fd in connections { shutdown(fd, SHUT_RDWR) }
        lock.unlock()
    }

    private static func waitForRegistration(_ start: DispatchSemaphore) { start.wait() }

    private func releaseAdmission() {
        lock.lock(); defer { lock.unlock() }
        busy = false; activeTask = nil
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { break }
            lock.lock()
            if stopped || connections.count >= 16 { lock.unlock(); close(client); continue }
            connections.insert(client); lock.unlock()
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
            DispatchQueue.global().async { [self] in handle(client) }
        }
    }

    private func finish(_ fd: Int32) {
        lock.lock(); connections.remove(fd); close(fd); lock.unlock()
    }

    private func reply(_ fd: Int32, _ status: Int, _ body: [String: Any]) {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var output = Data(header.utf8); output.append(payload)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        output.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if sent <= 0 { break }; offset += sent
            }
        }
    }

    private func read(_ fd: Int32, count: Int, deadline: Date) throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw WireError.timeout }
            var timeout = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining.truncatingRemainder(dividingBy: 1)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            var buffer = [UInt8](repeating: 0, count: min(8192, count - result.count))
            let amount = recv(fd, &buffer, buffer.count, 0)
            if amount == 0 { throw WireError.incomplete }
            if amount < 0 { throw WireError.timeout }
            result.append(contentsOf: buffer.prefix(amount))
        }
        return result
    }
    private enum WireError: Error { case timeout, incomplete }

    private func handle(_ fd: Int32) {
        var handedOff = false
        defer { if !handedOff { finish(fd) } }
        func respondError(_ status: Int, _ code: String) { reply(fd, status, ["error": code]) }
        do {
            let headerDeadline = Date().addingTimeInterval(readSeconds)
            var header = Data()
            while !header.suffix(4).elementsEqual([13, 10, 13, 10]) {
                guard header.count < 16384 else { respondError(400, "invalid_request"); return }
                header.append(try read(fd, count: 1, deadline: headerDeadline))
            }
            guard let string = String(data: header, encoding: .utf8) else { respondError(400, "invalid_request"); return }
            let lines = string.components(separatedBy: "\r\n")
            let request = lines[0].split(separator: " ")
            guard request.count == 3, request[2] == "HTTP/1.1" else { respondError(400, "invalid_request"); return }
            var fields: [String: String] = [:]
            for line in lines.dropFirst() where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { respondError(400, "invalid_request"); return }
                let key = line[..<colon].lowercased()
                guard !key.isEmpty, key.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }) else { respondError(400, "invalid_request"); return }
                guard fields[key] == nil else { respondError(400, "invalid_request"); return }
                fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard fields["host"] == "127.0.0.1:\(port)", fields["origin"] == nil,
                  fields["sec-fetch-site"] == nil || fields["sec-fetch-site"] == "none" else {
                respondError(403, "local_client_required"); return
            }
            let path = request[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
            if path == "/health", request[0] == "GET" {
                let loaded = available && ready()
                reply(fd, loaded ? 200 : 503, ["service": "marsin-dictation", "apiVersion": 1,
                    "version": version, "backend": "embedded-whisper", "model": model, "language": language,
                    "ready": loaded, "reason": loaded ? NSNull() : (available ? "model_loading_or_failed" : "model_missing")])
                return
            }
            guard path == "/transcribe" else { respondError(404, "not_found"); return }
            guard request[0] == "POST" else { respondError(405, "post_required"); return }
            guard fields["content-type"]?.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased() == "audio/wav" else { respondError(415, "audio_wav_required"); return }
            guard fields["transfer-encoding"] == nil, let lengthString = fields["content-length"],
                  !lengthString.isEmpty, lengthString.allSatisfy({ $0.isASCII && $0.isNumber }), let length = Int(lengthString) else { respondError(411, "content_length_required"); return }
            guard length <= Self.maxBodyBytes else { respondError(413, "audio_too_large"); return }
            guard available && ready() else { respondError(503, "embedded_model_not_ready"); return }
            lock.lock()
            if busy || stopped { lock.unlock(); respondError(429, "transcription_busy"); return }
            busy = true; lock.unlock()
            let deadline = Date().addingTimeInterval(requestSeconds)
            do {
                let wav = try read(fd, count: length, deadline: min(deadline, Date().addingTimeInterval(readSeconds)))
                guard let normalized = Self.normalizedWav(wav) else {
                    lock.lock(); busy = false; lock.unlock(); respondError(400, "pcm16_mono_16000_wav_required"); return
                }
                handedOff = true
                let response = ResponseDeadline(api: self, fd: fd)
                DispatchQueue.global().asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow)) { response.timeout() }
                let start = DispatchSemaphore(value: 0)
                let task = Task { [self] in
                    Self.waitForRegistration(start)
                    defer { releaseAdmission(); response.complete() }
                    do {
                        try Task.checkCancellation()
                        let text = try await transcribe(normalized)
                        try Task.checkCancellation()
                        if let text = text {
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == "[no audio]" { response.send(422, ["error": "no_speech_recognized"]) }
                            else { response.send(200, ["text": text, "backend": "embedded-whisper", "model": model, "language": language, "version": version]) }
                        } else { response.send(429, ["error": "transcription_busy"]) }
                    } catch is CancellationError { response.timeout() }
                    catch TranscriptionError.emptyResponse { response.send(422, ["error": "no_speech_recognized"]) }
                    catch {
                        if Task.isCancelled { response.timeout() }
                        else { response.send(503, ["error": "embedded_transcription_failed"]) }
                    }
                }
                #if DEBUG
                beforeTaskRegistration?()
                #endif
                response.setTask(task)
                lock.lock(); activeTask = task; let cancel = stopped; lock.unlock()
                if cancel { task.cancel() }
                start.signal()
            } catch {
                lock.lock(); busy = false; lock.unlock(); throw error
            }
        } catch WireError.incomplete { respondError(400, "incomplete_audio") }
        catch { respondError(408, "transcription_timeout_or_shutdown") }
    }

    /// Deadline closes only the HTTP connection; native inference retains its gate until completion.
    private final class ResponseDeadline {
        private let lock = NSLock()
        private let api: LocalTranscriptionApi
        private let fd: Int32
        private var closed = false
        private var task: Task<Void, Never>?
        private var expired = false
        init(api: LocalTranscriptionApi, fd: Int32) { self.api = api; self.fd = fd }
        func send(_ status: Int, _ body: [String: Any]) {
            lock.lock(); defer { lock.unlock() }
            guard !closed else { return }
            api.reply(fd, status, body); api.finish(fd); closed = true
        }
        func setTask(_ task: Task<Void, Never>) {
            lock.lock(); self.task = task; let cancel = expired; lock.unlock()
            if cancel { task.cancel() }
        }
        func timeout() {
            lock.lock(); expired = true; let active = task; lock.unlock()
            active?.cancel()
            send(408, ["error": "transcription_timeout_or_shutdown"])
        }
        func complete() {
            lock.lock(); defer { lock.unlock() }
            task = nil
            if !closed { api.finish(fd); closed = true }
        }
    }

    /// Validates the Windows API RIFF contract and emits a canonical 44-byte header for the engine.
    public static func normalizedWav(_ wav: Data) -> Data? {
        let bytes = [UInt8](wav)
        func number(_ offset: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        func tag(_ offset: Int, _ value: String) -> Bool { Array(bytes[offset..<offset+4]) == Array(value.utf8) }
        guard bytes.count >= 44, bytes.count <= maxBodyBytes, tag(0, "RIFF"), tag(8, "WAVE"), number(4, 4) == bytes.count - 8 else { return nil }
        var format = false; var pcm: Data?; var position = 12
        while position <= bytes.count - 8 {
            let start = position; let length = number(position + 4, 4); position += 8
            guard length <= bytes.count - position else { return nil }
            if tag(start, "fmt ") {
                guard !format, length >= 16, number(position, 2) == 1, number(position+2, 2) == 1,
                      number(position+4, 4) == 16000, number(position+8, 4) == 32000,
                      number(position+12, 2) == 2, number(position+14, 2) == 16 else { return nil }
                format = true
            }
            if tag(start, "data") {
                guard format, pcm == nil, length > 0, length % 2 == 0, length <= 120 * 32000 else { return nil }
                pcm = Data(bytes[position..<position+length])
            }
            position += length + length % 2
        }
        guard format, let pcm = pcm, position == bytes.count else { return nil }
        var result = Data("RIFF".utf8)
        func append(_ value: Int, _ count: Int) { for i in 0..<count { result.append(UInt8((value >> (8*i)) & 255)) } }
        append(pcm.count + 36, 4); result.append(Data("WAVEfmt ".utf8)); append(16, 4)
        append(1, 2); append(1, 2); append(16000, 4); append(32000, 4); append(2, 2); append(16, 2)
        result.append(Data("data".utf8)); append(pcm.count, 4); result.append(pcm)
        return result
    }
}
