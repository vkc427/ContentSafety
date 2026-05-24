# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-05-23

### Added

- **Image detection** — iOS via `SCSensitivityAnalyzer` (iOS 17+); Android via TFLite MobileNetV2 (GantMan, MIT)
- **Video detection** — iOS via `SCSensitivityAnalyzer.videoAnalysis`; Android via `MediaMetadataRetriever` + TFLite per-frame with `stopOnFirstHit`, `sampleRate`, and `maxFrames` controls
- **Text detection** — Blocklist (word-boundary anchored, leetspeak-normalised, whitespace-flexible) on both platforms; ML model slot is a no-op stub ready for a future text classifier
- **`warmup()`** — pre-loads image TFLite interpreter and text analyzer on both platforms
- **`ContentSafetyError`** — typed error class with `code` field (`INVALID_INPUT`, `INFERENCE_FAILED`, `MODEL_LOAD_FAILED`, `IOS_VERSION_TOO_LOW`, `UNSUPPORTED_PLATFORM`)
- New Architecture (TurboModules + Fabric) and legacy Bridge both supported via Expo Modules
