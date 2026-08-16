Pod::Spec.new do |spec|
  spec.name         = 'Zenmanage'
  spec.version      = '0.1.0'
  spec.summary      = 'Zenmanage feature flag SDK for iOS and Apple platform apps.'
  spec.description  = <<-DESC
Zenmanage is a native Swift SDK for iOS apps that fetches rules once,
evaluates feature flags locally, supports percentage rollouts, and persists
rules in UserDefaults by default.
  DESC
  spec.homepage     = 'https://github.com/zenmanage/zenmanage-swift'
  spec.license      = { :type => 'MIT', :file => 'LICENSE' }
  spec.author       = { 'Zenmanage' => 'opensource@zenmanage.com' }
  spec.source       = { :git => 'https://github.com/zenmanage/zenmanage-swift.git', :tag => spec.version.to_s }
  spec.swift_version = '5.9'

  spec.ios.deployment_target = '13.0'
  spec.osx.deployment_target = '10.15'
  spec.tvos.deployment_target = '13.0'
  spec.watchos.deployment_target = '6.0'

  spec.source_files = 'Sources/Zenmanage/**/*.swift'
  spec.requires_arc = true
end