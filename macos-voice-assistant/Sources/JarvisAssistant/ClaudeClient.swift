import Foundation

/// Minimal Anthropic Messages API client with a tool-use agent loop: send the user's spoken
/// command, and if Claude responds with tool_use blocks, execute them locally via `ToolExecutor`
/// and send the results back, repeating until Claude returns a plain text reply or the iteration
/// cap is hit.
struct ClaudeClient {
    let apiKey: String
    let model: String
    let maxIterations: Int
    private let session = URLSession(configuration: .default)

    func converse(
        userText: String,
        systemPrompt: String,
        tools: [ToolDefinition],
        serverTools: [[String: Any]],
        executor: ToolExecutor
    ) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": userText]]
        var iterations = 0

        while iterations < maxIterations {
            iterations += 1
            let response = try await callMessagesAPI(messages: messages, system: systemPrompt, tools: tools, serverTools: serverTools)

            guard let content = response["content"] as? [[String: Any]] else {
                throw JarvisError.malformedResponse
            }

            var toolUses: [[String: Any]] = []
            var textParts: [String] = []
            for block in content {
                guard let type = block["type"] as? String else { continue }
                if type == "text", let text = block["text"] as? String {
                    textParts.append(text)
                } else if type == "tool_use" {
                    toolUses.append(block)
                }
            }

            let stopReason = response["stop_reason"] as? String

            // A server-side tool (like web search) ran but hit its internal iteration limit; re-send
            // the assistant turn as-is so Anthropic resumes it — no tool result to add on our side.
            if stopReason == "pause_turn" {
                messages.append(["role": "assistant", "content": content])
                continue
            }

            if stopReason != "tool_use" || toolUses.isEmpty {
                return textParts.joined(separator: "\n")
            }

            messages.append(["role": "assistant", "content": content])

            var resultBlocks: [[String: Any]] = []
            for use in toolUses {
                guard let id = use["id"] as? String, let name = use["name"] as? String else { continue }
                let input = use["input"] as? [String: Any] ?? [:]
                let output = await executor.execute(name: name, input: input)

                if let imageBase64 = output.imageBase64 {
                    // Image-bearing result (e.g. a screenshot): send text + image content blocks.
                    let content: [[String: Any]] = [
                        ["type": "text", "text": output.text],
                        ["type": "image", "source": [
                            "type": "base64",
                            "media_type": output.imageMediaType ?? "image/png",
                            "data": imageBase64
                        ]]
                    ]
                    resultBlocks.append(["type": "tool_result", "tool_use_id": id, "content": content])
                } else {
                    resultBlocks.append(["type": "tool_result", "tool_use_id": id, "content": output.text])
                }
            }
            messages.append(["role": "user", "content": resultBlocks])
        }

        return "I hit my step limit working on that, so it may only be partially done."
    }

    private func callMessagesAPI(
        messages: [[String: Any]],
        system: String,
        tools: [ToolDefinition],
        serverTools: [[String: Any]]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": messages,
            // Client-executed tools plus any Anthropic-hosted server tools (e.g. web search).
            "tools": tools.map { $0.jsonSchema } + serverTools
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            throw JarvisError.apiError(text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JarvisError.malformedResponse
        }
        return json
    }
}
