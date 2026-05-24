import XCTest

final class CoreMLTextModelAnalyzingTests: XCTestCase {

    // MARK: - Fallback

    func test_load_withInvalidURL_returnsNoOpTextModelAnalyzing() {
        let url = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")
        let backend = CoreMLTextModelAnalyzing.load(from: url)
        XCTAssert(backend is NoOpTextModelAnalyzing,
                  "Expected NoOpTextModelAnalyzing, got \(type(of: backend))")
    }
}
