# Video Detection + v1.0.0 Production Release Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement real video detection on iOS and Android, fix the Android warmup gap, and bring the package to npm-publishable v1.0.0 shape (package.json, LICENSE, CHANGELOG, README).

**Architecture:** iOS uses `SCSensitivityAnalyzer.analyzeVideo(at:)` — Apple handles frame sampling internally; sampleRate/maxFrames/stopOnFirstHit are accepted and stored in the result for API shape consistency but are informational on iOS. Android uses `MediaMetadataRetriever` behind an injectable `FrameExtractor` interface, feeding frames directly into the existing `ImageAnalyzer.analyzeBitmap` method.

**Tech Stack:** Swift/SensitiveContentAnalysis (iOS), Kotlin/MediaMetadataRetriever/TFLite (Android), XCTest, JUnit 4 + Mockito-inline, expo-module-scripts.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `ios/VideoAnalyzer.swift` | Create | `VideoSensitivityAnalyzing` protocol + `SCAVideoAnalyzing` prod impl + `VideoAnalyzer` class |
| `ios/Tests/VideoAnalyzerTests.swift` | Create | XCTest for VideoAnalyzer |
| `ios/ContentSafetyModule.swift` | Modify | Replace stub detectVideo + update warmup |
| `android/src/main/java/.../ImageAnalyzer.kt` | Modify | Add `analyzeBitmap(bitmap, threshold)` method |
| `android/src/test/java/.../ImageAnalyzerTest.kt` | Modify | Test `analyzeBitmap` |
| `android/src/main/java/.../VideoAnalyzer.kt` | Create | `FrameExtractor` interface + `RetrieverFrameExtractor` + `VideoAnalyzer` |
| `android/src/test/java/.../VideoAnalyzerTest.kt` | Create | JUnit tests for VideoAnalyzer |
| `android/src/main/java/.../ContentSafetyModule.kt` | Modify | Replace stub detectVideo + fix warmup |
| `package.json` | Modify | Version 1.0.0, files field, repository/homepage/bugs URLs |
| `LICENSE` | Modify | Update copyright holder from Expo to kvadlamudi |
| `CHANGELOG.md` | Create | v1.0.0 release notes |
| `README.md` | Modify | Video detection section + status table update |

---

### Task 1: iOS VideoAnalyzer — protocol, SCA impl, and analyzer class

**Files:**
- Create: `ios/VideoAnalyzer.swift`

- [ ] **Step 1: Write the failing test (stub)**

Create `ios/Tests/VideoAnalyzerTests.swift` with a placeholder that will fail to compile until the real file exists:

```swift
import XCTest

// This file is intentionally empty — it will grow in Task 2.
// The VideoAnalyzer type must exist for this to compile.
final class VideoAnalyzerTests: XCTestCase {
    func testPlaceholder() {
        // will be filled in Task 2
    }
}
```

Run (expect compile error — VideoAnalyzer not yet defined):
```
xcodebuild test -scheme ExpoContentSafety-Tests 2>&1 | tail -20
```

- [ ] **Step 2: Create `ios/VideoAnalyzer.swift`**

