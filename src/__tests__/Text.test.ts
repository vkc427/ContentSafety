import { Text } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';

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
});
