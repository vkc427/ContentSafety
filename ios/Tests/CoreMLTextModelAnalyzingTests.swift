import XCTest
import CoreML
import NaturalLanguage

final class CoreMLTextModelAnalyzingTests: XCTestCase {

    // MARK: - Fallback

    func test_load_withInvalidURL_returnsNoOpTextModelAnalyzing() {
        let url = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")
        let backend = CoreMLTextModelAnalyzing.load(from: url)
        XCTAssert(backend is NoOpTextModelAnalyzing,
                  "Expected NoOpTextModelAnalyzing, got \(type(of: backend))")
    }

    // MARK: - Confidence (requires TestContentSafetyTextClassifier.mlmodelc in test bundle)

    private func makeFixtureBackend() -> CoreMLTextModelAnalyzing? {
        let bundle = Bundle(for: CoreMLTextModelAnalyzingTests.self)
        guard let url = bundle.url(forResource: "TestContentSafetyTextClassifier",
                                   withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: mlModel) else {
            return nil
        }
        return CoreMLTextModelAnalyzing(model: nlModel)
    }

    func test_confidence_returnsDoubleInZeroToOneRange() {
        guard let backend = makeFixtureBackend() else {
            XCTFail("Fixture model not found — run: xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift fixture && xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")
            return
        }
        let score = backend.confidence(for: "some text here")
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func test_confidence_emptyString_returnsZero() throws {
        guard let backend = makeFixtureBackend() else {
            throw XCTSkip("Fixture model not found — run: xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift fixture && xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")
        }
        // NLModel returns an empty dict for empty input; subscript ["unsafe"] → nil → 0.0
        let score = backend.confidence(for: "")
        XCTAssertEqual(score, 0.0)
    }

    func test_confidence_benignText_returnsInRange() throws {
        guard let backend = makeFixtureBackend() else {
            throw XCTSkip("Fixture model not found — run: xcrun --sdk macosx swift -framework CreateML scripts/train_text_classifier.swift fixture && xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")
        }
        let score = backend.confidence(for: "the quick brown fox")
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
}
