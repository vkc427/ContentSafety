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
