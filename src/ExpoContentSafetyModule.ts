import { NativeModule, requireNativeModule } from 'expo';

declare class ExpoContentSafetyModule extends NativeModule<{}> {
  setValueAsync(value: string): Promise<void>;
}

export default requireNativeModule<ExpoContentSafetyModule>('ExpoContentSafety');
