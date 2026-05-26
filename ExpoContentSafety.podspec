Pod::Spec.new do |s|
  s.name           = 'ExpoContentSafety'
  s.version        = '1.0.1'
  s.summary        = 'On-device NSFW detection for images, videos, and text'
  s.description    = 'Detects NSFW content entirely on-device. No content leaves the device.'
  s.author         = 'kvadlamudi'
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = { :ios => '17.0' }
  s.source         = { git: '' }
  s.license        = { type: 'MIT' }
  s.swift_version  = '5.9'
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.frameworks = 'SensitiveContentAnalysis', 'NaturalLanguage', 'CoreML', 'Security'
  s.resources  = 'ios/Resources/**'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  # ios/ contains the Swift sources; Tests/ is picked up by test_spec below
  s.source_files = "ios/*.{h,m,mm,swift,hpp,cpp}"

  s.test_spec 'Tests' do |test_spec|
    test_spec.platforms    = { :ios => '17.0' }
    test_spec.source_files = 'ios/Tests/**/*.swift'
    test_spec.resources    = 'ios/Tests/Resources/**/*.mlmodelc'
  end
end
