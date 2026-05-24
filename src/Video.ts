import ContentSafetyModule from './ContentSafetyModule';
import { remapNativeError } from './remapNativeError';
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
  try {
    return await ContentSafetyModule.detectVideo(uri, resolved);
  } catch (err) {
    throw remapNativeError(err);
  }
}
