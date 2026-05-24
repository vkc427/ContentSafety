import ContentSafetyModule from './ContentSafetyModule';
import {
  ContentSafetyError,
  DEFAULT_THRESHOLD,
  type ContentSafetyErrorCode,
  type DetectOptions,
  type DetectionResult,
} from './types';

const NATIVE_ERROR_CODES: ContentSafetyErrorCode[] = [
  'INVALID_INPUT',
  'INFERENCE_FAILED',
  'IOS_VERSION_TOO_LOW',
  'MODEL_LOAD_FAILED',
  'UNSUPPORTED_PLATFORM',
];

function remapNativeError(err: unknown): ContentSafetyError {
  if (err instanceof ContentSafetyError) return err;
  const message = err instanceof Error ? err.message : String(err);
  for (const code of NATIVE_ERROR_CODES) {
    if (message.startsWith(`${code}: `)) {
      return new ContentSafetyError(code, message.slice(code.length + 2));
    }
  }
  return new ContentSafetyError('INFERENCE_FAILED', message);
}

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
  try {
    return await ContentSafetyModule.detectImage(uri, resolved);
  } catch (err) {
    throw remapNativeError(err);
  }
}
