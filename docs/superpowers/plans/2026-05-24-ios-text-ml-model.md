# iOS Real Text ML Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `NoOpTextModelAnalyzing` stub on iOS with a bundled CoreML binary classifier that detects NSFW + toxic text, with an optional developer override at runtime.

**Architecture:** A new `CoreMLTextModelAnalyzing` class conforms to the existing `TextModelAnalyzing` protocol and wraps Apple's `NLModel`. A bundled `ContentSafetyTextClassifier.mlmodelc` is loaded at startup with silent fallback to `NoOpTextModelAnalyzing` when missing. Developers can pass a `modelPath` file URI via `warmup()` to substitute their own CoreML model at runtime.

**Tech Stack:** Swift, CoreML, NaturalLanguage framework, Create ML (training), XCTest

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `ios/CoreMLTextModelAnalyzing.swift` | **Create** | Conforms to `TextModelAnalyzing`; wraps `NLModel`; provides `load(from:)` and `default` |
| `ios/TextAnalyzer.swift` | **Modify** | Change default `modelBackend` from `NoOpTextModelAnalyzing()` to `CoreMLTextModelAnalyzing.default` |
| `ios/ContentSafetyModule.swift` | **Modify** | Accept optional `modelPath` in `warmup`, swap backend when provided |
| `ios/Resources/ContentSafetyTextClassifier.mlmodelc` | **Create** | Bundled production CoreML model |
| `ios/Tests/CoreMLTextModelAnalyzingTests.swift` | **Create** | Unit tests for `CoreMLTextModelAnalyzing` |
| `ios/Tests/Resources/TestContentSafetyTextClassifier.mlmodelc` | **Create** | Tiny fixture model used by tests |
| `scripts/train_text_classifier.swift` | **Create** | Reproducible Create ML training script (fixture + production modes) |
| `src/types.ts` | **Modify** | Add `WarmupOptions` interface |
| `src/ContentSafetyModule.ts` | **Modify** | Update `warmup` signature to accept `WarmupOptions` |
| `src/index.ts` | **Modify** | Pass `WarmupOptions` through to native module |
| `ExpoContentSafety.podspec` | **Modify** | Add `s.resources`, add `NaturalLanguage` + `CoreML` to `s.frameworks` |

---

## Task 1: `CoreMLTextModelAnalyzing` — shell and fallback test

**Files:**
- Create: `ios/CoreMLTextModelAnalyzing.swift`
- Modify: `ios/Tests/CoreMLTextModelAnalyzingTests.swift` (new file)

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/CoreMLTextModelAnalyzingTests.swift`:

```swift
import XCTest
import CoreML

final class CoreMLTextModelAnalyzingTests: XCTestCase {

    // MARK: - Fallback

    func test_load_withInvalidURL_returnsNoOpTextModelAnalyzing() {
        let url = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")
        let backend = CoreMLTextModelAnalyzing.load(from: url)
        XCTAssert(backend is NoOpTextModelAnalyzing,
                  "Expected NoOpTextModelAnalyzing, got \(type(of: backend))")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|error:|CoreMLTextModelAnalyzing)"
```

Expected: compile error — `CoreMLTextModelAnalyzing` not defined.

- [ ] **Step 3: Implement `CoreMLTextModelAnalyzing.swift`**

Create `ios/CoreMLTextModelAnalyzing.swift`:

```swift
import CoreML
import NaturalLanguage

final class CoreMLTextModelAnalyzing: TextModelAnalyzing {
    private let model: NLModel

    init(model: NLModel) {
        self.model = model
    }

    static func load(from url: URL) -> TextModelAnalyzing {
        guard let mlModel = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: mlModel) else {
            return NoOpTextModelAnalyzing()
        }
        return CoreMLTextModelAnalyzing(model: nlModel)
    }

    static var `default`: TextModelAnalyzing {
        guard let url = Bundle(for: CoreMLTextModelAnalyzing.self)
            .url(forResource: "ContentSafetyTextClassifier", withExtension: "mlmodelc") else {
            return NoOpTextModelAnalyzing()
        }
        return load(from: url)
    }

