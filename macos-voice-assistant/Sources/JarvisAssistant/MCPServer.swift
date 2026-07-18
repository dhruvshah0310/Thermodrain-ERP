import Foundation

/// A minimal Model Context Protocol (MCP) server over stdio, exposing Jarvis's Mac-control tools
/// so an MCP client such as Claude Desktop can operate the Mac directly. This is what lets you
/// talk (or type) to Claude and have it drive your computer through Jarvis's tools.
///
/// It speaks newline-delimited JSON-RPC 2.0 on stdin/stdout. IMPORTANT: only JSON-RPC messages may
/// go to stdout — all logging goes to stderr (see Logger) so the protocol stream stays clean.
///
/// Reuses the exact same `ToolExecutor` and tool definitions as the voice assistant, so every
/// capability (open apps, AppleScript, mouse, screenshot, type/paste, files, clipboard, and —
/// if enabled in config — shell) is available to the MCP client. Web search/fetch are NOT exposed
/// here because those are the MCP client's own responsibility (Claude already has its own web
/// tools); this server only offers the local, client-executed Mac tools.
final class MCPServer {
    private let config: Config
    private let executor: ToolExecutor
    private let tools: [ToolDefinition]

    init() {
        config = Config.load()
        executor = ToolExecutor(config: config)
        tools = JarvisTools.allTools(config: config)
        try? FileManager.default.createDirectory(at: config.workspaceURL, withIntermediateDirectories: true)
    }

    /// Blocking run loop. Reads one JSON-RPC message per line until stdin closes.
    func run() {
        Logger.shared.log("MCP server started (stdio). Exposing \(tools.count) Mac-control tools.")
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            guard
                let data = line.data(using: .utf8),
                let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            handle(message: message)
        }
        Logger.shared.log("MCP server stdin closed; exiting.")
    }

    private func handle(message: [String: Any]) {
        let method = message["method"] as? String
        let id = message["id"] // Int, String, or nil (a notification has no id)

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "jarvis-mac-control", "version": "1.0.0"]
            ])
        case "notifications/initialized", "notifications/cancelled":
            break // notifications get no response
        case "ping":
            respond(id: id, result: [String: Any]())
        case "tools/list":
            let list = tools.map { tool -> [String: Any] in
                ["name": tool.name, "description": tool.description, "inputSchema": tool.inputSchema]
            }
            respond(id: id, result: ["tools": list])
        case "tools/call":
            handleToolCall(id: id, params: message["params"] as? [String: Any] ?? [:])
        default:
            if id != nil {
                respondError(id: id, code: -32601, message: "Method not found: \(method ?? "nil")")
            }
        }
    }

    private func handleToolCall(id: Any?, params: [String: Any]) {
        guard let name = params["name"] as? String else {
            respondError(id: id, code: -32602, message: "Missing tool name")
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        // Bridge the async actor call into this synchronous stdio loop.
        let semaphore = DispatchSemaphore(value: 0)
        var toolResult: ToolResult?
        Task {
            toolResult = await executor.execute(name: name, input: arguments)
            semaphore.signal()
        }
        semaphore.wait()

        guard let result = toolResult else {
            respondError(id: id, code: -32603, message: "Tool execution returned no result")
            return
        }

        var content: [[String: Any]] = [["type": "text", "text": result.text]]
        if let image = result.imageBase64 {
            content.append([
                "type": "image",
                "data": image,
                "mimeType": result.imageMediaType ?? "image/png"
            ])
        }
        respond(id: id, result: ["content": content, "isError": false])
    }

    private func respond(id: Any?, result: [String: Any]) {
        var message: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { message["id"] = id }
        write(message)
    }

    private func respondError(id: Any?, code: Int, message: String) {
        var payload: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { payload["id"] = id }
        write(payload)
    }

    private func write(_ object: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}
