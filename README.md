# expo-content-safety

On-device NSFW detection for **images**, **videos**, and **text** in React Native / Expo apps.

> ⚠️ **Milestone 1 (skeleton):** the JS API and native stubs are in place; real ML inference lands in subsequent milestones.

## Status

| Capability      | iOS                       | Android                       |
|-----------------|---------------------------|-------------------------------|
| Image           | stub (Apple SCA planned)  | stub (TFLite planned)         |
| Video           | stub                      | stub                          |
| Text            | stub                      | stub                          |

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

## Privacy

All inference runs on-device. No content is uploaded to any server.

## License

MIT
