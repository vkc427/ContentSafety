# expo-content-safety — Milestone 1: Skeleton & JS API Surface

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a publishable Expo Module named `expo-content-safety` with the full TypeScript public API, JS unit tests, and stubbed native modules on both iOS and Android — no real ML inference yet, just shape-correct fake `DetectionResult` objects.

**Architecture:** One Expo Module, three JS namespaces (`Image`, `Video`, `Text`). The JS layer validates inputs, fills in option defaults, and forwards to a single native module via `requireNativeModule('ContentSafety')`. Native code (Swift + Kotlin) is stubbed to return fixed `DetectionResult` objects so the entire JS surface can be tested end-to-end before any ML work begins.

**Tech Stack:** TypeScript, Expo Modules API, Jest + `jest-expo`, Swift (iOS 17+), Kotlin (Android minSdk 24).

**Spec:** `docs/superpowers/specs/2026-05-23-expo-content-safety-design.md`

---

## Conventions

- Package directory is the repo root: `/Users/kvadlamudi/expo-content-safety/`.
- All paths in this plan are relative to that directory unless explicitly absolute.
- Commit after every task. Use Conventional Commits (`feat:`, `test:`, `chore:`, etc.).
- After each task that adds tests, run `npm test` and confirm green before moving on.

---

### Task 1: Scaffold the Expo Module via `create-expo-module`

We can't run `create-expo-module` directly into the existing directory (it expects an empty target). Approach: scaffold in a temp dir, then merge into the existing repo while preserving `.git/` and `docs/`.

**Files:**
- Create: every file produced by `create-expo-module`
- Preserve: `.git/`, `docs/`, `.gitignore`

- [ ] **Step 1: Scaffold into a temp directory**

```bash
cd /tmp
npx create-expo-module@latest expo-content-safety-scaffold \
  --no-recommended-packages
```

When the interactive prompt appears, answer:
- npm package name: `expo-content-safety`
- Native module name: `ExpoContentSafety` (it will accept `ContentSafety` only if you set the JS name; default is fine to start)
- GitHub username: your username
- Author name / email: your details
- License: `MIT`

Expected: a fully scaffolded module at `/tmp/expo-content-safety-scaffold/`.

- [ ] **Step 2: Merge scaffold into our existing repo without clobbering**

```bash
cd /Users/kvadlamudi/expo-content-safety
# Use rsync to avoid overwriting .git and docs
rsync -a --exclude='.git' --exclude='docs' \
  /tmp/expo-content-safety-scaffold/ \
  /Users/kvadlamudi/expo-content-safety/
```

Expected: all scaffolded files appear in the repo; `docs/superpowers/` is untouched; `git status` shows many new untracked files.

- [ ] **Step 3: Verify the scaffold works**

```bash
npm install
cd example && npm install && cd ..
npm run build
```

Expected: `npm install` completes; `npm run build` produces `build/` directory with compiled JS and `.d.ts` files. No errors.

- [ ] **Step 4: Commit the scaffold**

```bash
git add -A
git commit -m "chore: scaffold Expo Module via create-expo-module"
```

Expected: large initial commit.

---

### Task 2: Define `DetectionResult` and related types

We want a single source of truth for the result shape, options, and error class.

**Files:**
- Create: `src/types.ts`
- Test: `src/__tests__/types.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/__tests__/types.test.ts`:

```ts
import { ContentSafetyError } from '../types';

describe('ContentSafetyError', () => {
  it('captures the error code', () => {
    const err = new ContentSafetyError('INVALID_INPUT', 'bad uri');
    expect(err.code).toBe('INVALID_INPUT');
    expect(err.message).toBe('bad uri');
    expect(err.name).toBe('ContentSafetyError');
    expect(err).toBeInstanceOf(Error);
  });

  it('keeps the stack trace', () => {
    const err = new ContentSafetyError('INFERENCE_FAILED', 'boom');
    expect(err.stack).toContain('ContentSafetyError');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern=types.test.ts
```

