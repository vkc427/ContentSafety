import { Text } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';
import { ContentSafetyError } from '../types';

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

  describe('native error remapping', () => {
    it('remaps INFERENCE_FAILED prefix to ContentSafetyError', async () => {
      mockedNative.detectText.mockRejectedValue(
        new Error('INFERENCE_FAILED: model output malformed')
      );
      await expect(Text.detect('hello')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'model output malformed',
      });
    });

    it('remaps IOS_VERSION_TOO_LOW prefix to ContentSafetyError', async () => {
      mockedNative.detectText.mockRejectedValue(
        new Error('IOS_VERSION_TOO_LOW: iOS 17.0+ is required for image analysis')
      );
      await expect(Text.detect('hello')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'IOS_VERSION_TOO_LOW',
      });
    });

    it('wraps unrecognised native errors as INFERENCE_FAILED', async () => {
      mockedNative.detectText.mockRejectedValue(new Error('something unexpected'));
      await expect(Text.detect('hello')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'something unexpected',
      });
    });

    it('passes through an existing ContentSafetyError unchanged', async () => {
      const original = new ContentSafetyError('MODEL_LOAD_FAILED', 'disk full');
      mockedNative.detectText.mockRejectedValue(original);
      await expect(Text.detect('hello')).rejects.toBe(original);
    });
  });
});
