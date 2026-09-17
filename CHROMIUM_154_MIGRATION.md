# Kiwi features on Chromium 154

See `KIWI_FEATURE_PORT_STATUS.md` for the complete feature-by-feature migration status.

The new Android base is a clean Chromium `154.0.8037.21` checkout at commit
`0fa6d91e2faf313da8332688a96bd98b9d983a4d`. The legacy Chromium 105 tree is
kept separate and is not copied wholesale into the new source.

## Ported features

- History privacy lock uses Chromium 154's device reauthentication API. It accepts the device's
  configured fingerprint, face, PIN, pattern, or password and prevents screenshots while locked.
- The Kiwi full-screen video assistant is wired to the current fullscreen callbacks and the public
  MediaSession API.
- The adaptive toolbar remains clickable during its 225-300 ms icon/chip animation. Long-press is
  still disabled until the transition finishes.
- Translation uses Chromium 154's native `TranslateBridge.translateTabWhenReady()` and maintained
  always-translate preference pipeline. Kiwi 105's Google/Yandex/Baidu/Microsoft URL wrappers are
  intentionally not ported because they are not reliable automatic translation.

## Apply

Run `APPLY_CHROMIUM_154_FEATURES.cmd`. The patches are idempotent and verify the expected Chromium
revision before changing the clean source.

## Compile-check target

The Java integration can be checked incrementally with:

```bash
third_party/ninja/ninja -C out/KiwiReleaseNinja -j 3 chrome_java
```

This does not build, sign, install, or run an APK.

## Build APK with five jobs

Run `BUILD_CHROMIUM_154_J5.cmd`. It applies the feature patches, builds
`chrome_public_apk` with `-j5`, saves the complete log, and copies the resulting APK to
`release-apk/chromium154/Kiwi-Chromium154-arm64.apk`.
