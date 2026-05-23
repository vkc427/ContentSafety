# expo-content-safety — Milestone 2: iOS Image Detection

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stub `detectImage` with real `SCSensitivityAnalyzer` inference on iOS.

**Architecture:** A new `ImageAnalyzer.swift` wraps `SCSensitivityAnalyzer` behind an `ImageSensitivityAnalyzing` protocol (enabling mock injection in tests). `ContentSafetyModule.swift` uses `ImageAnalyzer` for `detectImage` and pre-initializes it in `warmup()`. XCTests in `ios/Tests/` inject a mock so they never need the SCA entitlement.

**Tech Stack:** Swift 5.9+, `SensitiveContentAnalysis.framework` (iOS 17+), XCTest via CocoaPods test spec.

**Spec:** `docs/superpowers/specs/2026-05-23-expo-content-safety-design.md` — "iOS implementation → ImageAnalyzer.swift"

---

## Conventions

- Package directory: `/Users/kvadlamudi/expo-content-safety/`
- All paths are relative to that root unless stated otherwise.
- Commit after every task.
- JS tests (`npm test`) must stay green throughout — run after any change to `src/`.

---

## File Map

| Action | Path | Role |
|--------|------|------|
| Create | `__fixtures__/sfw_sample.png` | 1×1 blue pixel PNG — benign fixture for tests |
| Create | `ios/ImageAnalyzer.swift` | `ImageSensitivityAnalyzing` protocol + `SCAImageAnalyzing` + `ImageAnalyzer` |
| Create | `ios/Tests/ImageAnalyzerTests.swift` | XCTest suite using mock protocol |
| Modify | `ios/ContentSafetyModule.swift` | Wire `detectImage` + `warmup` to `ImageAnalyzer`; keep other methods stubbed |
| Modify | `ios/ExpoContentSafety.podspec` | Add `SensitiveContentAnalysis` framework + test spec; scope source_files to root |
| Create | `example/package.json` | Enable `expo prebuild` for native build verification |

---

### Task 1: Create the SFW fixture image

**Files:**
- Create: `__fixtures__/sfw_sample.png`

- [ ] **Step 1: Generate a 1×1 blue PNG with Python**

```bash
mkdir -p __fixtures__
python3 - <<'EOF'
import struct, zlib

def make_png(r, g, b):
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b'\x00' + bytes([r, g, b])
    return (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw))
        + chunk(b'IEND', b'')
    )

with open('__fixtures__/sfw_sample.png', 'wb') as f:
    f.write(make_png(0, 128, 255))
print('ok')
EOF
```

Expected: `ok`

- [ ] **Step 2: Verify it is a valid PNG**

```bash
file __fixtures__/sfw_sample.png
```

Expected: `PNG image data, 1 x 1, 8-bit/color RGB, non-interlaced`

- [ ] **Step 3: Commit**

```bash
git add __fixtures__/sfw_sample.png
git commit -m "chore: add SFW fixture PNG for iOS tests"
```

---

### Task 2: Create `ios/ImageAnalyzer.swift`

**Files:**
- Create: `ios/ImageAnalyzer.swift`

- [ ] **Step 1: Write the file**

Create `ios/ImageAnalyzer.swift`:

```swift
import Foundation
import SensitiveContentAnalysis

// MARK: - Protocol for dependency injection / testability

protocol ImageSensitivityAnalyzing {
    func isSensitive(url: URL) async throws -> Bool
}

// MARK: - Production implementation backed by SCSensitivityAnalyzer

@available(iOS 17.0, *)
final class SCAImageAnalyzing: ImageSensitivityAnalyzing {
    private let analyzer = SCSensitivityAnalyzer()

    func isSensitive(url: URL) async throws -> Bool {
        do {
            let result = try await analyzer.analyzeImage(at: url)
            return result.isSensitive
        } catch {
            throw ImageAnalyzerError.inferenceFailed(error.localizedDescription)
        }
    }
}

// MARK: - Error types

enum ImageAnalyzerError: Error, LocalizedError {
    case invalidInput(String)
    case inferenceFailed(String)
    case iosVersionTooLow

    var errorDescription: String? {
        switch self {
        case .invalidInput(let msg):   return "INVALID_INPUT: \(msg)"
        case .inferenceFailed(let msg): return "INFERENCE_FAILED: \(msg)"
        case .iosVersionTooLow:        return "IOS_VERSION_TOO_LOW: iOS 17.0+ is required for image analysis"
        }
    }
}

// MARK: - ImageAnalyzer

@available(iOS 17.0, *)
final class ImageAnalyzer {
    private let underlying: ImageSensitivityAnalyzing

    init(underlying: ImageSensitivityAnalyzing = SCAImageAnalyzing()) {
        self.underlying = underlying
    }

    func analyze(uri: String, threshold: Double) async throws -> [String: Any] {
        let start = CFAbsoluteTimeGetCurrent()

        guard !uri.isEmpty, let url = URL(string: uri), url.isFileURL else {
            throw ImageAnalyzerError.invalidInput("uri must be a file:// URL, got: \(uri)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageAnalyzerError.invalidInput("File not found at: \(url.path)")
        }

        let sensitive: Bool
        do {
            sensitive = try await underlying.isSensitive(url: url)
        } catch let err as ImageAnalyzerError {
            throw err
        } catch {
            throw ImageAnalyzerError.inferenceFailed(error.localizedDescription)
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        return [
            "isNSFW": sensitive,
            "confidence": sensitive ? 1.0 : 0.0,
            "threshold": threshold,
            "source": "apple-sca",
            "durationMs": durationMs,
        ]
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/ImageAnalyzer.swift
git commit -m "feat(ios): add ImageAnalyzer backed by SCSensitivityAnalyzer"
```

