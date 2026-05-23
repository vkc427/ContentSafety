import { requireNativeModule } from 'expo-modules-core';
import type {
  DetectionResult,
  DetectOptions,
  VideoDetectOptions,
  TextDetectOptions,
} from './types';

interface ContentSafetyNativeModule {
  detectImage(uri: string, options: Required<DetectOptions>): Promise<DetectionResult>;
  detectVideo(uri: string, options: Required<VideoDetectOptions>): Promise<DetectionResult>;
  detectText(input: string, options: Required<TextDetectOptions>): Promise<DetectionResult>;
  warmup(): Promise<void>;
}

const ContentSafetyModule =
  requireNativeModule<ContentSafetyNativeModule>('ContentSafety');

export default ContentSafetyModule;
