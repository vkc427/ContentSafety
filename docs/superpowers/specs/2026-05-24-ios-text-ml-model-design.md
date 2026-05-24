# iOS Real Text ML Model — Design Spec

**Date:** 2026-05-24
**Status:** Approved

## Goal

Replace the `NoOpTextModelAnalyzing` stub in the iOS `TextAnalyzer` with a real on-device CoreML binary classifier that detects both NSFW and toxic text. Ship a bundled default model with the pod; also allow developers to supply their own CoreML model at runtime.

## Scope

- iOS only (Android remains NoOp for now)
- Single combined confidence score (no separate NSFW vs. toxic breakdown)
- No changes to the public JS/TS API beyond an optional `modelPath` param on `warmup()`
- No changes to `DetectionResult` shape

---

## Architecture

Three moving parts:

### 1. `CoreMLTextModelAnalyzing` (new file: `ios/CoreMLTextModelAnalyzing.swift`)

Conforms to the existing `TextModelAnalyzing` protocol. Wraps Apple's `NLModel` from the `NaturalLanguage` framework.

```swift
final class CoreMLTextModelAnalyzing: TextModelAnalyzing {
    private let model: NLModel

    init(model: NLModel) { self.model = model }

    static var `default`: TextModelAnalyzing { /* loads bundled model, falls back to NoOp */ }

    func confidence(for text: String) -> Double {
        model.predictedLabelHypotheses(for: text, maximumCount: 2)?["unsafe"] ?? 0.0
    }
}
```

The `static var default` loader:
1. Looks for `ContentSafetyTextClassifier.mlmodelc` in `Bundle(for: CoreMLTextModelAnalyzing.self)`
2. On success: `MLModel → NLModel → CoreMLTextModelAnalyzing`
3. On any failure: silently returns `NoOpTextModelAnalyzing()` — detection degrades to blocklist-only, no crash

### 2. Bundled Model (`ios/Resources/ContentSafetyTextClassifier.mlmodelc`)

- **Type:** CoreML binary text classifier (`NLModel`-compatible)
- **Labels:** `"safe"` and `"unsafe"` (NSFW + toxic combined into one label)
- **Training tool:** Create ML `MLTextClassifier` (transfer learning, embedding-based)
- **Dataset:** Jigsaw Toxic Comment Classification (public Kaggle, ~160K rows). Toxic/severe_toxic/obscene/threat/insult/identity_hate rows → `"unsafe"`. Clean rows → `"safe"`.
- **Training script:** `scripts/train_text_classifier.swift` (reproducible offline step)
- **Compilation:** `xcrun coremlcompiler compile ContentSafetyTextClassifier.mlmodel ios/Resources/`

### 3. Developer Override

- **Native level:** `TextAnalyzer(modelBackend:)` already accepts any `TextModelAnalyzing` — pass a custom `CoreMLTextModelAnalyzing(model:)` with your own `MLModel`.
- **JS level:** `warmup({ modelPath: string })` — if `modelPath` is provided, the module loads a CoreML model from that file URI and replaces the backend. On load failure, the existing backend is kept unchanged.

---

## Data Flow

```
detectText(input, options)
    → TextAnalyzer.analyze()
        → normalize(input)                        // leet-speak substitution
        → blocklistScore  (if useBlocklist)       // regex match → 0.0 or 1.0
        → modelScore      (if useModel)
            → CoreMLTextModelAnalyzing.confidence(for: normalizedText)
                → NLModel.predictedLabelHypotheses()
                → return hypos["unsafe"] ?? 0.0
        → confidence = max(blocklistScore, modelScore)
        → isNSFW = confidence >= threshold
```

`source` field in the result:
- `"tflite-text"` when `modelScore > blocklistScore && useModel` (kept for cross-platform naming consistency)
- `"blocklist"` otherwise

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Model file missing from bundle | `default` falls back to `NoOpTextModelAnalyzing` silently |
| `NLModel` inference error | `confidence(for:)` returns `0.0` |
| Invalid `modelPath` from JS in `warmup` | Error caught, existing backend unchanged, no crash |
| Empty input | Caught by existing `TextAnalyzer` guard before reaching model |

All degradation is silent and graceful — matches the existing pattern for missing `blocklist.txt`.

---

## Podspec Changes (`ExpoContentSafety.podspec`)

```ruby
s.resources  = 'ios/Resources/**'
s.frameworks = 'SensitiveContentAnalysis', 'NaturalLanguage', 'CoreML'
```

---

## Testing

### Unit tests (`ios/Tests/CoreMLTextModelAnalyzingTests.swift`)

- Load a small `TestContentSafetyTextClassifier.mlmodelc` (trained on a tiny fixture dataset) from the test bundle — `NLModel` is a final Apple class and not mockable.
- **Cases:**
  - Clearly toxic input → confidence > 0.5
  - Clearly clean input → confidence < 0.5
  - Empty string → 0.0
  - `default` with nil bundle URL → returns `NoOpTextModelAnalyzing`

### Updates to `TextAnalyzerTests.swift`

- Integration case: `TextAnalyzer` with `CoreMLTextModelAnalyzing.default` wired in
- Fallback case: assert `NoOp` is used when model URL is nil

### JS layer

- `Text.test.ts` unchanged — module mock already stubs `detectText` at the JS boundary

---

## Files Changed / Added

| File | Change |
|---|---|
| `ios/CoreMLTextModelAnalyzing.swift` | New — real model implementation |
| `ios/TextAnalyzer.swift` | Change default `modelBackend` from `NoOpTextModelAnalyzing()` to `CoreMLTextModelAnalyzing.default` |
| `ios/ContentSafetyModule.swift` | Add optional `modelPath` handling to `warmup` |
| `ios/Resources/ContentSafetyTextClassifier.mlmodelc` | New — bundled compiled model |
| `ios/Tests/CoreMLTextModelAnalyzingTests.swift` | New — unit tests |
| `ios/Tests/Resources/TestContentSafetyTextClassifier.mlmodelc` | New — small fixture model for tests |
| `scripts/train_text_classifier.swift` | New — reproducible training script |
| `ExpoContentSafety.podspec` | Add `s.resources`, add `NaturalLanguage` + `CoreML` frameworks |

---

## Out of Scope

- Android text model (separate task)
- Separate NSFW vs. toxic scores
- Cloud-based inference
- Model versioning / auto-update
