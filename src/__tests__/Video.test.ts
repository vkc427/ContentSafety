import { Video } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';
import { ContentSafetyError } from '../types';

const mockedNative = ContentSafetyModule as unknown as {
  detectVideo: jest.Mock;
};

describe('Video.detect', () => {
  beforeEach(() => {
    mockedNative.detectVideo.mockReset();
    mockedNative.detectVideo.mockResolvedValue({
      isNSFW: false,
      confidence: 0.05,
      threshold: 0.7,
      source: 'tflite-image',
      durationMs: 240,
      framesAnalyzed: 4,
    });
  });

  it('applies all default options when none provided', async () => {
    await Video.detect('file:///tmp/clip.mp4');
    expect(mockedNative.detectVideo).toHaveBeenCalledWith(
      'file:///tmp/clip.mp4',
      {
        threshold: 0.7,
        sampleRate: 1,
        maxFrames: 30,
        stopOnFirstHit: true,
      },
    );
  });

  it('passes caller-supplied options through', async () => {
    await Video.detect('file:///tmp/clip.mp4', {
      threshold: 0.8,
      sampleRate: 3,
      maxFrames: 60,
      stopOnFirstHit: false,
    });
    expect(mockedNative.detectVideo).toHaveBeenCalledWith(
      'file:///tmp/clip.mp4',
      {
        threshold: 0.8,
        sampleRate: 3,
        maxFrames: 60,
        stopOnFirstHit: false,
      },
    );
  });

  it('rejects sampleRate <= 0', async () => {
    await expect(
      Video.detect('file:///tmp/clip.mp4', { sampleRate: 0 }),
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });

  it('rejects maxFrames < 1', async () => {
    await expect(
      Video.detect('file:///tmp/clip.mp4', { maxFrames: 0 }),
    ).rejects.toMatchObject({ code: 'INVALID_INPUT' });
  });

  it('rejects empty uris', async () => {
    await expect(Video.detect('')).rejects.toMatchObject({
      code: 'INVALID_INPUT',
    });
  });

  describe('native error remapping', () => {
    it('remaps INFERENCE_FAILED prefix to ContentSafetyError', async () => {
      mockedNative.detectVideo.mockRejectedValue(
        new Error('INFERENCE_FAILED: frame decode error')
      );
      await expect(Video.detect('file:///tmp/clip.mp4')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'frame decode error',
      });
    });

    it('remaps IOS_VERSION_TOO_LOW prefix to ContentSafetyError', async () => {
      mockedNative.detectVideo.mockRejectedValue(
        new Error('IOS_VERSION_TOO_LOW: iOS 17.0+ is required for image analysis')
      );
      await expect(Video.detect('file:///tmp/clip.mp4')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'IOS_VERSION_TOO_LOW',
      });
    });

    it('wraps unrecognised native errors as INFERENCE_FAILED', async () => {
      mockedNative.detectVideo.mockRejectedValue(new Error('something unexpected'));
      await expect(Video.detect('file:///tmp/clip.mp4')).rejects.toMatchObject({
        name: 'ContentSafetyError',
        code: 'INFERENCE_FAILED',
        message: 'something unexpected',
      });
    });

    it('passes through an existing ContentSafetyError unchanged', async () => {
      const original = new ContentSafetyError('MODEL_LOAD_FAILED', 'disk full');
      mockedNative.detectVideo.mockRejectedValue(original);
      await expect(Video.detect('file:///tmp/clip.mp4')).rejects.toBe(original);
    });
  });
});
