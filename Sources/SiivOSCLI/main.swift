import Foundation
import SiivOSCore

// siivos-cli: the agent door. It answers questions about this Mac for an AI agent the
// user already uses, and only ever reads. All of its logic is in SiivOSCore (AgentDoor),
// where it is covered by tests; this file only passes the words along.

// Agents read English best, and get the same words on every Mac.
L10n.overrideLanguage = .english

// Some questions take a while on a full disk. Lines saying what is being looked at go
// to the error stream, so a person sees that the tool is working while the answer on
// the output stream stays clean JSON for the agent.
let door = AgentDoor.standard { line in
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
let reply = door.answer(Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data((reply.output + "\n").utf8))
exit(reply.exitCode)
