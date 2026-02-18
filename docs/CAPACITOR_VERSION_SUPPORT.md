# Capacitor Version Support

This plugin supports **Capacitor >= 7.0.0**, including Capacitor 8. The following analysis and changes were applied to support the latest Capacitor JS version.

## Architecture Analysis (ref-code/capacitor-mqtt-quic)

### TypeScript / Web layer (`src/`)

| File | Role | Capacitor API | Notes |
|------|------|---------------|--------|
| `index.ts` | Plugin registration | `registerPlugin<MqttQuicPlugin>('MqttQuic', { web: () => ... })` | Unchanged; API is stable in Cap 7 & 8. |
| `definitions.ts` | Plugin interface | TypeScript interfaces only | No runtime Capacitor dependency. |
| `web.ts` | Web/PWA implementation | None (uses `mqtt` npm package) | Fallback when not on native. |

**Conclusion:** No code changes required for Capacitor 8. `registerPlugin` and the web fallback pattern are compatible with both versions.

### Android (`android/`)

| Component | Role | Changes for Cap 8 |
|-----------|------|-------------------|
| `MqttQuicPlugin.kt` | Bridge: `@CapacitorPlugin`, `Plugin`, `PluginCall`, `@PluginMethod` | None; same APIs in Cap 7 & 8. |
| `build.gradle` | Build and Capacitor dependency | Updated (see below). |

**Build changes applied:**

- **Capacitor dependency:** Was `compileOnly 'com.getcapacitor:core:6.0.0'`. Now uses a variable so both Cap 7 and Cap 8 work:
  - Cap 8: `com.capacitorjs:core:8.0.0` (default).
  - Cap 7: app can set `capacitorCoreVersion` (e.g. `7.0.0`) and plugin uses `com.getcapacitor:core`.
- **Gradle:** AGP 8.13.0, Gradle property assignment uses `=` where required.
- **SDK:** `compileSdk`/`targetSdk` 36, `minSdkVersion` 24.
- **AndroidX:** Optional versions aligned with Capacitor 8 plugin guide (e.g. JUnit 1.3.0, Espresso 3.7.0).

### iOS (`ios/` and root `AnnadataCapacitorMqttQuic.podspec`)

| Component | Role | Changes for Cap 8 |
|-----------|------|-------------------|
| `MqttQuicPlugin.swift` | Bridge: `CAPPlugin`, `CAPPluginCall`, `CAPBridgedPlugin`, `@objc` methods | None; same APIs in Cap 7 & 8. |
| `AnnadataCapacitorMqttQuic.podspec` | CocoaPods spec | `s.ios.deployment_target = '15.0'` (was 14.0). |

**Conclusion:** Plugin Swift code is unchanged. Only deployment target was raised to match Capacitor 8 (iOS 15+).

## Summary of File Changes

1. **package.json**
   - `peerDependencies["@capacitor/core"]`: `"^7.0.0"` → `">=7.0.0"` (supports 7 and 8).
   - `devDependencies`: All `@capacitor/*` set to `^8.0.0` for development against latest.

2. **android/build.gradle**
   - Capacitor dependency: variable-based `compileOnly` (Cap 7: `com.getcapacitor`, Cap 8: `com.capacitorjs`).
   - `compileSdk`/`targetSdk` 36, `minSdkVersion` 24.
   - Gradle 8–style property assignments (`=`) where applicable.
   - AGP 8.13.0, optional AndroidX versions updated.

3. **AnnadataCapacitorMqttQuic.podspec**
   - `s.ios.deployment_target = '15.0'`.

## Consuming Apps

- **Capacitor 8:** Use as-is; plugin defaults to Cap 8 in Android build.
- **Capacitor 7:** Ensure app uses `@capacitor/core@^7.x`. For Android, the plugin will resolve `com.getcapacitor:core` when `capacitorCoreVersion` is set to a 7.x value in the app’s root project.

## References

- [Updating Capacitor to 8.0 in your plugin](https://capacitorjs.com/docs/updating/plugins/8-0)
- [Updating from Capacitor 7 to Capacitor 8](https://capacitorjs.com/docs/updating/8-0)