Expected: FAIL with `Cannot find module '../types'` or similar.

- [ ] **Step 3: Implement the types**

Create `src/types.ts`:

```ts
export type DetectionSource =
  | 'apple-sca'
  | 'tflite-image'
  | 'tflite-text'
  | 'blocklist';

export interface DetectionCategories {
  nudity?: number;
  sexual?: number;
  violence?: number;
  gore?: number;
  drugs?: number;
  [key: string]: number | undefined;
}

export interface DetectionResult {
  isNSFW: boolean;
  confidence: number;
  categories?: DetectionCategories;
  threshold: number;
  source: DetectionSource;
  durationMs: number;
  framesAnalyzed?: number;
}

export interface DetectOptions {
  threshold?: number;
}

export interface VideoDetectOptions extends DetectOptions {
  sampleRate?: number;
  maxFrames?: number;
  stopOnFirstHit?: boolean;
}

export interface TextDetectOptions extends DetectOptions {
  blocklist?: string[];
  useBlocklist?: boolean;
  useModel?: boolean;
}

export type ContentSafetyErrorCode =
  | 'UNSUPPORTED_PLATFORM'
  | 'INVALID_INPUT'
  | 'MODEL_LOAD_FAILED'
  | 'INFERENCE_FAILED'
  | 'IOS_VERSION_TOO_LOW';

export class ContentSafetyError extends Error {
  readonly code: ContentSafetyErrorCode;

  constructor(code: ContentSafetyErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'ContentSafetyError';
    Object.setPrototypeOf(this, ContentSafetyError.prototype);
  }
}

export const DEFAULT_THRESHOLD = 0.7;
export const DEFAULT_VIDEO_SAMPLE_RATE = 1;
export const DEFAULT_VIDEO_MAX_FRAMES = 30;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern=types.test.ts
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/types.ts src/__tests__/types.test.ts
git commit -m "feat: define DetectionResult and ContentSafetyError types"
```

---

### Task 3: Wrap the native module access

We expose exactly one place in the JS layer that touches the native side. Everything else imports from here.

**Files:**
- Create: `src/ContentSafetyModule.ts`

- [ ] **Step 1: Implement the wrapper**

Create `src/ContentSafetyModule.ts`:

```ts
import { requireNativeModule } from 'expo-modules-core';
import type {
  DetectionResult,
  DetectOptions,
  VideoDetectOptions,
  TextDetectOptions,
} from './types';

interface ContentSafetyNativeModule {
  detectImage(uri: string, options: Required<DetectOptions>): Promise<DetectionResult>;
  detectVideo(uri: string, options: Required<VideoDetectOptions>): Promise<DetectionResult>;
  detectText(input: string, options: Required<TextDetectOptions>): Promise<DetectionResult>;
  warmup(): Promise<void>;
}

const ContentSafetyModule =
  requireNativeModule<ContentSafetyNativeModule>('ContentSafety');

export default ContentSafetyModule;
```

- [ ] **Step 2: Verify it type-checks**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/ContentSafetyModule.ts
git commit -m "feat: add ContentSafetyModule native wrapper"
```

---

### Task 4: Implement `Image.detect`

Validates the URI, applies defaults, forwards to native.

**Files:**
- Create: `src/Image.ts`
- Test: `src/__tests__/Image.test.ts`

- [ ] **Step 1: Set up the native module mock**

Create `src/__tests__/__mocks__/ContentSafetyModule.ts`:

```ts
const detectImage = jest.fn();
const detectVideo = jest.fn();
const detectText = jest.fn();
const warmup = jest.fn();

