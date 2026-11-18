import Foundation

/// Offers the agent door's questions as tools over the Model Context Protocol (MCP), the
/// way many AI agents connect to helpers on the same computer.
///
/// The agent starts `siivos-cli mcp` itself and talks to it through the tool's input and
/// output: one message of JSON per line each way. Nothing listens on the network. Every
/// tool is one of the door's read-only questions, so the same rules hold: nothing is
/// changed, and nothing about the Mac is answered while the door is off.
public struct AgentDoorServer: Sendable {
    /// The versions of the protocol this server can speak, newest last.
    static let protocolVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]

    private let door: AgentDoor

    public init(door: AgentDoor) {
        self.door = door
    }

    /// The questions offered as tools. Help is for people, and status is useful to an
    /// agent too, so everything but help is here.
    static var toolCommands: [AgentDoor.Command] {
        AgentDoor.Command.allCases.filter { $0 != .help && $0 != .mcp }
    }

    static func toolName(for command: AgentDoor.Command) -> String {
        "siivos_" + command.rawValue
    }

    /// The numbers a question accepts, with what each means.
    private static func numberOptions(for command: AgentDoor.Command) -> [(name: String, meaning: String)] {
        switch command {
        case .changes:
            return [("days", "How many days back to look. 30 if left out.")]
        case .cleanup:
            return [("limit", "How many items to list in each group, largest first. 20 if left out.")]
        case .apps:
            return [("limit", "How many apps to list, largest first. 25 if left out.")]
        default:
            return []
        }
    }

    // MARK: - Answering

    /// Answers one line from the agent. Returns the line to send back, or `nil` when the
    /// message needs no answer.
    public func respond(to line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let message = parsed as? [String: Any]
        else {
            return Self.failure(id: NSNull(), code: -32700, message: "This is not a JSON message.")
        }
        guard let method = message["method"] as? String else {
            // A reply to something this server never asked. Nothing to do.
            return nil
        }
        guard let id = message["id"] else {
            // A notification, such as "notifications/initialized". No answer is expected.
            return nil
        }
        let parameters = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return Self.success(id: id, result: initialize(parameters))
        case "ping":
            return Self.success(id: id, result: [String: Any]())
        case "tools/list":
            return Self.success(id: id, result: ["tools": Self.toolDescriptions()])
        case "tools/call":
            guard let name = parameters["name"] as? String,
                  let command = Self.toolCommands.first(where: { Self.toolName(for: $0) == name })
            else {
                return Self.failure(id: id, code: -32602, message: "SiivOS has no such tool.")
            }
            return Self.success(id: id, result: call(command, arguments: parameters["arguments"] as? [String: Any] ?? [:]))
        default:
            return Self.failure(id: id, code: -32601, message: "SiivOS does not know the method \(method).")
        }
    }

    private func initialize(_ parameters: [String: Any]) -> [String: Any] {
        // Speak the agent's version when this server knows it, otherwise its own newest.
        let asked = parameters["protocolVersion"] as? String
        let version = asked.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[Self.protocolVersions.count - 1]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "siivos", "version": AgentDoor.version],
            "instructions": "SiivOS looks after this Mac: clutter, apps, performance, protection and a health timeline. These tools only read. They cannot remove or change anything; to remove something, tell the person to open SiivOS, where every change is explained first and can be undone. Items labelled checkFirst are the person's own files or may hold their work, so never suggest removing them without the person looking first. If a tool says the agent door is off, the person has to turn it on in SiivOS's Settings."
        ]
    }

    private static func toolDescriptions() -> [[String: Any]] {
        toolCommands.map { command in
            var properties: [String: Any] = [:]
            for option in numberOptions(for: command) {
                properties[option.name] = ["type": "integer", "minimum": 1, "description": option.meaning]
            }
            return [
                "name": toolName(for: command),
                "description": command.summary + " Read-only.",
                "inputSchema": [
                    "type": "object",
                    "properties": properties,
                    "additionalProperties": false
                ] as [String: Any],
                "annotations": ["readOnlyHint": true]
            ]
        }
    }

    private func call(_ command: AgentDoor.Command, arguments: [String: Any]) -> [String: Any] {
        var words = [command.rawValue]
        for option in Self.numberOptions(for: command) {
            if let value = arguments[option.name] as? Int {
                words += ["--" + option.name, String(value)]
            } else if let value = arguments[option.name] as? Double {
                words += ["--" + option.name, String(Int(value))]
            }
        }
        let reply = door.answer(words)
        return [
            "content": [["type": "text", "text": reply.output]],
            "isError": reply.exitCode != 0
        ]
    }

    // MARK: - Writing messages

    private static func success(id: Any, result: [String: Any]) -> String? {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func failure(id: Any, code: Int, message: String) -> String? {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]])
    }

    /// One message on one line, as the protocol asks.
    private static func write(_ message: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