```swift
import Foundation
import SensitiveContentAnalysis

// MARK: - Protocol for dependency injection / testability

protocol VideoSensitivityAnalyzing {
    func isSensitive(url: URL) async throws -> Bool
}

// MARK: - Production implementation backed by SCSensitivityAnalyzer

@available(iOS 17.0, *)
final class SCAVideoAnalyzing: VideoSensitivityAnalyzing {
    private let analyzer = SCSensitivityAnalyzer()

    func isSensitive(url: URL) async throws -> Bool {
        do {
            let result = try await analyzer.analyzeVideo(at: url)
            return result.isSensitive
        } catch {
            throw VideoAnalyzerError.inferenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Error types

enum VideoAnalyzerError: Error, LocalizedError {
    case invalidInput(String)
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):    return "INVALID_INPUT: \(msg)"
        case .inferenceFailed(let msg): return "INFERENCE_FAILED: \(msg)"
        }
    }
}

// MARK: - VideoAnalyzer

@available(iOS 17.0, *)
final class VideoAnalyzer {
    private let underlying: VideoSensitivityAnalyzing

    init(underlying: VideoSensitivityAnalyzing = SCAVideoAnalyzing()) {
        self.underlying = underlying
    }

    func analyze(
        uri: String,
        threshold: Double,
        sampleRate: Double,
        maxFrames: Int,
        stopOnFirstHit: Bool
    ) async throws -> [String: Any] {
        let start = ProcessInfo.processInfo.systemUptime

        guard !uri.isEmpty, let url = URL(string: uri), url.isFileURL else {
            throw VideoAnalyzerError.invalidInput("uri must be a file:// URL, got: \(uri)")
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw VideoAnalyzerError.invalidInput("File not found at: \(url.path(percentEncoded: false))")
        }

        let sensitive: Bool
        do {
            sensitive = try await underlying.isSensitive(url: url)
        } catch let err as VideoAnalyzerError {
            throw err
        } catch {
            throw VideoAnalyzerError.inferenceFailed(error.localizedDescription)
        }

        let durationMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)

        return [
            "isNSFW":          sensitive,
            "confidence":      sensitive ? 1.0 : 0.0,
            "threshold":       threshold,
            "source":          "apple-sca",
            "durationMs":      durationMs,
            "framesAnalyzed":  0,
        ]
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add ios/VideoAnalyzer.swift ios/Tests/VideoAnalyzerTests.swift
git commit -m "feat(ios): add VideoAnalyzer backed by SCSensitivityAnalyzer.analyzeVideo"
```

---

### Task 2: iOS VideoAnalyzerTests — full test coverage

**Files:**
- Modify: `ios/Tests/VideoAnalyzerTests.swift`

Context: `VideoAnalyzer` takes a `VideoSensitivityAnalyzing` protocol. Tests inject `MockVideoAnalyzing`. File existence is checked before calling the protocol, so tests use `FileManager.default.temporaryDirectory` + `createFile` for a valid URL.

- [ ] **Step 1: Replace placeholder with full test file**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add ios/Tests/VideoAnalyzerTests.swift
git commit -m "test(ios): add VideoAnalyzerTests"
```

---

### Task 3: Wire iOS detectVideo + update warmup

**Files:**
- Modify: `ios/ContentSafetyModule.swift`

Current state: `detectVideo` returns a hard-coded stub dict. `warmup` pre-warms `textAnalyzer` and `imageAnalyzer`. Need to add `videoAnalyzer` lazy var, replace stub, and add `videoAnalyzer` to warmup.

- [ ] **Step 1: Update `ContentSafetyModule.swift`**

Replace the entire file:

```swift
import ExpoModulesCore

public class ContentSafetyModule: Module {
    @available(iOS 17.0, *)
    private lazy var imageAnalyzer = ImageAnalyzer()

    @available(iOS 17.0, *)
    private lazy var videoAnalyzer = VideoAnalyzer()

    private lazy var textAnalyzer = TextAnalyzer()