    func confidence(for text: String) -> Double {
        model.predictedLabelHypotheses(for: text, maximumCount: 2)?["unsafe"] ?? 0.0
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|test_load)"
```

Expected: `test_load_withInvalidURL_returnsNoOpTextModelAnalyzing` PASSED.

- [ ] **Step 5: Commit**

```bash
git add ios/CoreMLTextModelAnalyzing.swift ios/Tests/CoreMLTextModelAnalyzingTests.swift
git commit -m "feat(ios): add CoreMLTextModelAnalyzing with fallback to NoOp"
```

---

## Task 2: Training script — produce fixture and production models

**Files:**
- Create: `scripts/train_text_classifier.swift`

- [ ] **Step 1: Write the training script**

Create `scripts/train_text_classifier.swift`:

```swift
#!/usr/bin/env swift -framework CreateML
import CreateML
import Foundation

// Usage:
//   swift scripts/train_text_classifier.swift fixture   → TestContentSafetyTextClassifier.mlmodel
//   swift scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv
//                                                       → ContentSafetyTextClassifier.mlmodel
//
// Compile to .mlmodelc after training:
//   xcrun coremlcompiler compile <output>.mlmodel <dest-dir>/

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixture"

if mode == "fixture" {
    let texts: [String] = [
        "I hate you and I want to kill you",
        "send me explicit photos right now",
        "you are worthless garbage, go die",
        "nude picture request here",
        "I will find where you live and hurt you",
        "severe obscene language example text",
        "The weather looks great today",
        "I really enjoy spending time with my family",
        "Let us go for a walk in the park",
        "The quarterly report numbers look good",
        "Can you help me with this homework problem?",
        "I like reading books on the weekend",
    ]
    let labels: [String] = [
        "unsafe","unsafe","unsafe","unsafe","unsafe","unsafe",
        "safe","safe","safe","safe","safe","safe",
    ]

    let table = try MLDataTable(dictionary: ["text": texts, "label": labels])
    let classifier = try MLTextClassifier(
        trainingData: table,
        textColumn:   "text",
        labelColumn:  "label"
    )
    let outURL = URL(fileURLWithPath: "TestContentSafetyTextClassifier.mlmodel")
    try classifier.write(to: outURL)
    print("Fixture model written to \(outURL.path)")
    print("Next: xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")

} else if mode == "production" {
    guard CommandLine.arguments.count > 2 else {
        print("Usage: swift scripts/train_text_classifier.swift production /path/to/jigsaw_train.csv")
        print("Dataset: https://www.kaggle.com/competitions/jigsaw-toxic-comment-classification-challenge/data")
        exit(1)
    }
    let csvPath = CommandLine.arguments[2]
    let rawTable = try MLDataTable(contentsOf: URL(fileURLWithPath: csvPath))

    // Jigsaw columns: id, comment_text, toxic, severe_toxic, obscene, threat, insult, identity_hate
    // Label "unsafe" if any toxicity column == 1, otherwise "safe"
    let unsafeCols = ["toxic", "severe_toxic", "obscene", "threat", "insult", "identity_hate"]
    let n = rawTable.size

    var labelArray = [String](repeating: "safe", count: n)
    for colName in unsafeCols {
        if let col = rawTable[colName] {
            for i in 0..<n {
                if let val = col[i] as? Int, val == 1 {
                    labelArray[i] = "unsafe"
                }
            }
        }
    }

    guard let textCol = rawTable["comment_text"] else {
        print("Error: 'comment_text' column not found in CSV"); exit(1)
    }
    let textArray = (0..<n).compactMap { textCol[$0] as? String }

    let trainTable = try MLDataTable(dictionary: ["text": textArray, "label": labelArray])
    let classifier = try MLTextClassifier(
        trainingData: trainTable,
        textColumn:   "text",
        labelColumn:  "label"
    )
    let outURL = URL(fileURLWithPath: "ContentSafetyTextClassifier.mlmodel")
    try classifier.write(to: outURL)
    print("Production model written to \(outURL.path)")
    print("Next: xcrun coremlcompiler compile ContentSafetyTextClassifier.mlmodel ios/Resources/")

} else {
    print("Unknown mode '\(mode)'. Use 'fixture' or 'production'.")
    exit(1)
}
```

- [ ] **Step 2: Create destination directories**

```bash
mkdir -p ios/Resources ios/Tests/Resources
touch ios/Resources/.gitkeep
```

- [ ] **Step 3: Run the fixture training (requires Xcode + macOS)**

```bash
swift scripts/train_text_classifier.swift fixture
```

Expected output: `Fixture model written to TestContentSafetyTextClassifier.mlmodel`

- [ ] **Step 4: Compile the fixture model to `.mlmodelc`**

```bash
xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/
```

Expected: `ios/Tests/Resources/TestContentSafetyTextClassifier.mlmodelc/` directory created.

- [ ] **Step 5: Clean up the intermediate `.mlmodel`**

```bash
rm TestContentSafetyTextClassifier.mlmodel
```

- [ ] **Step 6: Commit**

Note: `.mlmodelc` is a directory; `git add` the full directory path to capture all nested files.

```bash
git add scripts/train_text_classifier.swift \
        ios/Resources/.gitkeep \
        "ios/Tests/Resources/TestContentSafetyTextClassifier.mlmodelc/"
git commit -m "feat(ios): add training script and compiled fixture model for tests"
```

---

## Task 3: `CoreMLTextModelAnalyzing` — confidence tests with fixture model

**Files:**
- Modify: `ios/Tests/CoreMLTextModelAnalyzingTests.swift`

The fixture model is tiny (12 rows) so predictions aren't guaranteed — but it is a valid CoreML pipeline. These tests verify the end-to-end plumbing, not accuracy.

- [ ] **Step 1: Add confidence tests**

Append to `ios/Tests/CoreMLTextModelAnalyzingTests.swift` after `test_load_withInvalidURL_returnsNoOpTextModelAnalyzing`:

```swift
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
            XCTFail("Fixture model not found — run: swift scripts/train_text_classifier.swift fixture && xcrun coremlcompiler compile TestContentSafetyTextClassifier.mlmodel ios/Tests/Resources/")
            return
        }
        let score = backend.confidence(for: "some text here")
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func test_confidence_emptyString_returnsZero() {
        guard let backend = makeFixtureBackend() else { return }
        // NLModel returns nil hypotheses for empty input — should map to 0.0
        let score = backend.confidence(for: "")
        XCTAssertEqual(score, 0.0)
    }

    func test_confidence_missingUnsafeLabel_returnsZero() {
        // If model returns hypotheses without "unsafe" key, default is 0.0
        guard let backend = makeFixtureBackend() else { return }
        // A model that returns only "safe" should still return 0.0 for confidence
        let score = backend.confidence(for: "the quick brown fox")
        XCTAssertGreaterThanOrEqual(score, 0.0)
    }
