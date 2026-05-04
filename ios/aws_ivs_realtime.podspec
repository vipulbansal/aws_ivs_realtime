#
# Run `pod lib lint aws_ivs_realtime.podspec` from ios/ before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'aws_ivs_realtime'
  s.version          = '0.1.0'
  s.summary          = 'Amazon IVS Real-Time (Stages) for Flutter.'
  s.description      = <<-DESC
Native IVS Real-Time stage (Android + iOS) with optional Dart helpers for
participant tokens, stages, and IVS Chat (SigV4 or your backend).
                       DESC
  s.homepage         = 'https://github.com/vipulbansal/aws_ivs_realtime'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AWS IVS Realtime Flutter' => 'https://pub.dev/packages/aws_ivs_realtime' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'AmazonIVSBroadcast/Stages', '~> 1.36.0'
  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