    public func definition() -> ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            guard let self else {
                throw ImageAnalyzerError.inferenceFailed("Module deallocated")
            }
            let threshold = options["threshold"] as? Double ?? 0.7
            return try await self.imageAnalyzer.analyze(uri: uri, threshold: threshold)
        }

        AsyncFunction("detectVideo") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            guard let self else {
                throw VideoAnalyzerError.inferenceFailed("Module deallocated")
            }
            let threshold     = options["threshold"]     as? Double ?? 0.7
            let sampleRate    = options["sampleRate"]    as? Double ?? 1.0
            let maxFrames     = options["maxFrames"]     as? Int    ?? 30
            let stopOnFirstHit = options["stopOnFirstHit"] as? Bool ?? true
            return try await self.videoAnalyzer.analyze(
                uri:           uri,
                threshold:     threshold,
                sampleRate:    sampleRate,
                maxFrames:     maxFrames,
                stopOnFirstHit: stopOnFirstHit
            )
        }

        AsyncFunction("detectText") { [weak self] (input: String, options: [String: Any]) async throws -> [String: Any] in
            let threshold   = options["threshold"]   as? Double  ?? 0.7
            let extraTerms  = options["blocklist"]   as? [String] ?? []
            let useBlocklist = options["useBlocklist"] as? Bool  ?? true
            let useModel    = options["useModel"]    as? Bool    ?? true
            guard let self else {
                throw TextAnalyzerError.inferenceFailed("Module deallocated")
            }
            return try self.textAnalyzer.analyze(
                input:        input,
                threshold:    threshold,
                useBlocklist: useBlocklist,
                useModel:     useModel,
                extraTerms:   extraTerms
            )
        }

        AsyncFunction("warmup") { [weak self] () async -> Void in
            guard let self else { return }
            _ = self.textAnalyzer
            guard #available(iOS 17, *) else { return }
            _ = self.imageAnalyzer
            _ = self.videoAnalyzer
        }
    }
}
```

- [ ] **Step 2: Run JS tests to confirm nothing broken**

```bash
npm test 2>&1 | tail -15
```
Expected: all 33 tests pass.

- [ ] **Step 3: Commit**

```bash
git add ios/ContentSafetyModule.swift
git commit -m "feat(ios): wire detectVideo to VideoAnalyzer, add to warmup"
```

---

### Task 4: Android — add `analyzeBitmap` to ImageAnalyzer + test

**Files:**
- Modify: `android/src/main/java/expo/modules/contentsafety/ImageAnalyzer.kt`
- Modify: `android/src/test/java/expo/modules/contentsafety/ImageAnalyzerTest.kt`

`VideoAnalyzer` will call `imageAnalyzer.analyzeBitmap(bitmap, threshold)` directly (bypassing URI validation and bitmap decoding). The new method runs `runAnalysis` without recycling the bitmap — the caller owns lifecycle.

- [ ] **Step 1: Add `analyzeBitmap` to `ImageAnalyzer.kt`**

After the existing `analyze(uri, threshold)` method (around line 128), add:

```kotlin
fun analyzeBitmap(bitmap: Bitmap, threshold: Double): Map<String, Any> {
    val b = loadModel()
    return try {
        runAnalysis(bitmap, threshold, b)
    } catch (e: Exception) {
        throw RuntimeException("INFERENCE_FAILED: ${e.message}", e)
    }
    // NOTE: does NOT recycle bitmap — caller owns lifecycle
}
```

- [ ] **Step 2: Add tests for `analyzeBitmap` in `ImageAnalyzerTest.kt`**

At the end of the `ImageAnalyzerTest` class, add:

```kotlin
// -------------------------------------------------------------------------
// 9. analyzeBitmap delegates to runAnalysis correctly
// -------------------------------------------------------------------------
@Test
fun `analyzeBitmap returns correct result shape`() {
    `when`(mockBackend.runInference(any())).thenReturn(
        floatArrayOf(0.8f, 0.05f, 0.9f, 0.02f, 0.03f)
    )
    val analyzer = makeAnalyzer()
    // Pre-load the backend (analyzeBitmap calls loadModel internally)
    val result = analyzer.analyzeBitmap(mockBitmap, 0.7)

    assertEquals(false, result["isNSFW"])
    assertEquals(0.05, result["confidence"] as Double, 1e-6)
    assertEquals("tflite-image", result["source"])
}

// -------------------------------------------------------------------------
// 10. analyzeBitmap inference failure → INFERENCE_FAILED
// -------------------------------------------------------------------------
@Test
fun `analyzeBitmap inference failure throws INFERENCE_FAILED`() {
    `when`(mockBackend.runInference(any())).thenThrow(RuntimeException("crash"))
    val analyzer = makeAnalyzer()
    val ex = assertThrows(RuntimeException::class.java) {
        analyzer.analyzeBitmap(mockBitmap, 0.7)
    }
    assertTrue(ex.message!!.startsWith("INFERENCE_FAILED:"))
}
```

- [ ] **Step 3: Run Android unit tests**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | tail -20
```
Expected: all tests pass (was 8, now 10 for ImageAnalyzerTest).

- [ ] **Step 4: Commit**

```bash
git add android/src/main/java/expo/modules/contentsafety/ImageAnalyzer.kt \
        android/src/test/java/expo/modules/contentsafety/ImageAnalyzerTest.kt
git commit -m "feat(android): add ImageAnalyzer.analyzeBitmap for VideoAnalyzer reuse"
```

---

### Task 5: Android VideoAnalyzer.kt + tests

**Files:**
- Create: `android/src/main/java/expo/modules/contentsafety/VideoAnalyzer.kt`
- Create: `android/src/test/java/expo/modules/contentsafety/VideoAnalyzerTest.kt`

