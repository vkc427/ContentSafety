package expo.modules.contentsafety

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoContentSafetyModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoContentSafety")

    AsyncFunction("setValueAsync") { value: String ->
    }
  }
}
