# expo-content-safety — Design Spec

**Status:** Approved
**Date:** 2026-05-23
**Author:** kvadlamudi

## Goal

Build a React Native package — published as `expo-content-safety` — that detects NSFW content in **images**, **videos**, and **text** entirely on-device, with first-class support for both Expo and bare React Native, and for both the New Architecture (Fabric + TurboModules) and the legacy Bridge.

## Non-goals (v1)

The following are explicitly out of scope for v1. They are documented here so future contributors know they were considered and deferred.

- Live camera streaming (`processFrame(frame)` for vision-camera frame processors)
- Base64 / `ArrayBuffer` / raw buffer inputs
- BYOM (bring-your-own-model) configuration
- Per-frame video timeline results (we return one aggregated result per video)
- React hooks (`useImageSafety`, `useTextSafety`, etc.)
- Web platform support
- Cloud API fallback or hybrid mode

## Constraints

- **Platforms:** iOS and Android only.
- **iOS minimum:** 17.0. Older iOS is rejected at install time (podspec) and at runtime (defense-in-depth error).
- **Android minimum:** API 24 (Android 7.0), inherited from Expo Modules.
- **Privacy:** No content ever leaves the device. No analytics or telemetry on user content.
- **Architecture support:** New Architecture (TurboModules) is the default; legacy Bridge supported via Expo Modules' compatibility layer.
- **No `NativeModules.X` calls** anywhere in the JS layer. All native calls go through `requireNativeModule()`.

## Architecture overview

One Expo Module, one native module per platform, three JS sub-APIs.

```
expo-content-safety/
├── src/
│   ├── index.ts                  # re-exports Image, Video, Text, types, warmup
│   ├── Image.ts                  # Image.detect(uri, options)
│   ├── Video.ts                  # Video.detect(uri, options)
│   ├── Text.ts                   # Text.detect(input, options)
│   ├── types.ts                  # DetectionResult, options, ContentSafetyError
│   └── ContentSafetyModule.ts    # requireNativeModule wrapper
├── ios/
│   ├── ContentSafetyModule.swift # Expo Module definition (AsyncFunctions)
│   ├── ImageAnalyzer.swift       # wraps SCSensitivityAnalyzer
│   ├── VideoAnalyzer.swift       # AVAssetImageGenerator + ImageAnalyzer
│   ├── TextAnalyzer.swift        # Core ML text classifier + blocklist
│   └── Assets/                   # bundled into the framework via s.resources
│       ├── NSFWText.mlpackage    # ~5–15 MB Core ML text classifier
│       ├── vocab.txt             # tokenizer vocab (same source as Android)
│       └── blocklist.txt         # shared explicit-term list
├── android/
│   ├── src/main/java/.../ContentSafetyModule.kt
│   ├── src/main/java/.../ImageAnalyzer.kt    # TFLite image inference
│   ├── src/main/java/.../VideoAnalyzer.kt    # MediaMetadataRetriever + ImageAnalyzer
│   ├── src/main/java/.../TextAnalyzer.kt     # TFLite text inference + blocklist
│   └── src/main/assets/
│       ├── nsfw_image.tflite     # ~5–8 MB (GantMan MobileNetV2 lineage, MIT)
│       ├── nsfw_text.tflite      # ~5–15 MB (see Text model selection below)
│       ├── vocab.txt             # WordPiece vocab for text model tokenizer
│       └── blocklist.txt         # shared explicit-term list
├── example/                      # standard Expo Modules sample app for E2E + manual QA
├── __fixtures__/                 # benign test images (SFW only, never NSFW)
├── expo-module.config.json
├── package.json
├── README.md
└── LICENSE                       # MIT
```

### Module boundaries

- **JS layer** is platform-agnostic. It validates inputs, applies option defaults, and forwards to the native module. It never talks to platform-specific code paths directly.
- **Each `*Analyzer`** owns exactly one detection type and exposes a single async `analyze(...)` entry point. No cross-analyzer coupling beyond `VideoAnalyzer` calling `ImageAnalyzer` for per-frame inference.
- **Result objects** are normalized to a single TypeScript shape in the native code before crossing the bridge. Both platforms emit identical JSON.

## Public TypeScript API

