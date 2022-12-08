

Pod::Spec.new do |s|
  s.name             = 'LLNetworkAccessibility-OC'
  s.version          = '1.0.0'
  s.summary          = 'network authorization'
  s.description      = 'network authorization'

  s.homepage         = 'https://github.com/lanlinxl/LLNetworkAccessibility-OC'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'lanlinxl' => 'lanlin0806@icloud.com' }
  s.source           = { :git => 'https://github.com/lanlinxl/LLNetworkAccessibility-OC.git', :tag => s.version.to_s }

  s.ios.deployment_target = '11.0'

  s.source_files = 'LLNetworkAccessibility-OC/Classes/**/*'
  s.resource = 'LLNetworkAccessibility-OC/LLNetworkAccessibility.bundle'



end
