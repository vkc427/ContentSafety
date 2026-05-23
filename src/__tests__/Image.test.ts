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