```ts
export interface DetectionResult {
  isNSFW: boolean;            // overall flag, based on `confidence >= threshold`
  confidence: number;         // 0.0–1.0, the highest category score
  categories?: {              // present when the underlying model exposes them
    nudity?: number;
    sexual?: number;
    violence?: number;
    gore?: number;
    drugs?: number;
    [key: string]: number | undefined;
  };
  threshold: number;          // the threshold used for this call (echoed back)
  source: 'apple-sca' | 'tflite-image' | 'tflite-text' | 'blocklist';
  durationMs: number;         // time spent in native inference
  framesAnalyzed?: number;    // present on Video results only
}

export interface DetectOptions {
  threshold?: number;         // default 0.7
}

export interface VideoDetectOptions extends DetectOptions {
  sampleRate?: number;        // frames per second to sample, default 1
  maxFrames?: number;         // hard cap on frames analyzed, default 30
  stopOnFirstHit?: boolean;   // short-circuit when one frame trips threshold, default true
}

export interface TextDetectOptions extends DetectOptions {
  blocklist?: string[];       // additional terms appended to the built-in list
  useBlocklist?: boolean;     // default true
  useModel?: boolean;         // default true
}

export const Image: {
  detect(uri: string, options?: DetectOptions): Promise<DetectionResult>;
};

export const Video: {
  detect(uri: string, options?: VideoDetectOptions): Promise<DetectionResult>;
};

export const Text: {
  detect(input: string, options?: TextDetectOptions): Promise<DetectionResult>;
};

export function warmup(): Promise<void>;

export class ContentSafetyError extends Error {
  code:
    | 'UNSUPPORTED_PLATFORM'
    | 'INVALID_INPUT'
    | 'MODEL_LOAD_FAILED'
    | 'INFERENCE_FAILED'
    | 'IOS_VERSION_TOO_LOW';
}
```

### API design decisions

- **`categories` is optional.** It's `undefined` when the underlying engine returns only a binary score (Apple SCA). Callers must handle the optional case.
- **`source` is always populated** so callers can distinguish engines for analytics, debugging, or differential thresholding.
- **`threshold` is echoed back** in the result so the consumer always knows what decision boundary was applied (including the default `0.7` when none was passed).
- **`threshold` on iOS image/video is informational only**, since SCA encapsulates its own decision. We still surface the field for shape consistency.
- **`Video.detect` short-circuits by default** (`stopOnFirstHit: true`); most apps want "is this video NSFW" rather than a full timeline.
- **`warmup()` is exposed** so apps can pre-load TFLite interpreters at app start to avoid first-call latency.

### Usage example

```ts
import { Image, Video, Text } from 'expo-content-safety';

const result = await Image.detect(asset.uri, { threshold: 0.8 });
if (result.isNSFW) showWarning(result);

const videoResult = await Video.detect(videoUri, { sampleRate: 2, stopOnFirstHit: true });
const textResult = await Text.detect(message, { blocklist: ['extra-term'] });
```

## iOS implementation

**Minimum target:** iOS 17.0. Set in `expo-module.config.json` (`ios.deploymentTarget`) and the `.podspec` (`s.platform = :ios, "17.0"`).

### `ImageAnalyzer.swift`

- Imports `SensitiveContentAnalysis` and uses `SCSensitivityAnalyzer`.
- Flow: receive URI → resolve to `URL` (`file://`) → call `analyzer.analyzeImage(at:)` → map result.
- SCA returns `isSensitive: Bool` only — no per-category scores. Mapping:
  - `isNSFW = analysis.isSensitive`
  - `confidence = analysis.isSensitive ? 1.0 : 0.0`
  - `categories = nil` (omitted in the JSON)
  - `source = "apple-sca"`
- The caller's `threshold` is recorded in the result but does not affect the SCA decision boundary.

### `VideoAnalyzer.swift`

- Uses `AVAssetImageGenerator` to extract frames at `sampleRate` fps, capped at `maxFrames`.
- Each `CGImage` is wrapped in a `UIImage` and analyzed via `SCSensitivityAnalyzer.analyzeImage(_:)`.
- Aggregation: if any frame is sensitive, the video is sensitive. With `stopOnFirstHit: true`, the generator is cancelled the moment a sensitive frame is found.
- Result includes `framesAnalyzed` for transparency.

### `TextAnalyzer.swift`

