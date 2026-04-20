Pod::Spec.new do |s|
  s.name             = 'NetworkMetricsSDK'
  s.version          = '1.0.22'
  s.summary          = 'iOS network metrics measurement SDK'
  s.homepage         = 'https://github.com/kevindupas/ios-network-metrics-sdk'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Kevin Dupas' => 'dupas.dev@gmail.com' }
  s.source           = { :git => 'https://github.com/kevindupas/ios-network-metrics-sdk.git', :tag => "v#{s.version}" }
  s.source_files     = 'Sources/NetworkMetricsSDK/**/*.swift'
  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.7'
end