- [ ] **Step 1: Write the failing test first**

Create `android/src/test/java/expo/modules/contentsafety/VideoAnalyzerTest.kt`:

```kotlin
package expo.modules.contentsafety

import android.graphics.Bitmap
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*

class VideoAnalyzerTest {

    private lateinit var mockImageAnalyzer: ImageAnalyzer
    private lateinit var mockExtractor: FrameExtractor
    private lateinit var mockBitmap: Bitmap

    @Before
    fun setUp() {
        mockImageAnalyzer = mock(ImageAnalyzer::class.java)
        mockExtractor = mock(FrameExtractor::class.java)
        mockBitmap = mock(Bitmap::class.java)

        `when`(mockBitmap.width).thenReturn(224)
        `when`(mockBitmap.height).thenReturn(224)

        // Default: 5-second video, one frame at t=0
        `when`(mockExtractor.durationMs()).thenReturn(5_000L)
        `when`(mockExtractor.frameAt(anyLong())).thenReturn(mockBitmap)

        // Default: SFW result from image analyzer
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to false, "confidence" to 0.1, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )
    }

    private fun makeAnalyzer() = VideoAnalyzer(
        imageAnalyzer = mockImageAnalyzer,
        extractorFactory = { mockExtractor }
    )

    private val fakeUri = "file:///tmp/fake_video.mp4"

    // -------------------------------------------------------------------------
    // 1. Empty URI → INVALID_INPUT
    // -------------------------------------------------------------------------
    @Test
    fun `empty URI throws INVALID_INPUT`() {
        val ex = assertThrows(IllegalArgumentException::class.java) {
            makeAnalyzer().analyze("", 0.7, 1.0, 30, true)
        }
        assertTrue(ex.message!!.startsWith("INVALID_INPUT:"))
    }

    // -------------------------------------------------------------------------
    // 2. Non-file URI → INVALID_INPUT
    // -------------------------------------------------------------------------
    @Test
    fun `non-file URI throws INVALID_INPUT`() {
        val ex = assertThrows(IllegalArgumentException::class.java) {
            makeAnalyzer().analyze("https://example.com/v.mp4", 0.7, 1.0, 30, true)
        }
        assertTrue(ex.message!!.startsWith("INVALID_INPUT:"))
    }

    // -------------------------------------------------------------------------
    // 3. SFW frames → isNSFW false, framesAnalyzed set
    // -------------------------------------------------------------------------
    @Test
    fun `SFW frames return isNSFW false with correct framesAnalyzed`() {
        // sampleRate=1, durationMs=5000 → 5 frame times at t=0,1000,2000,3000,4000 ms
        `when`(mockExtractor.durationMs()).thenReturn(5_000L)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(false, result["isNSFW"])
        assertEquals(5, result["framesAnalyzed"])
        assertEquals("tflite-image", result["source"])
    }

    // -------------------------------------------------------------------------
    // 4. NSFW frame → isNSFW true
    // -------------------------------------------------------------------------
    @Test
    fun `NSFW frame sets isNSFW true`() {
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to true, "confidence" to 0.9, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(true, result["isNSFW"])
        assertEquals(0.9, result["confidence"] as Double, 1e-6)
    }

    // -------------------------------------------------------------------------
    // 5. stopOnFirstHit stops after first NSFW frame
    // -------------------------------------------------------------------------
    @Test
    fun `stopOnFirstHit stops analysis after first NSFW frame`() {
        // durationMs=10000, sampleRate=1 → 10 candidate frames
        `when`(mockExtractor.durationMs()).thenReturn(10_000L)
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenReturn(
            mapOf("isNSFW" to true, "confidence" to 0.9, "threshold" to 0.7,
                  "source" to "tflite-image", "durationMs" to 5)
        )

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, stopOnFirstHit = true)

        assertEquals(true, result["isNSFW"])
        assertEquals(1, result["framesAnalyzed"])
    }

    // -------------------------------------------------------------------------
    // 6. maxFrames caps the number of frames analyzed
    // -------------------------------------------------------------------------
    @Test
    fun `maxFrames caps frame count`() {
        // durationMs=60000, sampleRate=1 → 60 candidate frames; cap at 5
        `when`(mockExtractor.durationMs()).thenReturn(60_000L)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, maxFrames = 5, stopOnFirstHit = false)

        assertEquals(5, result["framesAnalyzed"])
    }

    // -------------------------------------------------------------------------
    // 7. framesAnalyzed reflects actual non-null frames
    // -------------------------------------------------------------------------
    @Test
    fun `null frame from extractor is skipped`() {
        `when`(mockExtractor.durationMs()).thenReturn(3_000L)
        // First call returns null, second and third return bitmap
        `when`(mockExtractor.frameAt(anyLong()))
            .thenReturn(null)
            .thenReturn(mockBitmap)
            .thenReturn(mockBitmap)

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)

        assertEquals(2, result["framesAnalyzed"])
    }

    // -------------------------------------------------------------------------
    // 8. threshold is echoed in result
    // -------------------------------------------------------------------------
    @Test
    fun `threshold is echoed in result`() {
        val result = makeAnalyzer().analyze(fakeUri, 0.85, 1.0, 30, false)
        assertEquals(0.85, result["threshold"] as Double, 1e-9)
    }

    // -------------------------------------------------------------------------
    // 9. confidence is max across frames
    // -------------------------------------------------------------------------
    @Test
    fun `confidence is max confidence across all frames`() {
        `when`(mockExtractor.durationMs()).thenReturn(2_000L)
        val results = listOf(
            mapOf("isNSFW" to false, "confidence" to 0.3, "threshold" to 0.7, "source" to "tflite-image", "durationMs" to 5),
            mapOf("isNSFW" to false, "confidence" to 0.6, "threshold" to 0.7, "source" to "tflite-image", "durationMs" to 5),
        )
        var callIndex = 0
        `when`(mockImageAnalyzer.analyzeBitmap(any(), anyDouble())).thenAnswer {
            results[callIndex++]
        }

        val result = makeAnalyzer().analyze(fakeUri, 0.7, 1.0, 30, false)
        assertEquals(0.6, result["confidence"] as Double, 1e-6)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (VideoAnalyzer, FrameExtractor don't exist yet)**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | grep -E "error:|FAILED|BUILD" | head -20
```
Expected: compile error about missing types.

