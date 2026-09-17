#!/usr/bin/env bash
set -euo pipefail

SRC=/root/chromium/src/out/KiwiRelease/apks/ChromePublic.apk
OUT=/mnt/c/Users/phuoc/Downloads/src.next/release-apk
ALIGNED="$OUT/.KiwiBrowser-arm64-release-aligned.apk"
FINAL="$OUT/KiwiBrowser-arm64-release.apk"
SIGNED="$OUT/.KiwiBrowser-arm64-release-signed.apk"
ZIPALIGN=/root/chromium/src/third_party/android_sdk/public/build-tools/31.0.0/zipalign
APKSIGNER=/root/chromium/src/third_party/android_sdk/public/build-tools/31.0.0/apksigner

if [[ ! -f "$SRC" ]]; then
  printf 'Built APK not found: %s\n' "$SRC" >&2
  exit 1
fi

PASSWORD=$(tr -d '\r\n' < "$OUT/.keystore-password.txt")
export KIWI_RELEASE_STORE_PASSWORD="$PASSWORD"
export KIWI_RELEASE_KEY_PASSWORD="$PASSWORD"

"$ZIPALIGN" -p -f 4 "$SRC" "$ALIGNED"
"$ZIPALIGN" -p -c 4 "$ALIGNED"
rm -f "$SIGNED"
"$APKSIGNER" sign \
  --ks "$OUT/kiwi-release.keystore" \
  --ks-key-alias kiwi-release \
  --ks-pass env:KIWI_RELEASE_STORE_PASSWORD \
  --key-pass env:KIWI_RELEASE_KEY_PASSWORD \
  --out "$SIGNED" "$ALIGNED"
"$APKSIGNER" verify --verbose "$SIGNED"
"$ZIPALIGN" -p -c 4 "$SIGNED"
mv -f "$SIGNED" "$FINAL"

unset KIWI_RELEASE_STORE_PASSWORD KIWI_RELEASE_KEY_PASSWORD PASSWORD
rm -f "$ALIGNED" "$SIGNED"
ls -lh "$FINAL"