---

### Task 3: Write XCTest for `ImageAnalyzer`

**Files:**
- Create: `ios/Tests/ImageAnalyzerTests.swift`

These tests use a mock `ImageSensitivityAnalyzing` so they never invoke the real SCA — no entitlement needed, no simulator needed for logic tests.

- [ ] **Step 1: Create the test directory and file**

```bash
mkdir -p ios/Tests
```

Create `ios/Tests/ImageAnalyzerTests.swift`:

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add ios/Tests/ImageAnalyzerTests.swift
git commit -m "test(ios): add XCTest suite for ImageAnalyzer"
```

---

### Task 4: Update `ios/ContentSafetyModule.swift`

Wire `detectImage` to `ImageAnalyzer`. Keep `detectVideo`, `detectText` stubbed. Update `warmup` to pre-init the analyzer.

**Files:**
- Modify: `ios/ContentSafetyModule.swift`

- [ ] **Step 1: Replace the file contents**

Open `ios/ContentSafetyModule.swift`. Replace entirely with:

```swift
import ExpoModulesCore

public class ContentSafetyModule: Module {
    @available(iOS 17.0, *)
    private lazy var imageAnalyzer = ImageAnalyzer()

    public func definition() -> ModuleDefinition {
        Name("ContentSafety")

        AsyncFunction("detectImage") { [weak self] (uri: String, options: [String: Any]) async throws -> [String: Any] in
            guard #available(iOS 17, *) else {
                throw ImageAnalyzerError.iosVersionTooLow
            }
            let threshold = options["threshold"] as? Double ?? 0.7
            guard let self else {
                throw ImageAnalyzerError.inferenceFailed("Module deallocated")
            }
            return try await self.imageAnalyzer.analyze(uri: uri, threshold: threshold)
        }

        AsyncFunction("detectVideo") { (_: String, options: [String: Any]) -> [String: Any] in
            let threshold = options["threshold"] as? Double ?? 0.7
            return [
                "isNSFW": false,
                "confidence": 0.0,
                "threshold": threshold,
                "source": "tflite-image",
                "durationMs": 0,
                "framesAnalyzed": 0,
            ]
        }

        AsyncFunction("detectText") { (_: String, options: [String: Any]) -> [String: Any] in
            let threshold = options["threshold"] as? Double ?? 0.7
            return [
                "isNSFW": false,
                "confidence": 0.0,
                "threshold": threshold,
                "source": "blocklist",
                "durationMs": 0,
            ]
        }

