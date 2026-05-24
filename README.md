# expo-content-safety

On-device NSFW detection for **images**, **videos**, and **text** in React Native / Expo apps.

## Status

| Capability | iOS                      | Android               |
|------------|--------------------------|-----------------------|
| Image      | ✅ SCSensitivityAnalyzer | stub (TFLite planned) |
| Video      | stub                     | stub                  |
| Text       | stub                     | stub                  |

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

## Privacy

All inference runs on-device. No content is uploaded to any server.

## License

MIT
