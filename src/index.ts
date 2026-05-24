import * as Image from './Image';
import * as Video from './Video';
import * as Text from './Text';
import ContentSafetyModule from './ContentSafetyModule';
import type { WarmupOptions } from './types';

export { Image, Video, Text };
export * from './types';

export function warmup(options?: WarmupOptions): Promise<void> {
  return ContentSafetyModule.warmup(options ?? {});
}
