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

  describe('native error remapping', () => {
    it('remaps INFERENCE_FAILED prefix to ContentSafetyError', async () => {
      mockedNative.detectImage.mockRejectedValue(
        new Error('INFERENCE_FAILED: model returned unexpected output')
      );
      await expect(Image.detect('file:///tmp/x.jpg')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'model returned unexpected output',
      });
    });

    it('remaps IOS_VERSION_TOO_LOW prefix to ContentSafetyError', async () => {
      mockedNative.detectImage.mockRejectedValue(
        new Error('IOS_VERSION_TOO_LOW: iOS 17.0+ is required for image analysis')
      );
      await expect(Image.detect('file:///tmp/x.jpg')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'IOS_VERSION_TOO_LOW',
      });
    });

    it('remaps INVALID_INPUT prefix from native layer to ContentSafetyError', async () => {
      mockedNative.detectImage.mockRejectedValue(
        new Error('INVALID_INPUT: uri must be a file:// URL, got: https://example.com')
      );
      await expect(Image.detect('file:///tmp/x.jpg')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INVALID_INPUT',
      });
    });

    it('wraps unrecognised native errors as INFERENCE_FAILED', async () => {
      mockedNative.detectImage.mockRejectedValue(new Error('something unexpected'));
      await expect(Image.detect('file:///tmp/x.jpg')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'something unexpected',
      });
    });

    it('passes through an existing ContentSafetyError unchanged', async () => {
      const original = new ContentSafetyError('MODEL_LOAD_FAILED', 'disk full');
      mockedNative.detectImage.mockRejectedValue(original);
      await expect(Image.detect('file:///tmp/x.jpg')).rejects.toBe(original);
    });
  });
});