- [ ] **Step 3: Create `VideoAnalyzer.kt`**

```kotlin
package expo.modules.contentsafety

import android.graphics.Bitmap
import android.os.SystemClock
import java.io.Closeable

interface FrameExtractor : Closeable {
    fun durationMs(): Long
    fun frameAt(timeUs: Long): Bitmap?
}

class RetrieverFrameExtractor(path: String) : FrameExtractor {
    private val retriever = android.media.MediaMetadataRetriever()

    init {
        try {
            retriever.setDataSource(path)
        } catch (e: Exception) {
            retriever.release()
            throw IllegalArgumentException("INVALID_INPUT: cannot open video: ${e.message}")
        }
    }

    override fun durationMs(): Long =
        retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLong() ?: 0L

    override fun frameAt(timeUs: Long): Bitmap? =
        retriever.getFrameAtTime(timeUs, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)

    override fun close() = retriever.release()
}

class VideoAnalyzer(
    private val imageAnalyzer: ImageAnalyzer,
    private val extractorFactory: (path: String) -> FrameExtractor = { RetrieverFrameExtractor(it) }
) {
    fun analyze(
        uri: String,
        threshold: Double,
        sampleRate: Double,
        maxFrames: Int,
        stopOnFirstHit: Boolean
    ): Map<String, Any> {
        if (uri.isEmpty()) throw IllegalArgumentException("INVALID_INPUT: uri must be a non-empty string")

        val parsed = try { java.net.URI(uri) } catch (e: Exception) {
            throw IllegalArgumentException("INVALID_INPUT: malformed uri: $uri")
        }
        if (parsed.scheme != "file") throw IllegalArgumentException("INVALID_INPUT: uri must be a file:// URL, got: $uri")
        val path = parsed.path ?: throw IllegalArgumentException("INVALID_INPUT: uri has no path: $uri")

        val extractor = try {
            extractorFactory(path)
        } catch (e: IllegalArgumentException) {
            throw e
        } catch (e: Exception) {
            throw RuntimeException("INFERENCE_FAILED: ${e.message}", e)
        }

        return extractor.use { ext ->
            val durationMs = ext.durationMs()
            val frameIntervalMs = (1000.0 / sampleRate).toLong().coerceAtLeast(1L)

            val frameTimes = mutableListOf<Long>()
            var t = 0L
            while (t < durationMs * 1000L && frameTimes.size < maxFrames) {
                frameTimes.add(t)
                t += frameIntervalMs * 1000L
            }

            var maxConfidence = 0.0
            var isNSFW = false
            var framesAnalyzed = 0
            val start = SystemClock.elapsedRealtime()

            for (timeUs in frameTimes) {
                val bitmap = ext.frameAt(timeUs) ?: continue
                try {
                    val result = imageAnalyzer.analyzeBitmap(bitmap, threshold)
                    framesAnalyzed++
                    val conf = (result["confidence"] as? Double) ?: 0.0
                    if (conf > maxConfidence) maxConfidence = conf
                    if (conf >= threshold) {
                        isNSFW = true
                        if (stopOnFirstHit) break
                    }
                } finally {
                    bitmap.recycle()
                }
            }

            val durationAnalyzedMs = (SystemClock.elapsedRealtime() - start).toInt()

            mapOf(
                "isNSFW"         to isNSFW,
                "confidence"     to maxConfidence,
                "threshold"      to threshold,
                "source"         to "tflite-image",
                "durationMs"     to durationAnalyzedMs,
                "framesAnalyzed" to framesAnalyzed,
            )
        }
    }
}
```

