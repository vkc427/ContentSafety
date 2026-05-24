# expo-content-safety

On-device NSFW detection for **images**, **videos**, and **text** in React Native / Expo apps.

## Status

| Capability | iOS                      | Android                    |
|------------|--------------------------|----------------------------|
| Image      | ✅ SCSensitivityAnalyzer | ✅ TFLite MobileNetV2      |
| Video      | stub                     | stub                       |
| Text       | ✅ Blocklist (model stub) | ✅ Blocklist (model stub)  |

## Requirements

- iOS 17.0+
- Android API 24+ (Android 7.0+)
- React Native New Architecture or legacy Bridge (both supported)

## Install

```bash
npm install expo-content-safety
# or
yarn add expo-content-safety
```

## Usage

```ts
import { Image, Video, Text, warmup } from 'expo-content-safety';

// Optional: pre-load models on app start
await warmup();

const imageResult = await Image.detect(asset.uri, { threshold: 0.8 });
if (imageResult.isNSFW) showWarning(imageResult);

const videoResult = await Video.detect(videoUri, { sampleRate: 2 });
const textResult = await Text.detect(message, { blocklist: ['extra-term'] });
```

## Text detection

`Text.detect` checks a string against a built-in blocklist of explicit terms and, when a text ML model is bundled, runs it through the model too. The highest score from either source determines `isNSFW`.

```ts
import { Text } from 'expo-content-safety';

const result = await Text.detect('some user message');
// result.isNSFW    — true if score ≥ threshold
// result.confidence — 0–1
// result.source    — 'blocklist' | 'tflite-text'
// result.durationMs
```

### TextDetectOptions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `threshold` | `number` | `0.7` | Score at or above which `isNSFW` is `true` |
| `blocklist` | `string[]` | `[]` | Extra terms to add to the built-in seed blocklist |
| `useBlocklist` | `boolean` | `true` | Whether to run blocklist matching at all |
| `useModel` | `boolean` | `true` | Whether to run the ML model (no-op until a text model is bundled) |

### Blocklist details

The built-in seed list (~30 terms) covers common explicit vocabulary. Matching is:

- **Case-insensitive** — `PORN` matches `porn`
- **Word-boundary anchored** — `anal` won't match `analysis`
- **Leetspeak-normalised** — `0→o`, `1→i`, `3→e`, `4→a`, `5→s`, `@→a`, `$→s`
- **Whitespace-flexible** for multi-word terms — `sexual assault` matches regardless of spacing

Pass `blocklist: ['extra-term']` to extend with domain-specific terms at call time. Terms are normalized and matched with the same rules.

**ML model:** The text model slot currently uses a no-op stub (always returns `0.0`). The blocklist is the active detection layer. A real TFLite/CoreML text classifier can be plugged in later without any API changes.

## Error handling

All three `detect` functions throw `ContentSafetyError` on failure. Check `err.code` to handle specific cases:

```ts
import { Image, ContentSafetyError } from 'expo-content-safety';

try {
  const result = await Image.detect(uri);
} catch (err) {
  if (err instanceof ContentSafetyError) {
    switch (err.code) {
      case 'IOS_VERSION_TOO_LOW':
        // Device is below iOS 17 — image detection unavailable
        break;
      case 'INVALID_INPUT':
        // Bad URI or out-of-range option value
        break;
      case 'INFERENCE_FAILED':
        // The model ran but something went wrong
        break;
      case 'MODEL_LOAD_FAILED':
        // Could not initialise the underlying model
        break;
      case 'UNSUPPORTED_PLATFORM':
        // Running on a platform with no native implementation yet
        break;
    }
  }
}
```

### Error codes

| Code | When thrown |
|------|-------------|
| `INVALID_INPUT` | Empty URI, non-string input, or option value out of range (e.g. `threshold > 1`) |
| `IOS_VERSION_TOO_LOW` | Device is running iOS < 17 (image detection requires iOS 17+) |
| `INFERENCE_FAILED` | The native model ran but returned an error |
| `MODEL_LOAD_FAILED` | The model could not be initialised |
| `UNSUPPORTED_PLATFORM` | No native implementation available on the current platform |

Input validation errors (empty URI, bad threshold) are thrown before the native call and are also `ContentSafetyError` instances with `code: 'INVALID_INPUT'`.

## Android bundle size

The Android TFLite model adds ~17 MB to the APK/AAB. The model is memory-mapped at runtime (not extracted to disk) via `aaptOptions { noCompress 'tflite' }`.

## Model attribution

**Android image detection:** [GantMan/nsfw_model](https://github.com/GantMan/nsfw_model) — MobileNetV2 trained on NSFW imagery. MIT licensed. Classes: `drawings`, `hentai`, `neutral`, `porn`, `sexy`. `isNSFW` is `true` when `max(porn, hentai, sexy) ≥ threshold`.

**iOS image detection:** Apple [SCSensitivityAnalyzer](https://developer.apple.com/documentation/sensitivecontentanalysis) — on-device, no model attribution required.

## Accuracy disclaimer

These models are not perfect. False positives and false negatives will occur. For high-stakes moderation, combine with human review.

## Privacy

All inference runs on-device. No content is uploaded to any server.

## License

MIT
