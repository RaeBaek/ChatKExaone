import Foundation

nonisolated enum ExaoneAPI {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    private struct RequestBody: Encodable {
        let model: String
        let reasoningEffort: String
        let stream: Bool
        let messages: [ChatMessage]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta
            let finishReason: String?
        }

        let choices: [Choice]
    }

    private enum APIError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case incompleteStream
        case generationLimit
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "서버 응답을 확인할 수 없습니다."
            case .httpStatus(401):
                return "인증에 실패했습니다. API 키를 확인하세요."
            case .httpStatus(429):
                return "요청 한도에 도달했습니다. 잠시 후 다시 시도하세요."
            case .httpStatus(let status):
                return "API 요청에 실패했습니다 (HTTP \(status))."
            case .incompleteStream:
                return "답변을 끝까지 받지 못했습니다. 다시 시도해 주세요."
            case .generationLimit:
                return "서버의 생성 한도에 도달해 답변이 중단되었습니다."
            case .emptyReply:
                return "최종 답변이 비어 있습니다. 메시지를 다시 보내보세요."
            }
        }
    }

    @concurrent
    static func reply(
        to messages: [ChatMessage],
        apiKey: String,
        onPartialReply: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let url = URL(string: "https://api.exaone.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            RequestBody(model: "k-exaone_v2.5", reasoningEffort: "low", stream: true, messages: messages)
        )

        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }

        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.httpStatus(response.statusCode)
        }
        guard response.mimeType == "text/event-stream" else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let clock = ContinuousClock()
        var lastUpdate: ContinuousClock.Instant?
        var reply = ""
        var finishReason: String?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty else { continue }

            if payload == "[DONE]" {
                if finishReason == "length" {
                    throw APIError.generationLimit
                }
                guard finishReason == "stop" else { throw APIError.incompleteStream }
                let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw APIError.emptyReply }
                await onPartialReply(answer)
                return answer
            }

            guard let chunk = try? decoder.decode(StreamChunk.self, from: Data(payload.utf8)) else {
                throw APIError.invalidResponse
            }
            guard let choice = chunk.choices.first else { continue }
            if let reason = choice.finishReason {
                finishReason = reason
            }
            guard let content = choice.delta.content, !content.isEmpty else { continue }

            reply.append(content)
            let now = clock.now
            if lastUpdate.map({ $0.duration(to: now) >= .milliseconds(80) }) ?? true {
                await onPartialReply(reply)
                lastUpdate = now
            }
        }
        throw APIError.incompleteStream
    }
}