        AsyncFunction("warmup") { [weak self] () async -> Void in
            guard #available(iOS 17, *) else { return }
            _ = self?.imageAnalyzer  // triggers lazy init of ImageAnalyzer / SCSensitivityAnalyzer
        }
    }
}
```

- [ ] **Step 2: Confirm JS tests still pass**

```bash
npm test
```

Expected: 20 tests, 5 suites, all green. (JS tests mock the native module, so Swift changes don't break them.)

- [ ] **Step 3: Commit**

```bash
git add ios/ContentSafetyModule.swift
git commit -m "feat(ios): wire ContentSafetyModule.detectImage to ImageAnalyzer"
```

---

### Task 5: Update the podspec

Add `SensitiveContentAnalysis` as a linked framework, scope `source_files` to the ios root (so `Tests/` is not compiled into the module target), and add a `test_spec`.

**Files:**
- Modify: `ios/ExpoContentSafety.podspec`

- [ ] **Step 1: Read the current podspec**

```bash
cat ios/ExpoContentSafety.podspec
```

- [ ] **Step 2: Replace entirely**

Open `ios/ExpoContentSafety.podspec`. Replace entirely with:

```ruby
Pod::Spec.new do |s|
  s.name           = 'ExpoContentSafety'
  s.version        = '1.0.0'
  s.summary        = 'On-device NSFW detection for images, videos, and text'
  s.description    = 'Detects NSFW content entirely on-device. No content leaves the device.'
  s.author         = 'kvadlamudi'
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = { :ios => '17.0' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.frameworks = 'SensitiveContentAnalysis'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  # Root-level ios/ files only — Tests/ is picked up by test_spec below
  s.source_files = "*.{h,m,mm,swift,hpp,cpp}"

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add ios/ExpoContentSafety.podspec
git commit -m "chore(ios): add SensitiveContentAnalysis framework and XCTest test_spec"
```

---

### Task 6: Set up example app and verify the native build

The example app needs a `package.json` before `expo prebuild` can generate the Xcode workspace. Once the workspace exists, `xcodebuild test` compiles `ImageAnalyzer.swift` and runs the XCTest suite.

**Files:**
- Create: `example/package.json`

- [ ] **Step 1: Create example/package.json**

```bash
ls example/package.json 2>/dev/null || echo "missing"
```

If missing, create `example/package.json`:

```json
{
  "name": "expo-content-safety-example",
  "version": "0.1.0",
  "main": "node_modules/expo/AppEntry.js",
  "scripts": {
    "start": "expo start",
    "ios": "expo run:ios",
    "android": "expo run:android"
  },
  "dependencies": {
    "expo": "~56.0.3",
    "expo-content-safety": "file:..",
    "react": "19.0.0",
    "react-native": "0.82.1"
  },
  "devDependencies": {
    "@babel/core": "^7.26.0"
  }
}
```

- [ ] **Step 2: Install example dependencies**

```bash
cd example && npm install && cd ..
```

Expected: `node_modules/` populated, no errors.

- [ ] **Step 3: Run expo prebuild for iOS**

```bash
cd example && npx expo prebuild --clean --platform ios 2>&1 | tail -10 && cd ..
```

Expected output ends with something like:
```
✔ Config synced
```
And `example/ios/` now exists with a `.xcworkspace`.

- [ ] **Step 4: Find the exact workspace and scheme names**

```bash
ls example/ios/*.xcworkspace && ls example/ios/*.xcodeproj
```

Expected: one `.xcworkspace` (e.g. `ExpoContentSafetyExample.xcworkspace`) and one `.xcodeproj`.

Note the exact workspace name — use it in the next step.

- [ ] **Step 5: Run the XCTest suite**

```bash
cd example/ios
xcodebuild test \
  -workspace ExpoContentSafetyExample.xcworkspace \
  -scheme ExpoContentSafetyExample \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing ExpoContentSafety/Tests \
  2>&1 | grep -E "Test Case|error:|BUILD SUCCEEDED|BUILD FAILED"
cd ../..
```

If `iPhone 16` isn't available, find an available simulator first:

```bash
xcrun simctl list devices available | grep "iPhone"
```

Then re-run the xcodebuild command with the correct name.

Expected: lines like:
```
Test Case '-[ExpoContentSafety.ImageAnalyzerTests test_sfwResult_allFieldsPresent]' passed
Test Case '-[ExpoContentSafety.ImageAnalyzerTests test_emptyURI_throwsInvalidInput]' passed
...
BUILD SUCCEEDED
```

No `error:` or `BUILD FAILED` lines.

- [ ] **Step 6: Commit example package.json**

```bash
git add example/package.json
git commit -m "chore(example): add package.json to enable expo prebuild"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run JS tests**

```bash
npm test
```

Expected: 20 tests, 5 suites, all green.

- [ ] **Step 2: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Verify git log**

```bash
git log --oneline -10
```

Expected: commits for Tasks 1–6 visible in order.

- [ ] **Step 4: Tag the milestone**

```bash
git tag -a v0.2.0-ios-image -m "Milestone 2: iOS image detection via SCSensitivityAnalyzer"
```

---

## What's next (Plan 3)

- **Plan 3:** Android image detection — bundle `nsfw_image.tflite`, implement `ImageAnalyzer.kt` with `MobileNetV2` inference (GantMan/NSFW, MIT-licensed), wire into `ContentSafetyModule.kt`.