export default { detectImage, detectVideo, detectText, warmup };
```

Add to `package.json` Jest config (if not already present):

```json
"jest": {
  "preset": "jest-expo",
  "moduleNameMapper": {
    "^\\./ContentSafetyModule$": "<rootDir>/src/__tests__/__mocks__/ContentSafetyModule.ts"
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `src/__tests__/Image.test.ts`:

```ts
import { Image } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';
import { ContentSafetyError } from '../types';

const mockedNative = ContentSafetyModule as unknown as {
  detectImage: jest.Mock;
};

describe('Image.detect', () => {
  beforeEach(() => {
    mockedNative.detectImage.mockReset();
    mockedNative.detectImage.mockResolvedValue({
      isNSFW: false,
      confidence: 0.1,
      threshold: 0.7,
      source: 'apple-sca',
      durationMs: 12,
    });
  });

  it('rejects empty uris', async () => {
    await expect(Image.detect('')).rejects.toMatchObject({
      code: 'INVALID_INPUT',
    });
    expect(mockedNative.detectImage).not.toHaveBeenCalled();
  });

  it('rejects non-string uris', async () => {
    // @ts-expect-error testing runtime validation
    await expect(Image.detect(null)).rejects.toBeInstanceOf(ContentSafetyError);
  });

  it('forwards default threshold when omitted', async () => {
    await Image.detect('file:///tmp/x.jpg');
    expect(mockedNative.detectImage).toHaveBeenCalledWith(
      'file:///tmp/x.jpg',
      { threshold: 0.7 }
    );
  });

  it('forwards caller-supplied threshold', async () => {
    await Image.detect('file:///tmp/x.jpg', { threshold: 0.9 });
    expect(mockedNative.detectImage).toHaveBeenCalledWith(
      'file:///tmp/x.jpg',
      { threshold: 0.9 }
    );
  });

  it('rejects thresholds outside [0, 1]', async () => {
    await expect(
      Image.detect('file:///tmp/x.jpg', { threshold: 1.5 })
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
    await expect(
      Image.detect('file:///tmp/x.jpg', { threshold: -0.1 })
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });

  it('returns the native result unchanged', async () => {
    const result = await Image.detect('file:///tmp/x.jpg');
    expect(result).toEqual({
      isNSFW: false,
      confidence: 0.1,
      threshold: 0.7,
      source: 'apple-sca',
      durationMs: 12,
    });
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
npm test -- --testPathPattern=Image.test.ts
```

Expected: FAIL with `Cannot find module '../index'` or similar.

- [ ] **Step 4: Implement `Image.ts`**

Create `src/Image.ts`:

```ts
import ContentSafetyModule from './ContentSafetyModule';
import {
  ContentSafetyError,
  DEFAULT_THRESHOLD,
  type DetectOptions,
  type DetectionResult,
} from './types';

function validateUri(uri: unknown): asserts uri is string {
  if (typeof uri !== 'string' || uri.length === 0) {
    throw new ContentSafetyError('INVALID_INPUT', 'uri must be a non-empty string');
  }
}

function resolveOptions(options: DetectOptions = {}): Required<DetectOptions> {
  const threshold = options.threshold ?? DEFAULT_THRESHOLD;
  if (threshold < 0 || threshold > 1 || Number.isNaN(threshold)) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      `threshold must be between 0 and 1, got ${threshold}`,
    );
  }
  return { threshold };
}

export async function detect(
  uri: string,
  options?: DetectOptions,
): Promise<DetectionResult> {
  validateUri(uri);
  const resolved = resolveOptions(options);
  return ContentSafetyModule.detectImage(uri, resolved);
}
```

- [ ] **Step 5: Create temporary `src/index.ts` so the test can import `Image`**

Create `src/index.ts`:

```ts
import * as Image from './Image';
import * as Video from './Video';
import * as Text from './Text';

export { Image, Video, Text };
export * from './types';
export { default } from './ContentSafetyModule';
```

We haven't written `Video.ts` and `Text.ts` yet. Add temporary stubs so the import resolves; we'll flesh them out in Tasks 5 and 6:

Create `src/Video.ts`:

```ts
export async function detect(): Promise<never> {
  throw new Error('not implemented yet');
}
```

Create `src/Text.ts`:

```ts
export async function detect(): Promise<never> {
  throw new Error('not implemented yet');
}
```

- [ ] **Step 6: Run test to verify it passes**

```bash
npm test -- --testPathPattern=Image.test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 7: Commit**

```bash
git add src/Image.ts src/Video.ts src/Text.ts src/index.ts \
        src/ContentSafetyModule.ts src/__tests__/Image.test.ts \
        src/__tests__/__mocks__/ContentSafetyModule.ts package.json
git commit -m "feat: implement Image.detect with validation"
```

---

### Task 5: Implement `Video.detect`

Same pattern as Image, plus video-specific option defaults.

**Files:**
- Replace: `src/Video.ts`
- Test: `src/__tests__/Video.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/__tests__/Video.test.ts`:

```ts
import { Video } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';

const mockedNative = ContentSafetyModule as unknown as {
  detectVideo: jest.Mock;
};

describe('Video.detect', () => {
  beforeEach(() => {
    mockedNative.detectVideo.mockReset();
    mockedNative.detectVideo.mockResolvedValue({
      isNSFW: false,
      confidence: 0.05,
      threshold: 0.7,
      source: 'tflite-image',
      durationMs: 240,
      framesAnalyzed: 4,
    });
  });

  it('applies all default options when none provided', async () => {
    await Video.detect('file:///tmp/clip.mp4');
    expect(mockedNative.detectVideo).toHaveBeenCalledWith(
      'file:///tmp/clip.mp4',
      {
        threshold: 0.7,
        sampleRate: 1,
        maxFrames: 30,
        stopOnFirstHit: true,
      },
    );
  });

  it('passes caller-supplied options through', async () => {
    await Video.detect('file:///tmp/clip.mp4', {
      threshold: 0.8,
      sampleRate: 3,
      maxFrames: 60,
      stopOnFirstHit: false,
    });
    expect(mockedNative.detectVideo).toHaveBeenCalledWith(
      'file:///tmp/clip.mp4',
      {
        threshold: 0.8,
        sampleRate: 3,
        maxFrames: 60,
        stopOnFirstHit: false,
      },
    );
  });

  it('rejects sampleRate <= 0', async () => {
    await expect(
      Video.detect('file:///tmp/clip.mp4', { sampleRate: 0 }),
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });

  it('rejects maxFrames < 1', async () => {
    await expect(
      Video.detect('file:///tmp/clip.mp4', { maxFrames: 0 }),
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });

  it('rejects empty uris', async () => {
    await expect(Video.detect('')).rejects.toMatchObject({
      code: 'INVALID_INPUT',
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern=Video.test.ts
```

Expected: FAIL — current `Video.detect` throws "not implemented yet".

- [ ] **Step 3: Implement `Video.ts`**

Replace `src/Video.ts` entirely:

```ts
import ContentSafetyModule from './ContentSafetyModule';
import {
  ContentSafetyError,
  DEFAULT_THRESHOLD,
  DEFAULT_VIDEO_SAMPLE_RATE,
  DEFAULT_VIDEO_MAX_FRAMES,
  type VideoDetectOptions,
  type DetectionResult,
} from './types';

function validateUri(uri: unknown): asserts uri is string {
  if (typeof uri !== 'string' || uri.length === 0) {
    throw new ContentSafetyError('INVALID_INPUT', 'uri must be a non-empty string');
  }
}

function resolveOptions(
  options: VideoDetectOptions = {},
): Required<VideoDetectOptions> {
  const threshold = options.threshold ?? DEFAULT_THRESHOLD;
  const sampleRate = options.sampleRate ?? DEFAULT_VIDEO_SAMPLE_RATE;
  const maxFrames = options.maxFrames ?? DEFAULT_VIDEO_MAX_FRAMES;
  const stopOnFirstHit = options.stopOnFirstHit ?? true;

  if (threshold < 0 || threshold > 1 || Number.isNaN(threshold)) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      `threshold must be between 0 and 1, got ${threshold}`,
    );
  }
  if (sampleRate <= 0 || Number.isNaN(sampleRate)) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      `sampleRate must be > 0, got ${sampleRate}`,
    );
  }
  if (!Number.isInteger(maxFrames) || maxFrames < 1) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      `maxFrames must be a positive integer, got ${maxFrames}`,
    );
  }
  return { threshold, sampleRate, maxFrames, stopOnFirstHit };
}

export async function detect(
  uri: string,
  options?: VideoDetectOptions,
): Promise<DetectionResult> {
  validateUri(uri);
  const resolved = resolveOptions(options);
  return ContentSafetyModule.detectVideo(uri, resolved);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern=Video.test.ts
```

Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Video.ts src/__tests__/Video.test.ts
git commit -m "feat: implement Video.detect with validation"
```

---

### Task 6: Implement `Text.detect`

Same pattern; text-specific options.

**Files:**
- Replace: `src/Text.ts`
- Test: `src/__tests__/Text.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/__tests__/Text.test.ts`:

```ts
import { Text } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';

const mockedNative = ContentSafetyModule as unknown as {
  detectText: jest.Mock;
};

describe('Text.detect', () => {
  beforeEach(() => {
    mockedNative.detectText.mockReset();
    mockedNative.detectText.mockResolvedValue({
      isNSFW: false,
      confidence: 0.0,
      threshold: 0.7,
      source: 'blocklist',
      durationMs: 1,
    });
  });

  it('rejects empty strings', async () => {
    await expect(Text.detect('')).rejects.toMatchObject({
      code: 'INVALID_INPUT',
    });
  });

  it('rejects non-string inputs', async () => {
    // @ts-expect-error testing runtime validation
    await expect(Text.detect(42)).rejects.toMatchObject({
      code: 'INVALID_INPUT',
    });
  });

  it('applies all default options', async () => {
    await Text.detect('hello');
    expect(mockedNative.detectText).toHaveBeenCalledWith('hello', {
      threshold: 0.7,
      blocklist: [],
      useBlocklist: true,
      useModel: true,
    });
  });

  it('passes caller-supplied blocklist additions', async () => {
    await Text.detect('hello', { blocklist: ['banana'] });
    expect(mockedNative.detectText).toHaveBeenCalledWith('hello', {
      threshold: 0.7,
      blocklist: ['banana'],
      useBlocklist: true,
      useModel: true,
    });
  });

  it('honors useBlocklist=false and useModel=false', async () => {
    await Text.detect('hello', { useBlocklist: false, useModel: false });
    expect(mockedNative.detectText).toHaveBeenCalledWith('hello', {
      threshold: 0.7,
      blocklist: [],
      useBlocklist: false,
      useModel: false,
    });
  });

  it('rejects blocklist values that are not strings', async () => {
    await expect(
      // @ts-expect-error testing runtime validation
      Text.detect('hello', { blocklist: [123] }),
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern=Text.test.ts
```

Expected: FAIL — current `Text.detect` throws "not implemented yet".

- [ ] **Step 3: Implement `Text.ts`**

Replace `src/Text.ts` entirely:

```ts
import ContentSafetyModule from './ContentSafetyModule';
import {
  ContentSafetyError,
  DEFAULT_THRESHOLD,
  type TextDetectOptions,
  type DetectionResult,
} from './types';

function validateInput(input: unknown): asserts input is string {
  if (typeof input !== 'string' || input.length === 0) {
    throw new ContentSafetyError('INVALID_INPUT', 'input must be a non-empty string');
  }
}

function resolveOptions(
  options: TextDetectOptions = {},
): Required<TextDetectOptions> {
  const threshold = options.threshold ?? DEFAULT_THRESHOLD;
  const blocklist = options.blocklist ?? [];
  const useBlocklist = options.useBlocklist ?? true;
  const useModel = options.useModel ?? true;

  if (threshold < 0 || threshold > 1 || Number.isNaN(threshold)) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      `threshold must be between 0 and 1, got ${threshold}`,
    );
  }
  if (!Array.isArray(blocklist) || blocklist.some((t) => typeof t !== 'string')) {
    throw new ContentSafetyError(
      'INVALID_INPUT',
      'blocklist must be an array of strings',
    );
  }
  return { threshold, blocklist, useBlocklist, useModel };
}

export async function detect(
  input: string,
  options?: TextDetectOptions,
): Promise<DetectionResult> {
  validateInput(input);
  const resolved = resolveOptions(options);
  return ContentSafetyModule.detectText(input, resolved);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern=Text.test.ts
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Text.ts src/__tests__/Text.test.ts
git commit -m "feat: implement Text.detect with validation"
```

---

### Task 7: Implement `warmup()` export

**Files:**
- Modify: `src/index.ts`
- Test: `src/__tests__/warmup.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/__tests__/warmup.test.ts`:

```ts
import { warmup } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';

const mockedNative = ContentSafetyModule as unknown as {
  warmup: jest.Mock;
};

describe('warmup', () => {
  it('calls the native warmup', async () => {
    mockedNative.warmup.mockResolvedValue(undefined);
    await warmup();
    expect(mockedNative.warmup).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
npm test -- --testPathPattern=warmup.test.ts
```

Expected: FAIL with `warmup is not a function` or `Cannot find name 'warmup'`.

- [ ] **Step 3: Add the export**

Modify `src/index.ts` to add the named export:

```ts
import * as Image from './Image';
import * as Video from './Video';
import * as Text from './Text';
import ContentSafetyModule from './ContentSafetyModule';

export { Image, Video, Text };
export * from './types';

export function warmup(): Promise<void> {
  return ContentSafetyModule.warmup();
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
npm test -- --testPathPattern=warmup.test.ts
```

Expected: PASS (1 test).

- [ ] **Step 5: Run the full test suite**

```bash
npm test
```

Expected: ALL tests pass (types, Image, Video, Text, warmup).

- [ ] **Step 6: Commit**

```bash
git add src/index.ts src/__tests__/warmup.test.ts
git commit -m "feat: expose warmup()"
```

---

### Task 8: Configure iOS deployment target to 17.0

The scaffolded `.podspec` targets a lower iOS version by default. Bump it.

**Files:**
- Modify: `ios/ExpoContentSafety.podspec` (exact filename produced by the scaffold may differ — likely `ios/ExpoContentSafety.podspec` or similar)
- Modify: `expo-module.config.json`

- [ ] **Step 1: Find the podspec**

```bash
ls ios/*.podspec
```

Expected: one `.podspec` file printed.

- [ ] **Step 2: Update the deployment target in the podspec**

Open the `.podspec` and replace the `s.platform` line. It currently looks like:

```ruby
s.platform       = :ios, '15.1'
```

Change to:

```ruby
s.platform       = :ios, '17.0'
```

- [ ] **Step 3: Update `expo-module.config.json`**

Open `expo-module.config.json`. Find the `platforms` section. Ensure it contains `"ios"` and `"android"`. Add iOS deployment target metadata so consumers see a clear error if they're on an older project:

```json
{
  "platforms": ["ios", "android"],
  "ios": {
    "modules": ["ContentSafetyModule"]
  },
  "android": {
    "modules": ["expo.modules.contentsafety.ContentSafetyModule"]
  }
}
```

(The exact module names will already be set correctly by the scaffold — only adjust the platforms and iOS target if scaffold defaults differ.)

- [ ] **Step 4: Commit**

```bash
git add ios/*.podspec expo-module.config.json
git commit -m "chore: target iOS 17.0 minimum"
```

---

### Task 9: Implement iOS native stub returning a fake `DetectionResult`

**Files:**
- Replace: `ios/ContentSafetyModule.swift` (filename may be `ios/ExpoContentSafetyModule.swift` from the scaffold — keep the name the scaffold gave you and update `Module.name` inside)

- [ ] **Step 1: Read the existing scaffolded module file**

```bash
cat ios/*.swift
```

Note the class name, file name, and how it's wired into the module config. We will replace its contents but keep the class/file name.

- [ ] **Step 2: Replace the module contents**

Open `ios/ContentSafetyModule.swift` (or whatever the scaffold named it). Replace the entire file with:

```swift
import ExpoModulesCore

public class ContentSafetyModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ContentSafety")

    AsyncFunction("detectImage") { (uri: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "apple-sca",
        "durationMs": 0
      ]
    }

    AsyncFunction("detectVideo") { (uri: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "tflite-image",
        "durationMs": 0,
        "framesAnalyzed": 0
      ]
    }

    AsyncFunction("detectText") { (input: String, options: [String: Any]) -> [String: Any] in
      let threshold = options["threshold"] as? Double ?? 0.7
      return [
        "isNSFW": false,
        "confidence": 0.0,
        "threshold": threshold,
        "source": "blocklist",
        "durationMs": 0
      ]
    }

    AsyncFunction("warmup") { () -> Void in
      // no-op stub; real impl loads models lazily
    }
  }
}
```

- [ ] **Step 3: Verify the example app builds for iOS**

```bash
cd example
npx expo prebuild --clean --platform ios
npx expo run:ios --no-build-cache
cd ..
```

Expected: app launches in iOS simulator. The default example screen renders (no errors in the Metro/Xcode logs about our module failing to load).

If `expo run:ios` is too heavy in the agent environment, fall back to:

```bash
cd example/ios && pod install && cd ../..
```

and confirm `pod install` succeeds and includes `ExpoContentSafety` in the generated `Podfile.lock`.

- [ ] **Step 4: Commit**

```bash
git add ios/
git commit -m "feat(ios): stub native module returning fake DetectionResult"
```

---

### Task 10: Configure Android minSdk and implement Kotlin stub

**Files:**
- Modify: `android/build.gradle`
- Replace: `android/src/main/java/expo/modules/contentsafety/ContentSafetyModule.kt`

- [ ] **Step 1: Verify or set `minSdk` to 24**

Open `android/build.gradle`. Find the `defaultConfig` block. Confirm it contains:

```gradle
defaultConfig {
  minSdkVersion 24
  // ...other lines
}
```

If `minSdkVersion` is missing or lower, add/change it to `24`.

- [ ] **Step 2: Find the existing Kotlin module file**

```bash
find android/src/main/java -name "*.kt"
```

Expected: one Kotlin file printed. Note its path and package.

- [ ] **Step 3: Replace the Kotlin module contents**

Open the Kotlin file. Replace its contents with (adjusting the `package` line to match the scaffolded package):

```kotlin
package expo.modules.contentsafety

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContentSafetyModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ContentSafety")

    AsyncFunction("detectImage") { uri: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "tflite-image",
        "durationMs" to 0,
      )
    }

    AsyncFunction("detectVideo") { uri: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "tflite-image",
        "durationMs" to 0,
        "framesAnalyzed" to 0,
      )
    }

    AsyncFunction("detectText") { input: String, options: Map<String, Any?> ->
      val threshold = (options["threshold"] as? Number)?.toDouble() ?: 0.7
      mapOf(
        "isNSFW" to false,
        "confidence" to 0.0,
        "threshold" to threshold,
        "source" to "blocklist",
        "durationMs" to 0,
      )
    }

    AsyncFunction("warmup") {
      // no-op stub
    }
  }
}
```

- [ ] **Step 4: If the package path differs, move the file**

If the scaffolded package is e.g. `expo.modules.expocontentsafety`, either:
- (a) keep it and update the `package` line in the Kotlin file accordingly, OR
- (b) `git mv` the file to `android/src/main/java/expo/modules/contentsafety/ContentSafetyModule.kt` and update `expo-module.config.json` to point at the new fully-qualified class name.

Pick (a) for least churn unless the scaffolded name is clearly wrong.

- [ ] **Step 5: Build the Android example app**

```bash
cd example
npx expo prebuild --clean --platform android
cd android && ./gradlew assembleDebug --no-daemon && cd ../..
```

Expected: `BUILD SUCCESSFUL`. Our module compiles into the example app's APK.

- [ ] **Step 6: Commit**

```bash
git add android/ expo-module.config.json
git commit -m "feat(android): stub native module returning fake DetectionResult"
```

---

### Task 11: Add an integration smoke test screen to the example app

This isn't an automated test — it's a human-runnable screen we can use later to verify each milestone on a real device.

**Files:**
- Replace: `example/App.tsx` (or whatever the scaffold named it)

- [ ] **Step 1: Replace the example app**

Open `example/App.tsx`. Replace its contents with:

```tsx
import { useState } from 'react';
import { Button, ScrollView, Text as RNText, StyleSheet, View } from 'react-native';
import { Image, Video, Text } from 'expo-content-safety';

export default function App() {
  const [output, setOutput] = useState<string>('Tap a button to call the stub.');

  async function runImage() {
    try {
      const result = await Image.detect('file:///placeholder.jpg');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  async function runVideo() {
    try {
      const result = await Video.detect('file:///placeholder.mp4');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  async function runText() {
    try {
      const result = await Text.detect('hello world');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <RNText style={styles.title}>expo-content-safety smoke test</RNText>
      <Button title="detect image" onPress={runImage} />
      <View style={styles.spacer} />
      <Button title="detect video" onPress={runVideo} />
      <View style={styles.spacer} />
      <Button title="detect text" onPress={runText} />
      <View style={styles.spacer} />
      <RNText style={styles.output}>{output}</RNText>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 24, paddingTop: 80 },
  title: { fontSize: 18, fontWeight: '600', marginBottom: 16 },
  spacer: { height: 12 },
  output: { marginTop: 24, fontFamily: 'Courier', fontSize: 12 },
});
```

- [ ] **Step 2: Smoke-test on iOS Simulator** (manual verification step)

```bash
cd example
npx expo run:ios
```

Expected: app launches; tapping each button shows a JSON `DetectionResult` with `isNSFW: false`, `confidence: 0`, the right `source` for each, and `threshold: 0.7`.

- [ ] **Step 3: Smoke-test on Android Emulator** (manual verification step)

```bash
cd example
npx expo run:android
```

Expected: app launches; tapping each button shows the same shape, with `source: "tflite-image"` for image/video and `"blocklist"` for text.

- [ ] **Step 4: Commit**

```bash
git add example/App.tsx
git commit -m "feat(example): add smoke-test screen for stubbed detectors"
```

---

### Task 12: Write a skeleton README

**Files:**
- Replace: `README.md`

- [ ] **Step 1: Write the README**

Replace `README.md` with:

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add skeleton README"
```

---

### Task 13: Final verification

- [ ] **Step 1: Run the full JS test suite**

```bash
npm test
```

Expected: ALL tests pass (Image, Video, Text, warmup, types).

- [ ] **Step 2: Type-check**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Build the package**

```bash
npm run build
```

Expected: `build/` directory contains compiled `.js` and `.d.ts` files for every TS file in `src/`.

- [ ] **Step 4: Inspect the public API**

```bash
cat build/index.d.ts
```

Expected: declarations for `Image`, `Video`, `Text`, `warmup`, plus all the types (`DetectionResult`, `DetectOptions`, `VideoDetectOptions`, `TextDetectOptions`, `ContentSafetyError`, etc.).

- [ ] **Step 5: Tag the milestone**

```bash
git tag -a v0.1.0-skeleton -m "Milestone 1: skeleton & JS API surface complete"
```

- [ ] **Step 6: Push to remote** (skip if no remote yet)

```bash
git push origin main --tags
```

---

## What's next (subsequent plans)

The following plans will be written one at a time after each is executed:

- **Plan 2:** iOS image detection via `SCSensitivityAnalyzer`
- **Plan 3:** Android image detection via bundled TFLite model
- **Plan 4:** Video detection on both platforms
- **Plan 5:** Text detection (blocklist + TFLite/Core ML classifier) on both platforms
- **Plan 6:** `warmup()` lifecycle polish, interpreter shutdown, native-error mapping
- **Plan 7:** Docs, attributions, example polish, npm publish
