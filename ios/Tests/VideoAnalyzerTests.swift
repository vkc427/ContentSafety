import XCTest

// MARK: - Mock

final class MockVideoAnalyzing: VideoSensitivityAnalyzing {
    var stubbedSensitive: Bool = false
    var stubbedError: Error? = nil
    var callCount: Int = 0

    func isSensitive(url: URL) async throws -> Bool {
        callCount += 1
        if let err = stubbedError { throw err }
        return stubbedSensitive
    }
}

// MARK: - Tests

@available(iOS 17.0, *)
final class VideoAnalyzerTests: XCTestCase {
    private var mock: MockVideoAnalyzing!
    private var analyzer: VideoAnalyzer!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        mock = MockVideoAnalyzing()
        analyzer = VideoAnalyzer(underlying: mock)

        // VideoAnalyzer checks file existence before calling the protocol.
        // Create an empty temp file so the check passes.
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_video_\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // -------------------------------------------------------------------------
    // 1. Empty URI → INVALID_INPUT
    // -------------------------------------------------------------------------
    func testEmptyURIThrowsInvalidInput() async {
        do {
            _ = try await analyzer.analyze(uri: "", threshold: 0.7, sampleRate: 1, maxFrames: 30, stopOnFirstHit: true)
            XCTFail("Expected error")
        } catch let err as VideoAnalyzerError {
            if case .invalidInput = err { /* ok */ }
            else { XCTFail("Expected invalidInput, got \(err)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // 2. Non-file URI → INVALID_INPUT
    // -------------------------------------------------------------------------
    func testNonFileURIThrowsInvalidInput() async {
        do {
            _ = try await analyzer.analyze(uri: "https://example.com/video.mp4", threshold: 0.7, sampleRate: 1, maxFrames: 30, stopOnFirstHit: true)
            XCTFail("Expected error")
        } catch let err as VideoAnalyzerError {
            if case .invalidInput = err { /* ok */ }
            else { XCTFail("Expected invalidInput, got \(err)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // 3. File not found → INVALID_INPUT
    // -------------------------------------------------------------------------
    func testMissingFileThrowsInvalidInput() async {
        do {
            _ = try await analyzer.analyze(uri: "file:///no/such/video.mp4", threshold: 0.7, sampleRate: 1, maxFrames: 30, stopOnFirstHit: true)
            XCTFail("Expected error")
        } catch let err as VideoAnalyzerError {
            if case .invalidInput = err { /* ok */ }
            else { XCTFail("Expected invalidInput, got \(err)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // 4. SFW result shape
    // -------------------------------------------------------------------------
    func testSFWResultShape() async throws {
        mock.stubbedSensitive = false

        let result = try await analyzer.analyze(
            uri: tempURL.absoluteString,
            threshold: 0.7,
            sampleRate: 1,
            maxFrames: 30,
            stopOnFirstHit: true
        )

        XCTAssertEqual(result["isNSFW"] as? Bool, false)
        XCTAssertEqual(result["confidence"] as? Double, 0.0, accuracy: 1e-9)
        XCTAssertEqual(result["source"] as? String, "apple-sca")
        XCTAssertEqual(result["threshold"] as? Double, 0.7, accuracy: 1e-9)
        XCTAssertEqual(result["framesAnalyzed"] as? Int, 0)
        XCTAssertNotNil(result["durationMs"])
    }

    // -------------------------------------------------------------------------
    // 5. NSFW result
    // -------------------------------------------------------------------------
    func testNSFWResult() async throws {
        mock.stubbedSensitive = true

        let result = try await analyzer.analyze(
            uri: tempURL.absoluteString,
            threshold: 0.7,
            sampleRate: 1,
            maxFrames: 30,
            stopOnFirstHit: true
        )

        XCTAssertEqual(result["isNSFW"] as? Bool, true)
        XCTAssertEqual(result["confidence"] as? Double, 1.0, accuracy: 1e-9)
    }

    // -------------------------------------------------------------------------
    // 6. Underlying error → INFERENCE_FAILED
    // -------------------------------------------------------------------------
    func testUnderlyingErrorBecomesInferenceFailed() async {
        mock.stubbedError = VideoAnalyzerError.inferenceFailed("SCA failed")

        do {
            _ = try await analyzer.analyze(uri: tempURL.absoluteString, threshold: 0.7, sampleRate: 1, maxFrames: 30, stopOnFirstHit: true)
            XCTFail("Expected error")
        } catch let err as VideoAnalyzerError {
            if case .inferenceFailed = err { /* ok */ }
            else { XCTFail("Expected inferenceFailed, got \(err)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // 7. Threshold is echoed in result
    // -------------------------------------------------------------------------
    func testThresholdEcho() async throws {
        mock.stubbedSensitive = false
        let result = try await analyzer.analyze(uri: tempURL.absoluteString, threshold: 0.9, sampleRate: 1, maxFrames: 30, stopOnFirstHit: true)
        XCTAssertEqual(result["threshold"] as? Double, 0.9, accuracy: 1e-9)
    }
}
