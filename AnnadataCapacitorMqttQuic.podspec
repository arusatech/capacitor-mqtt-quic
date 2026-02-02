require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'AnnadataCapacitorMqttQuic'
  s.version = package['version']
  s.summary = 'MQTT-over-QUIC Capacitor plugin (iOS)'
  s.license = package['license']
  s.homepage = 'https://github.com/annadata/capacitor-mqtt-quic'
  s.author = 'Annadata'
  s.source = { :git => 'https://github.com/annadata/capacitor-mqtt-quic', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  # Exclude ngtcp2 native impl when using QuicClientStub. Remove when NGTCP2 bridge is fixed.
  s.exclude_files = 'ios/Sources/MqttQuicPlugin/QUIC/NGTCP2Client.swift', 'ios/Sources/MqttQuicPlugin/QUIC/NGTCP2Bridge.mm', 'ios/Sources/MqttQuicPlugin/QUIC/NGTCP2Bridge.h'
  s.resources = ['ios/Sources/MqttQuicPlugin/Resources/*.pem']
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
  s.vendored_libraries = [
    'ios/libs/libngtcp2.a',
    'ios/libs/libngtcp2_crypto_quictls.a',
    'ios/libs/libnghttp3.a',
    'ios/libs/libssl.a',
    'ios/libs/libcrypto.a'
  ]
  s.public_header_files = 'ios/Sources/**/*.h', 'ios/include/**/*.h'
  s.private_header_files = 'ios/Sources/**/*.h', 'ios/include/**/*.h'
  s.header_mappings_dir = 'ios/Sources'
  # Use QuicClientStub for now (in-memory mock). Enable NGTCP2_ENABLED + NGHTTP3_ENABLED
  # and add Swift-C bridge for NGTCP2Client when native QUIC is needed.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/AnnadataCapacitorMqttQuic/ios/include/ngtcp2 $(PODS_ROOT)/AnnadataCapacitorMqttQuic/ios/include/nghttp3 $(PODS_ROOT)/AnnadataCapacitorMqttQuic/ios/include/openssl',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/AnnadataCapacitorMqttQuic/ios/libs',
    'OTHER_LDFLAGS' => '-lngtcp2 -lngtcp2_crypto_quictls -lnghttp3 -lssl -lcrypto'
  }
end
