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
