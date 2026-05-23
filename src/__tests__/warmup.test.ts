import { warmup } from '../index';
import ContentSafetyModule from '../ContentSafetyModule';

const mockedNative = ContentSafetyModule as unknown as {
  warmup: jest.Mock;
};

describe('warmup', () => {
  it('calls the native warmup', async () => {
    mockedNative.warmup.mockResolvedValue(undefined);
    await warmup();
    expect(mockedNative.warmup).toHaveBeenCalledTimes(1);
  });
});
