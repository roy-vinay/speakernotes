import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Finds the phrases an instruction refers to ("the names of the engines"), using Apple's on-device
/// language model (macOS 26 with Apple Intelligence). The notes never leave the Mac.
enum Assistant {
    /// Nil when the model is ready; otherwise a short reason it can't be used.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac can't run Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to use instructions."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready. Try again in a few minutes."
            case .unavailable:
                return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "Instructions need macOS 26 with Apple Intelligence."
    }

    static var isAvailable: Bool { unavailableReason == nil }

    /// Reads each passage in turn and returns the phrases that match the instruction, copied exactly
    /// from the passages. Phrases the model makes up (not found in the passage) are dropped.
    static func findPhrases(_ instruction: String, in passages: [String],
                            progress: @escaping (Int) -> Void) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await PhraseFinder().run(instruction, passages, progress)
        }
        #endif
        return []
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct PhraseMatches {
    @Guide(description: "Exact phrases copied from the passage, with the same spelling and capitalization, that the instruction asks for. Keep each one short: a name or a few words, not a whole sentence unless the instruction asks for sentences.")
    var phrases: [String]
}

@available(macOS 26.0, *)
struct PhraseFinder {
    static let instructions = """
        You help a presenter mark up their speaker notes. You get an instruction and a passage from the notes. \
        Return the phrases from the passage that the instruction refers to, copied exactly as they appear. \
        If nothing in the passage matches, return an empty list. Never invent phrases that are not in the passage.
        """

    func run(_ instruction: String, _ passages: [String], _ progress: @escaping (Int) -> Void) async throws -> [String] {
        var found: [String] = []
        for (i, passage) in passages.enumerated() {
            try Task.checkCancellation()
            progress(i)
            let trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // A fresh session for each passage keeps every request well inside the model's context.
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = "Instruction: \(instruction)\n\nPassage:\n\(String(trimmed.prefix(6000)))"
            do {
                let response = try await session.respond(to: prompt, generating: PhraseMatches.self)
                for phrase in response.content.phrases {
                    let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'“”‘’*")))
                    guard p.count >= 2, trimmed.range(of: p, options: .caseInsensitive) != nil,
                          !found.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) else { continue }
                    found.append(p)
                }
            } catch let error as LanguageModelSession.GenerationError {
                // One passage the model declines or can't fit shouldn't stop the rest.
                if case .exceededContextWindowSize = error { continue }
                if case .guardrailViolation = error { continue }
                if case .refusal = error { continue }
                throw error
            }
        }
        progress(passages.count)
        return found
    }
}
#endif
