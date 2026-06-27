Pod::Spec.new do |s|
  s.name             = 'app_group_directory'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin to access shared app group on iOS'
  s.description      = 'Flutter plugin to access shared app group on iOS'
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Healthy-T' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.ios.deployment_target = '11.0'
end
