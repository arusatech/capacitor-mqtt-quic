require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name = 'MqttQuicPlugin'
  s.version = package['version']
  s.summary = 'MQTT-over-QUIC Capacitor plugin (iOS)'
  s.license = package['license']
  s.homepage = 'https://github.com/annadata/capacitor-mqtt-quic'
  s.author = 'Annadata'
  s.source = { :git => 'https://github.com/annadata/capacitor-mqtt-quic', :tag => s.version.to_s }
  s.source_files = 'Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.resources = ['Sources/MqttQuicPlugin/Resources/*.pem']
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
  s.vendored_libraries = [
    'libs/libngtcp2.a',
    'libs/libngtcp2_crypto_quictls.a',
    'libs/libnghttp3.a',
    'libs/libssl.a',
    'libs/libcrypto.a'
  ]
  s.public_header_files = 'Sources/**/*.h', 'include/**/*.h'
  s.private_header_files = 'Sources/**/*.h', 'include/**/*.h'
  s.header_mappings_dir = 'Sources'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/include/ngtcp2 $(PODS_ROOT)/MqttQuicPlugin/include/nghttp3 $(PODS_ROOT)/MqttQuicPlugin/include/openssl',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/libs',
    'OTHER_LDFLAGS' => '-lngtcp2 -lngtcp2_crypto_quictls -lnghttp3 -lssl -lcrypto',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'NGTCP2_ENABLED NGHTTP3_ENABLED'
  }
end