- [ ] **Step 4: Run Android unit tests — all should pass**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/java/expo/modules/contentsafety/VideoAnalyzer.kt \
        android/src/test/java/expo/modules/contentsafety/VideoAnalyzerTest.kt
git commit -m "feat(android): add VideoAnalyzer with MediaMetadataRetriever + injectable FrameExtractor"
```

---

### Task 6: Wire Android detectVideo + fix warmup

**Files:**
- Modify: `android/src/main/java/expo/modules/contentsafety/ContentSafetyModule.kt`

Current: `detectVideo` returns a stub. `warmup` only loads imageAnalyzer. Need to add `videoAnalyzer` DCL helper, wire `detectVideo`, fix warmup to also initialize `textAnalyzer`.

- [ ] **Step 1: Replace `ContentSafetyModule.kt`**

```kotlin
package expo.modules.contentsafety

import android.content.Context
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
    private val context: Context
        get() = appContext.reactContext ?: throw IllegalStateException("React context unavailable")

    @Volatile private var imageAnalyzer: ImageAnalyzer? = null
    @Volatile private var videoAnalyzer: VideoAnalyzer? = null
    @Volatile private var textAnalyzer: TextAnalyzer? = null

    private fun getOrCreateAnalyzer(): ImageAnalyzer =
        imageAnalyzer ?: synchronized(this) {
            imageAnalyzer ?: ImageAnalyzer(context).also { imageAnalyzer = it }
        }

    private fun getOrCreateVideoAnalyzer(): VideoAnalyzer =
        videoAnalyzer ?: synchronized(this) {
            videoAnalyzer ?: VideoAnalyzer(getOrCreateAnalyzer()).also { videoAnalyzer = it }
        }

    private fun getOrCreateTextAnalyzer(): TextAnalyzer =
        textAnalyzer ?: synchronized(this) {
            textAnalyzer ?: TextAnalyzer(context).also { textAnalyzer = it }
        }

    override fun definition() = ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { uri: String, options: Map<String, Any?> ->
            val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
            getOrCreateAnalyzer().analyze(uri, threshold)
        }

        AsyncFunction("detectVideo") { uri: String, options: Map<String, Any?> ->
            val threshold      = (options["threshold"]      as? Number)?.toDouble()  ?: 0.7
            val sampleRate     = (options["sampleRate"]     as? Number)?.toDouble()  ?: 1.0
            val maxFrames      = (options["maxFrames"]      as? Number)?.toInt()     ?: 30
            val stopOnFirstHit = (options["stopOnFirstHit"] as? Boolean)             ?: true
            getOrCreateVideoAnalyzer().analyze(uri, threshold, sampleRate, maxFrames, stopOnFirstHit)
        }

        AsyncFunction("detectText") { input: String, options: Map<String, Any?> ->
            val threshold    = (options["threshold"]    as? Number)?.toDouble()  ?: 0.7
            @Suppress("UNCHECKED_CAST")
            val extraTerms   = (options["blocklist"]    as? List<String>)        ?: emptyList()
            val useBlocklist = (options["useBlocklist"] as? Boolean)             ?: true
            val useModel     = (options["useModel"]     as? Boolean)             ?: true
            getOrCreateTextAnalyzer().analyze(input, threshold, useBlocklist, useModel, extraTerms)
        }

        AsyncFunction("warmup") {
            getOrCreateAnalyzer().loadModel()
            getOrCreateTextAnalyzer()
        }

        OnDestroy {
            imageAnalyzer?.close()
            imageAnalyzer = null
            videoAnalyzer = null
            textAnalyzer  = null
        }
    }
}
```

- [ ] **Step 2: Run JS tests**

```bash
npm test 2>&1 | tail -10
```
Expected: all 33 tests pass.

- [ ] **Step 3: Run Android unit tests**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | tail -15
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add android/src/main/java/expo/modules/contentsafety/ContentSafetyModule.kt
git commit -m "feat(android): wire detectVideo to VideoAnalyzer, fix warmup to include textAnalyzer"
```

