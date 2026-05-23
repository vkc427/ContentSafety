import XCTest

// MARK: - Mock

@available(iOS 17.0, *)
final class MockImageSensitivityAnalyzing: ImageSensitivityAnalyzing {
    var stubbedResult: Bool = false
    var stubbedError: Error?
    var capturedURL: URL?

    func isSensitive(url: URL) async throws -> Bool {
        capturedURL = url
        if let err = stubbedError { throw err }
        return stubbedResult
    }
}

// MARK: - Tests

@available(iOS 17.0, *)
final class ImageAnalyzerTests: XCTestCase {
    private var mock: MockImageSensitivityAnalyzing!
    private var analyzer: ImageAnalyzer!

    override func setUp() {
        super.setUp()
        mock = MockImageSensitivityAnalyzing()
        analyzer = ImageAnalyzer(underlying: mock)
    }

    // Writes an empty file to tmp and returns its file:// URL string.
    private func makeTempFile(name: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try Data().write(to: url)
        return url.absoluteString
    }

    // MARK: URI validation

    func test_emptyURI_throwsInvalidInput() async throws {
        do {
            _ = try await analyzer.analyze(uri: "", threshold: 0.7)
            XCTFail("Expected throw")
        } catch let err as ImageAnalyzerError {
            guard case .invalidInput = err else { return XCTFail("Wrong case: \(err)") }
        }
    }

    func test_httpsURI_throwsInvalidInput() async throws {
        do {
            _ = try await analyzer.analyze(uri: "https://example.com/img.jpg", threshold: 0.7)
            XCTFail("Expected throw")
        } catch let err as ImageAnalyzerError {
            guard case .invalidInput = err else { return XCTFail("Wrong case: \(err)") }
        }
    }

    func test_nonexistentFile_throwsInvalidInput() async throws {
        do {
            _ = try await analyzer.analyze(uri: "file:///nonexistent/no-such-file.png", threshold: 0.7)
            XCTFail("Expected throw")
        } catch let err as ImageAnalyzerError {
            guard case .invalidInput = err else { return XCTFail("Wrong case: \(err)") }
        }
    }

    // MARK: Result shape — SFW

    func test_sfwResult_allFieldsPresent() async throws {
        mock.stubbedResult = false
        let uri = try makeTempFile(name: "sfw_\(#function).png")

        let result = try await analyzer.analyze(uri: uri, threshold: 0.7)

        XCTAssertEqual(result["isNSFW"] as? Bool,   false)
        XCTAssertEqual(result["confidence"] as? Double, 0.0)
        XCTAssertEqual(result["threshold"] as? Double,  0.7)
        XCTAssertEqual(result["source"] as? String, "apple-sca")
        XCTAssertNotNil(result["durationMs"] as? Int)
    }

    func test_sfwResult_categoriesAbsent() async throws {
        mock.stubbedResult = false
        let uri = try makeTempFile(name: "sfw_cats_\(#function).png")

        let result = try await analyzer.analyze(uri: uri, threshold: 0.7)

        XCTAssertNil(result["categories"])
    }

    // MARK: Result shape — NSFW stub

    func test_nsfwStub_isNSFWTrueAndConfidenceOne() async throws {
        mock.stubbedResult = true
        let uri = try makeTempFile(name: "nsfw_stub_\(#function).png")

        let result = try await analyzer.analyze(uri: uri, threshold: 0.7)

        XCTAssertEqual(result["isNSFW"] as? Bool,      true)
        XCTAssertEqual(result["confidence"] as? Double, 1.0)
    }

    // MARK: Threshold echo-back

    func test_customThreshold_echoedInResult() async throws {
        mock.stubbedResult = false
        let uri = try makeTempFile(name: "thresh_\(#function).png")

        let result = try await analyzer.analyze(uri: uri, threshold: 0.95)

        XCTAssertEqual(result["threshold"] as? Double, 0.95)
    }

    // MARK: URL forwarded to underlying

    func test_urlForwardedToUnderlying() async throws {
        mock.stubbedResult = false
        let uri = try makeTempFile(name: "url_\(#function).png")

        _ = try await analyzer.analyze(uri: uri, threshold: 0.7)

        XCTAssertNotNil(mock.capturedURL)
        XCTAssertTrue(mock.capturedURL?.isFileURL == true)
    }

    // MARK: Error propagation

    func test_underlyingImageAnalyzerError_propagatesUnchanged() async throws {
        mock.stubbedError = ImageAnalyzerError.inferenceFailed("SCA threw")
        let uri = try makeTempFile(name: "err1_\(#function).png")

        do {
            _ = try await analyzer.analyze(uri: uri, threshold: 0.7)
            XCTFail("Expected throw")
        } catch let err as ImageAnalyzerError {
            guard case .inferenceFailed = err else { return XCTFail("Wrong case: \(err)") }
        }
    }

    func test_unknownUnderlyingError_wrappedAsInferenceFailed() async throws {
        mock.stubbedError = NSError(domain: "test", code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: "unknown"])
        let uri = try makeTempFile(name: "err2_\(#function).png")

        do {
            _ = try await analyzer.analyze(uri: uri, threshold: 0.7)
            XCTFail("Expected throw")
        } catch let err as ImageAnalyzerError {
            guard case .inferenceFailed = err else { return XCTFail("Wrong case: \(err)") }
        }
    }
}
