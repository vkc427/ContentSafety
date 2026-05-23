import * as Image from './Image';
import * as Video from './Video';
import * as Text from './Text';
import ContentSafetyModule from './ContentSafetyModule';

export { Image, Video, Text };
export * from './types';

export function warmup(): Promise<void> {
  return ContentSafetyModule.warmup();
}
