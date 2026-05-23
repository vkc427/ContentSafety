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
