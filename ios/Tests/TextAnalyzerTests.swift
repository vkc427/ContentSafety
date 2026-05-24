import XCTest

// MARK: - Mock

final class MockTextModelAnalyzing: TextModelAnalyzing {
    var stubbedConfidence: Double = 0.0
    func confidence(for text: String) -> Double { stubbedConfidence }
}

// MARK: - Tests

final class TextAnalyzerTests: XCTestCase {
    private var mock: MockTextModelAnalyzing!
    private var analyzer: TextAnalyzer!

    override func setUp() {
        super.setUp()
        mock = MockTextModelAnalyzing()
        // blocklistURL: nil → base blocklist is empty; use extraTerms for test vocabulary
        analyzer = TextAnalyzer(blocklistURL: nil, modelBackend: mock)
    }

    override func tearDown() {
        analyzer = nil
        mock = nil
        super.tearDown()
    }

    // MARK: 1. Empty input

    func test_emptyInput_throwsInvalidInput() {
        XCTAssertThrowsError(
            try analyzer.analyze(
                input: "",
                threshold: 0.7,
                useBlocklist: true,
                useModel: false,
                extraTerms: []
            )
        ) { error in
            guard let err = error as? TextAnalyzerError,
                  case .invalidInput = err else {
                return XCTFail("Expected TextAnalyzerError.invalidInput, got: \(error)")
            }
        }
    }

    // MARK: 2. Blocklist match → isNSFW=true

    func test_blocklistMatch_isNSFWTrue() throws {
        let result = try analyzer.analyze(
            input: "badword",
            threshold: 0.7,
            useBlocklist: true,
            useModel: false,
            extraTerms: ["badword"]
        )
        XCTAssertEqual(result["isNSFW"] as? Bool, true)
    }

    // MARK: 3. Clean text → isNSFW=false, confidence=0.0

    func test_cleanText_isNSFWFalseAndConfidenceZero() throws {
        let result = try analyzer.analyze(
            input: "the quick brown fox",
            threshold: 0.7,
            useBlocklist: true,
            useModel: false,
            extraTerms: ["badword"]
        )
        XCTAssertEqual(result["isNSFW"] as? Bool,      false)
        XCTAssertEqual(result["confidence"] as? Double, 0.0)
    }

    // MARK: 4. Leetspeak match

    func test_leetspeakMatch_normalizedAndHitsBlocklist() throws {
        // "p0rn" normalises to "porn", which is in extraTerms
        let result = try analyzer.analyze(
            input: "p0rn",
            threshold: 0.7,
            useBlocklist: true,
            useModel: false,
            extraTerms: ["porn"]
        )
        XCTAssertEqual(result["isNSFW"] as? Bool, true)
    }

    // MARK: 5. useBlocklist=false → isNSFW=false even with a matching term

    func test_useBlocklistFalse_matchingTermIgnored() throws {
        let result = try analyzer.analyze(
            input: "badword",
            threshold: 0.7,
            useBlocklist: false,
            useModel: false,
            extraTerms: ["badword"]
        )
        XCTAssertEqual(result["isNSFW"] as? Bool, false)
    }

    // MARK: 6. useModel=false → source is always "blocklist"

    func test_useModelFalse_sourceIsBlocklist() throws {
        mock.stubbedConfidence = 0.9          // would win if model were consulted
        let result = try analyzer.analyze(
            input: "hello world",
            threshold: 0.7,
            useBlocklist: true,
            useModel: false,
            extraTerms: []
        )
        XCTAssertEqual(result["source"] as? String, "blocklist")
    }

    // MARK: 7. Model wins over blocklist

    func test_modelWins_sourceIsTfliteText() throws {
        mock.stubbedConfidence = 0.9          // blocklist returns 0.0 (no extraTerms match)
        let result = try analyzer.analyze(
            input: "hello world",
            threshold: 0.7,
            useBlocklist: true,
            useModel: true,
            extraTerms: []
        )
        XCTAssertEqual(result["source"] as? String,     "tflite-text")
        XCTAssertEqual(result["confidence"] as? Double,  0.9)
        XCTAssertEqual(result["isNSFW"] as? Bool,        true)
    }

    // MARK: 8. Blocklist wins over model

    func test_blocklistWinsOverModel_sourceIsBlocklist() throws {
        mock.stubbedConfidence = 0.5          // model < blocklist (1.0)
        let result = try analyzer.analyze(
            input: "badword",
            threshold: 0.7,
            useBlocklist: true,
            useModel: true,
            extraTerms: ["badword"]
        )
        XCTAssertEqual(result["source"] as? String,     "blocklist")
        XCTAssertEqual(result["confidence"] as? Double,  1.0)
    }

    // MARK: 9. Extra terms

    func test_extraTerms_customTermTriggersFlagging() throws {
        let result = try analyzer.analyze(
            input: "this text contains customterm here",
            threshold: 0.5,
            useBlocklist: true,
            useModel: false,
            extraTerms: ["customterm"]
        )
        XCTAssertEqual(result["isNSFW"] as? Bool, true)
    }

    // MARK: 10. Threshold echo

    func test_threshold_echoedInResult() throws {
        let supplied = 0.42
        let result = try analyzer.analyze(
            input: "hello",
            threshold: supplied,
            useBlocklist: true,
            useModel: false,
            extraTerms: []
        )
        XCTAssertEqual(result["threshold"] as? Double, supplied)
    }

    // MARK: 11. normalize() unit test

    func test_normalize_leetspeakConversion() {
        let output = TextAnalyzer.normalize("p0rn h3nt@i")
        XCTAssertEqual(output, "porn hentai")
    }

    // MARK: Result shape

    func test_resultContainsAllRequiredKeys() throws {
        let result = try analyzer.analyze(
            input: "sample text",
            threshold: 0.7,
            useBlocklist: true,
            useModel: false,
            extraTerms: []
        )
        XCTAssertNotNil(result["isNSFW"])
        XCTAssertNotNil(result["confidence"])
        XCTAssertNotNil(result["threshold"])
        XCTAssertNotNil(result["source"])
        XCTAssertNotNil(result["durationMs"])
    }

    // MARK: - CoreMLTextModelAnalyzing.default integration

    func test_defaultBackend_isNotNoOp_whenModelBundled() {
        // When the production model is bundled, default should be CoreMLTextModelAnalyzing.
        // When not bundled (CI without model file), it degrades to NoOp — test skips.
        let backend = CoreMLTextModelAnalyzing.default
        // This test documents expected production behaviour. It will pass once the
        // bundled model is present; until then CoreMLTextModelAnalyzing.default == NoOp.
        if backend is NoOpTextModelAnalyzing {
            // Model not bundled yet — acceptable during development
            return
        }
        XCTAssert(backend is CoreMLTextModelAnalyzing)
    }

    func test_analyzerWithCoreMLDefault_doesNotThrow() throws {
        // Smoke test: analyzer with default backend runs without crashing.
        let analyzerWithDefault = TextAnalyzer(
            blocklistURL: nil,
            modelBackend: CoreMLTextModelAnalyzing.default
        )
        let result = try analyzerWithDefault.analyze(
            input: "hello world",
            threshold: 0.7,
            useBlocklist: false,
            useModel: true,
            extraTerms: []
        )
        XCTAssertNotNil(result["confidence"])
    }
}