- **Blocklist path:** built-in compiled list (`assets/blocklist.txt`, also bundled on iOS via the podspec's `s.resources`) plus any caller-provided terms. Implemented with `NSRegularExpression` using word boundaries and a small leetspeak normalizer (e.g., `0`→`o`, `1`→`i`, `5`→`s`).
- **Model path:** bundled Core ML text classifier (`ios/Assets/NSFWText.mlpackage`) — converted from the same source TFLite model used on Android via `coremltools` to keep parity. Run via `MLModel` directly (`NLModel`'s schema is too restrictive for the conversion path). See **Text model selection** below.
- **Merge rule:** both paths run; the final `DetectionResult` carries the higher `confidence` of the two. `source = "blocklist"` if the blocklist won, `"tflite-text"` otherwise (the `tflite-text` name is kept across platforms for simplicity, even though it's Core ML on iOS). If one path is disabled via `useBlocklist: false` or `useModel: false`, only the other runs.

### Error handling

- iOS <17 at runtime → throw `ContentSafetyError('IOS_VERSION_TOO_LOW')`.
- Invalid file URI / unreadable file → `ContentSafetyError('INVALID_INPUT')`.
- SCA initialization failure → `ContentSafetyError('MODEL_LOAD_FAILED')`.
- Inference throws → `ContentSafetyError('INFERENCE_FAILED')` with the underlying error message attached.

### Permissions

SCA does **not** require an Info.plist entry or runtime permission for analyzing file URIs the app can already read. File-system access to the URI is the caller's responsibility (e.g., via `expo-image-picker`).

### Threading

All native inference runs on `DispatchQueue.global(qos: .userInitiated)`. Results are marshalled back via the Expo Modules `AsyncFunction` promise plumbing.

## Android implementation

**Minimum target:** `minSdk = 24` (inherited from Expo Modules).

### Dependencies

```gradle
implementation 'org.tensorflow:tensorflow-lite:2.16.1'
implementation 'org.tensorflow:tensorflow-lite-support:0.4.4'
implementation 'org.tensorflow:tensorflow-lite-gpu-delegate-plugin:0.4.4'  // optional GPU
```

(Versions pinned at design time; will be revisited during implementation if newer stable releases are available.)

### `ImageAnalyzer.kt`

- Loads `assets/nsfw_image.tflite` lazily on first use (or eagerly via `warmup()`).
- **Model choice:** GantMan/NSFW MobileNetV2 (MIT-licensed) — 5 output classes: `drawings`, `hentai`, `neutral`, `porn`, `sexy`. ~5–8 MB quantized.
- Flow: receive URI → decode to `Bitmap` (using `ImageDecoder` on API 28+, `BitmapFactory` otherwise) → resize to 224×224 with `inSampleSize` guarding against >1024px source → normalize to float32 → run `interpreter.run(...)` → softmax → map to normalized `categories`.
- Output mapping: `categories = { nudity: porn, sexual: sexy, drawings, neutral, hentai }`.
- `isNSFW = max(porn, hentai, sexy) >= threshold`.
- `source = "tflite-image"`.

### `VideoAnalyzer.kt`

- Uses `MediaMetadataRetriever.setDataSource(uri)` and `getFrameAtTime(timeUs, OPTION_CLOSEST)` to extract frames at `sampleRate` fps up to `maxFrames`.
- Each `Bitmap` is fed directly into `ImageAnalyzer.analyzeBitmap(bitmap)` (bypassing the URI→decode hop).
- Same aggregation rules as iOS: `stopOnFirstHit` short-circuits.
- `framesAnalyzed` populated in the result.
- `source = "tflite-image"`.
- Known limitation: `MediaMetadataRetriever` is OK for clips up to a few minutes; longer videos may need a `MediaCodec`-based extractor (deferred to v2).

### `TextAnalyzer.kt`

- **Blocklist path:** shared `assets/blocklist.txt` compiled into a regex with word boundaries and the same leetspeak normalizer as iOS.
- **Model path:** bundled `assets/nsfw_text.tflite` with `assets/vocab.txt` for WordPiece tokenization (using `BertTokenizer` from `tensorflow-lite-support`). See **Text model selection** below.
- **Merge rule (shared with iOS):** both paths run; the final `DetectionResult` carries the higher `confidence` of the two. `source = "blocklist"` if the blocklist won, `"tflite-text"` otherwise. If one path is disabled via `useBlocklist: false` or `useModel: false`, only the other runs.

### Model loading & lifecycle

- Interpreters are singletons per analyzer, created lazily on first `detect()` call or eagerly by `warmup()`.
- Closed only when the module is destroyed (via Expo Module's `OnDestroy` lifecycle hook).
- Delegate strategy: try GPU → fall back to NNAPI → fall back to CPU. Delegate failures are logged but never thrown.

### Memory

- Bitmaps decoded with `inSampleSize` to cap pre-resize size at 1024×1024 to avoid OOM on large images.
- Bitmaps recycled after inference.

### Threading

Inference runs on `Dispatchers.IO` via Kotlin coroutines. Expo Modules' `AsyncFunction` provides the promise plumbing.

### Asset handling

Models live in `android/src/main/assets/` and are loaded via `AssetManager.openFd()`. The module's `build.gradle` sets `aaptOptions { noCompress 'tflite' }` so models stay mmap-able from the APK/AAB without an extraction step.

### Bundle size

Total Android contribution: ~10–25 MB raw, ~8–18 MB after AAB delivery. Documented prominently in the README so adopters aren't surprised.

## Text model selection

The exact text classifier is chosen during implementation milestone 5 from candidates that meet **all** of the following criteria:

- **License:** MIT, Apache-2.0, or BSD (no GPL/CC-BY-SA, no "research only" terms).
- **Size after dynamic-range quantization:** ≤ 15 MB.
- **TFLite conversion path:** must successfully convert from PyTorch/TF to TFLite and round-trip through `coremltools` to Core ML without losing the classification head.
- **Output:** at least one of {toxicity, sexual_explicit, threat} categories. We map whatever it emits onto our normalized `categories` shape.
- **Tokenizer:** WordPiece or SentencePiece, with a vocab file we can bundle (≤ 1 MB).

Current frontrunners (to be evaluated in milestone 5):
- **Detoxify "original-small"** (Apache-2.0) — emits 6 toxicity categories, distilled BERT base.
- **MobileBERT fine-tuned on Jigsaw + sexual-content corpus** — needs more validation work but smaller.

If no candidate passes the criteria, milestone 5 may ship blocklist-only and the model is deferred to v1.1.

## Architecture compatibility (Fabric + TurboModules)

- The module is defined using the **Expo Modules API** (`Module { ... }` DSL in Swift/Kotlin), which automatically compiles to a TurboModule on the New Architecture and to a legacy NativeModule on the old one.
- All exposed methods use `AsyncFunction` (which maps to JSI-backed async on New Arch, promise-based on Bridge).
- The JS layer accesses the native module exclusively via `requireNativeModule('ContentSafety')` — never `NativeModules.ContentSafety`. This is what enables transparent New/Old Arch compatibility.
- No view components are exposed in v1, so no Fabric-specific work is needed beyond following Expo Modules' defaults.

## Testing strategy

### JS layer (Jest with `jest-expo` preset)

- Mock `requireNativeModule('ContentSafety')` to return canned results.
- Test argument validation: empty strings, malformed URIs, out-of-range thresholds.
- Test result-shape normalization and option defaults.
- Verify each namespace (`Image`, `Video`, `Text`) calls the right native method with the right payload.

### iOS native

- XCTest target in `ios/Tests/`.
- Fixture-driven tests for `ImageAnalyzer` and `VideoAnalyzer` using benign SFW images committed to `__fixtures__/`.
- `TextAnalyzer` tested with a fixed blocklist and a stubbed Core ML model.

### Android native

- JUnit + Robolectric for non-TFLite paths (blocklist, URI parsing).
- Instrumented tests in `androidTest/` for TFLite inference on an emulator, using the bundled fixture assets.

### Integration / E2E

- `example/` Expo app inside the repo, scaffolded by `create-expo-module`.
- Manual test screen for image picker → detect, video picker → detect, text input → detect.
- Detox E2E is deferred to v2.

### Fixtures policy

We commit only benign images and synthetic patterns to `__fixtures__/`. NSFW imagery is **never** committed; "positive" cases are exercised via mocked analyzer responses in unit tests, and through ad-hoc manual testing on developer devices.

## Distribution

- Published to **npm** as `expo-content-safety`.
- Repo includes the `example/` app for adopters to clone and try.
- Build/lint/test commands wired via `expo-module-scripts`.
- License: **MIT**. README enumerates the model licenses and attributions separately.
- README must cover:
  - Bundle-size impact (with concrete numbers).
  - iOS 17+ requirement.
  - Model attributions and their licenses.
  - Privacy statement ("all inference happens on-device; no data leaves the device").
  - Accuracy disclaimer (the model is not perfect; combine with human moderation for high-stakes use).

## Rollout plan / milestones

Loose phasing — exact ordering will be nailed down in the implementation plan. Each milestone ends with the `example/` app exercising the new capability on a real device.

1. **Skeleton.** Scaffold via `create-expo-module`. TypeScript surface compiles. Stub native methods return fake `DetectionResult` objects. JS unit tests green.
2. **iOS image.** Wire `SCSensitivityAnalyzer`. Verify in `example/` with a real device.
3. **Android image.** Bundle TFLite model and write inference path. Verify in `example/`.
4. **Video (both platforms).** Frame extraction + reuse image analyzers.
5. **Text (both platforms).** Blocklist first, then bundled classifier.
6. **Lifecycle polish.** `warmup()`, interpreter shutdown, error mapping, threading audit.
7. **Docs & release.** README, attributions, `example/` polish, npm publish.

## Open questions

None blocking implementation. Items deferred to v2 (live camera frames, BYOM, hooks, web) are tracked in **Non-goals** above.