---

### Task 7: Production readiness — package.json, LICENSE, CHANGELOG

**Files:**
- Modify: `package.json`
- Modify: `LICENSE`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Update `package.json`**

Replace with:

```json
{
  "name": "expo-content-safety",
  "version": "1.0.0",
  "description": "On-device NSFW detection for images, videos, and text",
  "main": "build/index.js",
  "types": "build/index.d.ts",
  "files": [
    "build/",
    "android/",
    "ios/",
    "expo-module.config.json",
    "ExpoContentSafety.podspec"
  ],
  "scripts": {
    "build": "node internal/module_scripts/build.js",
    "clean": "node internal/module_scripts/clean.js",
    "lint": "eslint src/",
    "test": "node internal/module_scripts/test.js",
    "prepare": "node internal/module_scripts/prepare.js",
    "open:ios": "node internal/module_scripts/open-ios.js",
    "open:android": "node internal/module_scripts/open-android.js"
  },
  "keywords": [
    "react-native",
    "expo",
    "expo-content-safety",
    "nsfw",
    "content-moderation",
    "on-device",
    "ExpoContentSafety"
  ],
  "repository": {
    "type": "git",
    "url": "https://github.com/kvadlamudi/expo-content-safety.git"
  },
  "bugs": {
    "url": "https://github.com/kvadlamudi/expo-content-safety/issues"
  },
  "author": "kvadlamudi <iosvkctps@gmail.com>",
  "license": "MIT",
  "homepage": "https://github.com/kvadlamudi/expo-content-safety#readme",
  "devDependencies": {
    "@babel/core": "^7.26.0",
    "@types/jest": "^29.2.1",
    "@types/react": "~19.1.1",
    "babel-preset-expo": "~55.0.8",
    "eslint": "~9.39.4",
    "eslint-config-universe": "^15.0.3",
    "expo": "^56.0.3",
    "jest": "^29.7.0",
    "jest-expo": "~56.0.0",
    "prettier": "^3.0.0",
    "react-native": "0.82.1",
    "typescript": "^5.9.2"
  },
  "jest": {
    "preset": "jest-expo",
    "roots": [
      "<rootDir>/src"
    ],
    "testPathIgnorePatterns": [
      "/node_modules/",
      "/__mocks__/"
    ],
    "moduleNameMapper": {
      "^\\.\\./ContentSafetyModule$": "<rootDir>/src/__tests__/__mocks__/ContentSafetyModule.ts",
      "^\\./ContentSafetyModule$": "<rootDir>/src/__tests__/__mocks__/ContentSafetyModule.ts"
    }
  },
  "peerDependencies": {
    "expo": "*",
    "react": "*",
    "react-native": "*"
  }
}
```

- [ ] **Step 2: Update `LICENSE` copyright**

