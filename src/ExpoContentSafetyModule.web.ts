import { registerWebModule, NativeModule } from 'expo';

// ExpoContentSafetyModule is not available on the web platform.
class ExpoContentSafetyModule extends NativeModule<{}> {}

export default registerWebModule(ExpoContentSafetyModule, 'ExpoContentSafetyModule');