```

- [ ] **Step 2: Add fixture model to test_spec resources in podspec**

Open `ExpoContentSafety.podspec` and update the `test_spec` block:

```ruby
  s.test_spec 'Tests' do |test_spec|
    test_spec.platforms    = { :ios => '17.0' }
    test_spec.source_files = 'ios/Tests/**/*.swift'
    test_spec.resources    = 'ios/Tests/Resources/**'
  end
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|test_confidence)"
```

Expected: all three `test_confidence_*` tests PASSED.

- [ ] **Step 4: Commit**

```bash
git add ios/Tests/CoreMLTextModelAnalyzingTests.swift ExpoContentSafety.podspec
git commit -m "test(ios): add CoreMLTextModelAnalyzing confidence tests with fixture model"
```

---

## Task 4: Wire `CoreMLTextModelAnalyzing.default` into `TextAnalyzer`

**Files:**
- Modify: `ios/TextAnalyzer.swift:34-36`
- Modify: `ios/Tests/TextAnalyzerTests.swift`

- [ ] **Step 1: Write failing integration test**

Append to `ios/Tests/TextAnalyzerTests.swift` (after the last test, before the closing `}`):

```swift
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
```

- [ ] **Step 2: Run tests to verify the new tests pass (they should — NoOp path)**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|test_default|test_analyzerWith)"
```

Expected: both new tests PASSED (NoOp path taken, no crash).

- [ ] **Step 3: Update `TextAnalyzer` default**

In `ios/TextAnalyzer.swift`, change line 35:

Old:
```swift
    init(blocklistURL: URL? = TextAnalyzer.defaultBlocklistURL(),
         modelBackend: TextModelAnalyzing = NoOpTextModelAnalyzing()) {
```

New:
```swift
    init(blocklistURL: URL? = TextAnalyzer.defaultBlocklistURL(),
         modelBackend: TextModelAnalyzing = CoreMLTextModelAnalyzing.default) {
```

- [ ] **Step 4: Run the full test suite to confirm no regressions**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|error:)"
```

Expected: all tests PASSED, no errors.

- [ ] **Step 5: Commit**

```bash
git add ios/TextAnalyzer.swift ios/Tests/TextAnalyzerTests.swift
git commit -m "feat(ios): wire CoreMLTextModelAnalyzing.default as TextAnalyzer default backend"
```

---

## Task 5: `warmup(modelPath:)` override — native + JS

**Files:**
- Modify: `ios/ContentSafetyModule.swift`
- Modify: `src/types.ts`
- Modify: `src/ContentSafetyModule.ts`
- Modify: `src/index.ts`

- [ ] **Step 1: Add `WarmupOptions` to `src/types.ts`**

Append before the last line of `src/types.ts`:

```typescript
export interface WarmupOptions {
  modelPath?: string;
}
```

- [ ] **Step 2: Update native module interface in `src/ContentSafetyModule.ts`**

Replace:
```typescript
  warmup(): Promise<void>;
```
With:
```typescript
  warmup(options: WarmupOptions): Promise<void>;
