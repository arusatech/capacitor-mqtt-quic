require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'AnnadataCapacitorMqttQuic'
  s.version = package['version']
  s.summary = 'MQTT-over-QUIC Capacitor plugin (iOS)'
  s.license = package['license']
  s.homepage = 'https://github.com/annadata/capacitor-mqtt-quic'
  s.author = 'Mr. Yakub Mohammad'
  s.authors = { 'Mr. Yakub Mohammad' => 'yakub@annadata.ai' }
  s.source = { :git => 'https://github.com/annadata/capacitor-mqtt-quic', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.resources = ['ios/Sources/MqttQuicPlugin/Resources/*.pem']
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
  s.vendored_libraries = [
    'ios/libs/libngtcp2.a',
    'ios/libs/libngtcp2_crypto_wolfssl.a',
    'ios/libs/libnghttp3.a',
    'ios/libs/libwolfssl.a'
  ]
  s.public_header_files = 'ios/Sources/**/*.h', 'ios/include/**/*.h'
  s.private_header_files = 'ios/Sources/**/*.h', 'ios/include/**/*.h'
  s.header_mappings_dir = 'ios/Sources'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/ios/include $(PODS_TARGET_SRCROOT)/ios/Sources/MqttQuicPlugin/QUIC',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/ios/libs',
    'OTHER_LDFLAGS' => '-lngtcp2 -lngtcp2_crypto_wolfssl -lnghttp3 -lwolfssl',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'NGTCP2_ENABLED NGHTTP3_ENABLED',
    'OTHER_CFLAGS' => '$(inherited) -fmodule-map-file=$(PODS_TARGET_SRCROOT)/ios/Sources/MqttQuicPlugin/QUIC/module.modulemap',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc -fmodule-map-file=$(PODS_TARGET_SRCROOT)/ios/Sources/MqttQuicPlugin/QUIC/module.modulemap'
  }
end
