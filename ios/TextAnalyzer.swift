import Foundation

// MARK: - Protocol for model path (plug in CoreML later)

protocol TextModelAnalyzing {
    func confidence(for text: String) -> Double
}

// No-op implementation used when no model is bundled
final class NoOpTextModelAnalyzing: TextModelAnalyzing {
    func confidence(for text: String) -> Double { 0.0 }
}

// MARK: - Error types

enum TextAnalyzerError: Error, LocalizedError {
    case invalidInput(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):    return "INVALID_INPUT: \(msg)"
        case .inferenceFailed(let msg): return "INFERENCE_FAILED: \(msg)"
        }
    }
}

// MARK: - TextAnalyzer

final class TextAnalyzer {
    private let blocklistPatterns: [NSRegularExpression]
    private let modelBackend: TextModelAnalyzing

    init(blocklistURL: URL? = TextAnalyzer.defaultBlocklistURL(),
         modelBackend: TextModelAnalyzing = CoreMLTextModelAnalyzing.default) {
        self.modelBackend = modelBackend
        self.blocklistPatterns = TextAnalyzer.loadBlocklist(from: blocklistURL)
    }

    func analyze(
        input: String,
        threshold: Double,
        useBlocklist: Bool,
        useModel: Bool,
        extraTerms: [String]
    ) throws -> [String: Any] {
        guard !input.isEmpty else {
            throw TextAnalyzerError.invalidInput("input must be a non-empty string")
        }

        let start = ProcessInfo.processInfo.systemUptime
        let normalized = TextAnalyzer.normalize(input)

        var blocklistScore = 0.0
        if useBlocklist {
            let extraPatterns = extraTerms.compactMap { TextAnalyzer.makePattern(for: $0) }
            let allPatterns = blocklistPatterns + extraPatterns
            blocklistScore = TextAnalyzer.blocklistScore(normalized: normalized, patterns: allPatterns)
        }

        let modelScore = useModel ? modelBackend.confidence(for: normalized) : 0.0

        let confidence = max(blocklistScore, modelScore)
        let source: String
        if modelScore > blocklistScore && useModel {
            source = "tflite-text"
        } else {
            source = "blocklist"
        }

        let durationMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)

        return [
            "isNSFW":     confidence >= threshold,
            "confidence": confidence,
            "threshold":  threshold,
            "source":     source,
            "durationMs": durationMs,
        ]
    }

    // MARK: - Private helpers

    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        let subs: [(Character, Character)] = [
            ("0", "o"), ("1", "i"), ("3", "e"),
            ("4", "a"), ("5", "s"), ("@", "a"), ("$", "s"),
        ]
        for (from, to) in subs {
            s = s.replacingOccurrences(of: String(from), with: String(to))
        }
        return s
    }

    static func blocklistScore(normalized: String, patterns: [NSRegularExpression]) -> Double {
        let range = NSRange(normalized.startIndex..., in: normalized)
        for pattern in patterns {
            if pattern.firstMatch(in: normalized, range: range) != nil {
                return 1.0
            }
        }
        return 0.0
    }

    static func makePattern(for term: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: term.lowercased())
        return try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive)
    }

    static func loadBlocklist(from url: URL?) -> [NSRegularExpression] {
        guard let url = url,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { makePattern(for: $0) }
    }

    static func defaultBlocklistURL() -> URL? {
        // Look in the module bundle (bundled via podspec s.resources)
        let bundle = Bundle(for: TextAnalyzer.self)
        return bundle.url(forResource: "blocklist", withExtension: "txt")
    }
}