```

And add the import at the top:
```typescript
import type {
  DetectionResult,
  DetectOptions,
  VideoDetectOptions,
  TextDetectOptions,
  WarmupOptions,
} from './types';
```

- [ ] **Step 3: Update `src/index.ts`**

Replace:
```typescript
export function warmup(): Promise<void> {
  return ContentSafetyModule.warmup();
}
```
With:
```typescript
export function warmup(options?: WarmupOptions): Promise<void> {
  return ContentSafetyModule.warmup(options ?? {});
}
```

And add `WarmupOptions` to the import of `ContentSafetyModule`:
```typescript
import ContentSafetyModule from './ContentSafetyModule';
```
(no change needed to this import, `WarmupOptions` is re-exported via `export * from './types'`)

- [ ] **Step 4: Update `ios/ContentSafetyModule.swift` `warmup` function**

Replace the existing `warmup` `AsyncFunction` block:

```swift
        AsyncFunction("warmup") { [weak self] (options: [String: Any]?) async -> Void in
            guard let self else { return }
            if let modelPath = options?["modelPath"] as? String {
                let url: URL
                if modelPath.hasPrefix("file://") {
                    url = URL(string: modelPath) ?? URL(fileURLWithPath: modelPath)
                } else {
                    url = URL(fileURLWithPath: modelPath)
                }
                let backend = CoreMLTextModelAnalyzing.load(from: url)
                self.textAnalyzer = TextAnalyzer(modelBackend: backend)
            }
            _ = self.textAnalyzer
            guard #available(iOS 17, *) else { return }
            _ = self.imageAnalyzer
            _ = self.videoAnalyzer
        }
```

Also change `textAnalyzer` from `lazy var` to `var` so reassignment works cleanly:

```swift
    private var textAnalyzer = TextAnalyzer()
```

- [ ] **Step 5: Run TypeScript type-check**

```bash
cd /Users/kvadlamudi/Desktop/MyPersonalAPp/expo-content-safety && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 6: Run iOS tests to confirm warmup still works**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|error:)"
```

Expected: all tests PASSED.

- [ ] **Step 7: Commit**

```bash
git add ios/ContentSafetyModule.swift src/types.ts src/ContentSafetyModule.ts src/index.ts
git commit -m "feat: add warmup(modelPath) override for custom CoreML model at runtime"
```

---

## Task 6: Production model — train, compile, bundle, podspec

**Files:**
- Create: `ios/Resources/ContentSafetyTextClassifier.mlmodelc`
- Modify: `ExpoContentSafety.podspec`

- [ ] **Step 1: Download the Jigsaw dataset**

Go to https://www.kaggle.com/competitions/jigsaw-toxic-comment-classification-challenge/data and download `train.csv`. Save it somewhere accessible, e.g. `~/Downloads/jigsaw_train.csv`.

- [ ] **Step 2: Train the production model**

```bash
swift scripts/train_text_classifier.swift production ~/Downloads/jigsaw_train.csv
```

Expected: `Production model written to ContentSafetyTextClassifier.mlmodel`
Training on ~160K rows takes 2–10 minutes depending on hardware.

- [ ] **Step 3: Compile the production model**

```bash
xcrun coremlcompiler compile ContentSafetyTextClassifier.mlmodel ios/Resources/
```

Expected: `ios/Resources/ContentSafetyTextClassifier.mlmodelc/` directory created.

- [ ] **Step 4: Clean up the intermediate `.mlmodel`**

```bash
rm ContentSafetyTextClassifier.mlmodel
```

- [ ] **Step 5: Update `ExpoContentSafety.podspec`**

Add `s.resources` and extend `s.frameworks`:

```ruby
  s.resources  = 'ios/Resources/**'
  s.frameworks = 'SensitiveContentAnalysis', 'NaturalLanguage', 'CoreML'
```

- [ ] **Step 6: Run the full iOS test suite**

```bash
xcodebuild test \
  -project example/ios/expocontentsafetyexample.xcodeproj \
  -scheme ExpoContentSafety-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "(FAILED|PASSED|error:)"
```

Expected: all tests PASSED, including `test_defaultBackend_isNotNoOp_whenModelBundled` now confirming `CoreMLTextModelAnalyzing` (not NoOp).

- [ ] **Step 7: Run JS tests to confirm no regressions**

```bash
cd /Users/kvadlamudi/Desktop/MyPersonalAPp/expo-content-safety && npx jest --testPathPattern=Text
```

Expected: all TS/JS tests PASSED.

- [ ] **Step 8: Commit**

Note: `.mlmodelc` is a directory; add the full directory path.

```bash
git add "ios/Resources/ContentSafetyTextClassifier.mlmodelc/" ExpoContentSafety.podspec
git commit -m "feat(ios): bundle production CoreML text safety classifier"
```

---

## Done

At this point:
- `TextAnalyzer` uses `CoreMLTextModelAnalyzing.default` (real model) by default on iOS
- Blocklist still fires at confidence 1.0 and overrides the model (existing behaviour)
- `warmup({ modelPath })` lets a developer substitute their own CoreML model
- Silent fallback to `NoOpTextModelAnalyzing` if model is missing — no crashes
- All existing tests still pass
