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
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
