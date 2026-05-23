import ExpoModulesCore

public class ExpoContentSafetyModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoContentSafety")

    AsyncFunction("setValueAsync") { (value: String) in
    }
  }
}
