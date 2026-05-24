import { ContentSafetyError, type ContentSafetyErrorCode } from './types';

const NATIVE_ERROR_CODES: ContentSafetyErrorCode[] = [
  'INVALID_INPUT',
  'INFERENCE_FAILED',
  'IOS_VERSION_TOO_LOW',
  'MODEL_LOAD_FAILED',
  'UNSUPPORTED_PLATFORM',
];

export function remapNativeError(err: unknown): ContentSafetyError {
  if (err instanceof ContentSafetyError) return err;
  const message = err instanceof Error ? err.message : String(err);
  for (const code of NATIVE_ERROR_CODES) {
    if (message.startsWith(`${code}: `)) {
      return new ContentSafetyError(code, message.slice(code.length + 2));
    }
  }
  return new ContentSafetyError('INFERENCE_FAILED', message);
}
