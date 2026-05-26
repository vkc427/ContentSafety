import ExpoModulesCore

public class ContentSafetyModule: Module {
    @available(iOS 17.0, *)
    private lazy var imageAnalyzer = ImageAnalyzer()

    @available(iOS 17.0, *)
    private lazy var videoAnalyzer = VideoAnalyzer()

    private lazy var textAnalyzer = TextAnalyzer()
    private let analyzerQueue = DispatchQueue(label: "expo.content-safety.text-analyzer")

    public func definition() -> ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            let threshold = options["threshold"] as? Double ?? 0.7
            guard scaEntitlementPresent() else {
                return ["isNSFW": false, "confidence": 0.0, "threshold": threshold,
                        "source": "apple-sca", "durationMs": 0]
            }
            guard let self else {
                throw ImageAnalyzerError.inferenceFailed("Module deallocated")
            }
            return try await self.imageAnalyzer.analyze(uri: uri, threshold: threshold)
        }

        AsyncFunction("detectVideo") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            let threshold      = options["threshold"]      as? Double ?? 0.7
            let sampleRate     = options["sampleRate"]     as? Double ?? 1.0
            let maxFrames      = options["maxFrames"]      as? Int    ?? 30
            let stopOnFirstHit = options["stopOnFirstHit"] as? Bool   ?? true
            guard scaEntitlementPresent() else {
                return ["isNSFW": false, "confidence": 0.0, "threshold": threshold,
                        "source": "apple-sca", "durationMs": 0, "framesAnalyzed": 0]
            }
            guard let self else {
                throw VideoAnalyzerError.inferenceFailed("Module deallocated")
            }
            return try await self.videoAnalyzer.analyze(
                uri:            uri,
                threshold:      threshold,
                sampleRate:     sampleRate,
                maxFrames:      maxFrames,
                stopOnFirstHit: stopOnFirstHit
            )
        }

        AsyncFunction("detectText") { [weak self] (input: String, options: [String: Any]) async throws -> [String: Any] in
            let threshold    = options["threshold"]    as? Double   ?? 0.7
            let extraTerms   = options["blocklist"]    as? [String] ?? []
            let useBlocklist = options["useBlocklist"] as? Bool     ?? true
            let useModel     = options["useModel"]     as? Bool     ?? true
            guard let self else {
                throw TextAnalyzerError.inferenceFailed("Module deallocated")
            }
            let analyzer = self.analyzerQueue.sync { self.textAnalyzer }
            return try analyzer.analyze(
                input:        input,
                threshold:    threshold,
                useBlocklist: useBlocklist,
                useModel:     useModel,
                extraTerms:   extraTerms
            )
        }

        AsyncFunction("warmup") { [weak self] (options: [String: Any]?) async -> Void in
            guard let self else { return }
            if let modelPath = options?["modelPath"] as? String {
                let url: URL
                if modelPath.hasPrefix("file://") {
                    let stripped = String(modelPath.dropFirst("file://".count))
                    url = URL(string: modelPath) ?? URL(fileURLWithPath: stripped)
                } else {
                    url = URL(fileURLWithPath: modelPath)
                }
                let backend = CoreMLTextModelAnalyzing.load(from: url)
                self.analyzerQueue.sync { self.textAnalyzer = TextAnalyzer(modelBackend: backend) }
            }
            _ = self.analyzerQueue.sync { self.textAnalyzer }
            guard #available(iOS 17, *), scaEntitlementPresent() else { return }
            _ = self.imageAnalyzer
            _ = self.videoAnalyzer
        }
    }
}