Replace the copyright line:
```
Copyright (c) 2026 kvadlamudi
```
(Full file):
```
The MIT License (MIT)

Copyright (c) 2026 kvadlamudi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-05-23

### Added

- **Image detection** — iOS via `SCSensitivityAnalyzer` (iOS 17+); Android via TFLite MobileNetV2 (GantMan, MIT)
- **Video detection** — iOS via `SCSensitivityAnalyzer.analyzeVideo`; Android via `MediaMetadataRetriever` + TFLite per-frame with `stopOnFirstHit`, `sampleRate`, and `maxFrames` controls
- **Text detection** — Blocklist (word-boundary anchored, leetspeak-normalised, whitespace-flexible) on both platforms; ML model slot is a no-op stub ready for a future text classifier
- **`warmup()`** — pre-loads image TFLite interpreter and text analyzer on both platforms
- **`ContentSafetyError`** — typed error class with `code` field (`INVALID_INPUT`, `INFERENCE_FAILED`, `MODEL_LOAD_FAILED`, `IOS_VERSION_TOO_LOW`, `UNSUPPORTED_PLATFORM`)
- New Architecture (TurboModules + Fabric) and legacy Bridge both supported via Expo Modules
```

- [ ] **Step 4: Run JS tests**

```bash
npm test 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add package.json LICENSE CHANGELOG.md
git commit -m "chore: bump to v1.0.0 — package.json files/keywords/urls, LICENSE, CHANGELOG"
```

---

### Task 8: README — video detection section + status table

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update status table**

Replace:
```markdown
| Video      | stub                     | stub                       |
```
With:
```markdown
| Video      | ✅ SCSensitivityAnalyzer | ✅ TFLite MobileNetV2      |
```

- [ ] **Step 2: Add video detection section**

After the "Text detection" section and before "Error handling", insert:

```markdown
## Video detection

`Video.detect` extracts frames from a local video file and checks them for NSFW content.

- **iOS** — delegates to `SCSensitivityAnalyzer.analyzeVideo(at:)`. Apple handles frame sampling internally; `sampleRate`, `maxFrames`, and `stopOnFirstHit` are accepted for API consistency but are informational on iOS.
- **Android** — extracts frames via `MediaMetadataRetriever` at `sampleRate` fps, capped at `maxFrames`, and runs each through the TFLite MobileNetV2 image classifier. `stopOnFirstHit: true` (the default) short-circuits as soon as one frame exceeds the threshold.

```ts
import { Video } from 'expo-content-safety';

const result = await Video.detect(videoUri, {
  threshold: 0.7,    // default
  sampleRate: 1,     // frames per second to sample (Android)
  maxFrames: 30,     // hard cap on frames analyzed (Android)
  stopOnFirstHit: true, // stop on first NSFW frame (Android)
});
// result.isNSFW
// result.confidence
// result.framesAnalyzed  — always 0 on iOS (SCA handles sampling internally)
// result.durationMs
```

### VideoDetectOptions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `threshold` | `number` | `0.7` | Score at or above which `isNSFW` is `true` |
| `sampleRate` | `number` | `1` | Frames per second to sample (Android only) |
| `maxFrames` | `number` | `30` | Hard cap on frames analyzed (Android only) |
| `stopOnFirstHit` | `boolean` | `true` | Stop analyzing after first NSFW frame (Android only) |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add video detection section and update status table to v1.0.0"
```

- [ ] **Step 4: Tag v1.0.0**

```bash
git tag v1.0.0
```

---

## Self-Review

**Spec coverage:**
- ✅ iOS video: `SCSensitivityAnalyzer.analyzeVideo(at:)` — matches spec's "frame extraction + reuse image analyzers" intent (iOS uses SCA natively)
- ✅ Android video: `MediaMetadataRetriever` + `ImageAnalyzer.analyzeBitmap` — matches spec exactly
- ✅ `stopOnFirstHit`, `sampleRate`, `maxFrames` options wired on Android
- ✅ `framesAnalyzed` in result
- ✅ `warmup()` pre-warms all analyzers on both platforms
- ✅ Production packaging: `files`, version `1.0.0`, CHANGELOG, LICENSE
- ✅ README reflects live status

**Placeholder scan:** No TBD/TODO in plan. All code blocks complete.

**Type consistency:** `FrameExtractor` interface defined before use in `VideoAnalyzer.kt`. `analyzeBitmap` added before `VideoAnalyzer.kt` references it. iOS `VideoAnalyzerError` defined in `VideoAnalyzer.swift` and referenced in `ContentSafetyModule.swift`.
