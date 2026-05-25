export type DetectionSource =
  | 'apple-sca'
  | 'tflite-image'
  | 'coreml-text'
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

export interface WarmupOptions {
  modelPath?: string;
}
