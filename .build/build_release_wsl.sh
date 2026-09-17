#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="${1:?Pass the project root as the first argument}"
BUILD_ROOT="/root/chromium"
SRC_ROOT="$BUILD_ROOT/src"
DEPOT_TOOLS="/root/depot_tools"
CHROMIUM_TAG="105.0.5195.24"
CHROMIUM_COMMIT="64038a114b86434efcce9c36697be10e333f911a"
OUT_DIR="$SRC_ROOT/out/KiwiRelease"
RESULT_DIR="$PROJECT_ROOT/release-apk"
LOG_FILE="$RESULT_DIR/build.log"
DEPS_READY_MARKER="$BUILD_ROOT/.kiwi_android_deps_ready"
RUN_HOOKS=0

mkdir -p "$RESULT_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

stage() {
  printf '\n==== %s ====\n' "$1"
}

stage "Checking disk space"
AVAILABLE_GB=$(df --output=avail -BG /mnt/c | tail -n 1 | tr -dc '0-9')
printf 'Free space on C: %s GB\n' "$AVAILABLE_GB"
if (( AVAILABLE_GB < 35 )); then
  printf 'At least 35 GB free on C: is required to continue. Free more space and run BUILD_RELEASE.cmd again.\n' >&2
  exit 2
fi
if (( AVAILABLE_GB < 90 )); then
  printf 'Warning: less than 90 GB is free. A first build may run out of space; interrupted builds can be resumed.\n'
fi

MEMORY_GB=$(awk '/MemTotal/ { print int($2 / 1024 / 1024) }' /proc/meminfo)
if (( MEMORY_GB < 6 )); then
  stage "Preparing build swap"
  if [[ ! -f /swapfile ]]; then
    fallocate -l 8G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  if ! swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
    swapon /swapfile
  fi
  free -h
fi

stage "Installing Linux build prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  ca-certificates curl git rsync python3 python3-venv \
  build-essential ninja-build gperf pkg-config openjdk-17-jdk-headless lsb-release

stage "Preparing depot_tools"
if [[ ! -d "$DEPOT_TOOLS/.git" ]]; then
  git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
else
  git -C "$DEPOT_TOOLS" pull --ff-only
fi
export PATH="$DEPOT_TOOLS:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
"$DEPOT_TOOLS/ensure_bootstrap"

stage "Preparing Chromium $CHROMIUM_TAG"
mkdir -p "$BUILD_ROOT"
if [[ ! -d "$SRC_ROOT/.git" ]]; then
  git clone --depth=1 --branch "$CHROMIUM_TAG" \
    https://chromium.googlesource.com/chromium/src.git "$SRC_ROOT"
fi

ACTUAL_COMMIT=$(git -C "$SRC_ROOT" rev-parse HEAD)
if [[ "$ACTUAL_COMMIT" != "$CHROMIUM_COMMIT" ]]; then
  printf 'Unexpected Chromium checkout at %s. Expected %s.\n' "$ACTUAL_COMMIT" "$CHROMIUM_COMMIT" >&2
  printf 'Move /root/chromium aside and run the script again.\n' >&2
  exit 3
fi

cd "$BUILD_ROOT"
# Chromium 105 references a retired Linux traffic-annotation binary. It is a
# desktop validation tool and is not used by an Android APK build, so the
# checked-in gclient template disables only that download hook.
if [[ ! -f "$BUILD_ROOT/.gclient" ]] ||
    ! cmp -s "$PROJECT_ROOT/.build/chromium105.gclient" "$BUILD_ROOT/.gclient"; then
  cp "$PROJECT_ROOT/.build/chromium105.gclient" "$BUILD_ROOT/.gclient"
fi
if [[ -f "$DEPS_READY_MARKER" ]]; then
  printf 'Android dependencies were already synchronized; reusing them.\n'
elif ! git -C "$SRC_ROOT" diff --quiet; then
  # The overlay is only applied after a successful sync and hook run. This
  # handles builds made with an older version of this helper, before the marker
  # file was introduced.
  printf 'Existing Kiwi overlay detected; reusing the previously synchronized dependencies.\n'
  touch "$DEPS_READY_MARKER"
else
  gclient sync --no-history --nohooks --revision "src@$CHROMIUM_COMMIT"
  RUN_HOOKS=1
fi

stage "Installing Chromium Android dependencies"
cd "$SRC_ROOT"
if ! ./build/install-build-deps-android.sh --unsupported; then
  printf 'The Chromium 105 dependency helper does not fully recognize this newer Ubuntu release.\n'
  printf 'Installing the compatible Android host packages available on this system and continuing.\n'
  dpkg --add-architecture i386
  apt-get update
  apt-get install -y \
    lib32z1 lighttpd xvfb x11-utils libncurses6:i386 libstdc++6:i386 zlib1g:i386
fi
if (( RUN_HOOKS )); then
  gclient runhooks
  touch "$DEPS_READY_MARKER"
else
  printf 'Chromium hooks were already completed; skipping repeated downloads.\n'
fi

stage "Applying the Kiwi source overlay"
rsync -a --checksum --no-times \
  --exclude='.git/' \
  --exclude='.build/' \
  --exclude='release-apk/' \
  --exclude='out/' \
  "$PROJECT_ROOT/" "$SRC_ROOT/"

# Chromium 105 owns accessibility_preferences.xml in the accessibility
# component. Kiwi's customized copy is overlaid there above; remove the legacy
# Chrome-app copy so aapt2 sees exactly one resource with this name.
rm -f "$SRC_ROOT/chrome/android/java/res/xml/accessibility_preferences.xml"

# This archived Kiwi overlay lists a legacy settings-icon pack that is not
# present in the repository. Keeping those entries makes Ninja fail before any
# compilation starts. Remove only that clearly delimited, absent resource list
# from the disposable WSL checkout.
if grep -q '^# Settings icons' "$SRC_ROOT/chrome/android/chrome_java_resources.gni"; then
  sed -i '/^# Settings icons\r*$/,/^]\r*$/ { /^# Settings icons\r*$/d; /^]\r*$/!d; }' \
    "$SRC_ROOT/chrome/android/chrome_java_resources.gni"
fi

# Python removed universal-newline mode "U". Chromium 105's GRIT still asks
# for "rU" even though plain "r" has identical newline behavior on Python 3.
if grep -q "mode = 'rU'" "$SRC_ROOT/tools/grit/grit/util.py"; then
  sed -i "s/mode = 'rU'/mode = 'r'/" "$SRC_ROOT/tools/grit/grit/util.py"
fi

# Python 3.13 removed the deprecated 'pipes' module. Replace with shlex.
for PYTHON_FILE in \
  "$SRC_ROOT/build/android/gyp/util/build_utils.py" \
  "$SRC_ROOT/build/android/apk_operations.py" \
  "$SRC_ROOT/build/print_python_deps.py"; do
  if grep -q '^import pipes' "$PYTHON_FILE"; then
    sed -i 's/^import pipes/import shlex as pipes/' "$PYTHON_FILE"
  fi
done

# Git on Windows may materialize this strict generator input with CRLF. The
# Chromium generator intentionally rejects anything except Unix LF endings.
if grep -q $'\r$' "$SRC_ROOT/net/http/transport_security_state_static.pins"; then
  sed -i 's/\r$//' "$SRC_ROOT/net/http/transport_security_state_static.pins"
fi

# AIDL's preprocessed-file parser also rejects CRLF. Normalize all Android
# interface definitions after copying the Windows overlay.
while IFS= read -r -d '' AIDL_FILE; do
  if grep -q $'\r$' "$AIDL_FILE"; then
    sed -i 's/\r$//' "$AIDL_FILE"
  fi
done < <(find "$SRC_ROOT" -type f -name '*.aidl' -print0)

# gperf 3.3 emits C++ fallthrough attributes in positions rejected by the
# older Chromium 105 Clang. Convert them to the comment form Clang accepts.
GPERF_WRAPPER="$SRC_ROOT/third_party/blink/renderer/build/scripts/gperf.py"
if ! grep -q "gperf 3.3 compatibility" "$GPERF_WRAPPER"; then
  sed -i "/        # -Wpointer-to-int-cast/i\\        # gperf 3.3 compatibility\\n        gperf_output = gperf_output.replace('[[fallthrough]];', '\/\* FALLTHROUGH \*\/')" \
    "$GPERF_WRAPPER"
fi

# Kiwi's layout-level ad filtering calls AllowAds(), while the Chromium 105
# interface no longer declares that legacy hook. Restore its default behavior
# so Kiwi embedders can override it and ordinary clients remain permissive.
CONTENT_SETTINGS_CLIENT="$SRC_ROOT/third_party/blink/public/platform/web_content_settings_client.h"
if ! grep -q "AllowAds(bool" "$CONTENT_SETTINGS_CLIENT"; then
  sed -i "/  virtual bool AllowPopupsAndRedirects/i\\  virtual bool AllowAds(bool default_value) { return default_value; }\\n" \
    "$CONTENT_SETTINGS_CLIENT"
fi

# The archived Kiwi painter used a removed BorderPaintAutoDarkMode overload.
# Chromium 105 represents table borders as background-role paint instead.
TABLE_PAINTERS="$SRC_ROOT/third_party/blink/renderer/core/paint/ng/ng_table_painters.cc"
if grep -q 'BorderPaintAutoDarkMode(fragment_\.Style(), edge\.BorderColor())' "$TABLE_PAINTERS"; then
  sed -i 's/BorderPaintAutoDarkMode(fragment_\.Style(), edge\.BorderColor())/PaintAutoDarkMode(fragment_.Style(), DarkModeFilter::ElementRole::kBackground)/' \
    "$TABLE_PAINTERS"
fi

# resource_id.h includes this generated password-manager header. The Android
# Safe Browsing source set uses resource_id.h but Chromium 105 omits the direct
# generator dependency, which can leave the header absent in clean builds.
SAFE_BROWSING_BUILD="$SRC_ROOT/chrome/browser/safe_browsing/BUILD.gn"
if ! grep -q 'password_manager:password_manager_buildflags' "$SAFE_BROWSING_BUILD"; then
  sed -i '/"tailored_security\/consented_message_android.cc"/,/^      }/ {
    /"\/\/chrome\/app\/vector_icons:vector_icons",/a\          "//chrome/browser/password_manager:password_manager_buildflags",
  }' "$SAFE_BROWSING_BUILD"
fi

stage "Generating the ARM64 release build"
mkdir -p "$OUT_DIR"
ARGS_CHANGED=0
if [[ ! -f "$OUT_DIR/args.gn" ]] ||
    ! cmp -s "$PROJECT_ROOT/.build/android_arm64_release.args.gn" "$OUT_DIR/args.gn"; then
  cp "$PROJECT_ROOT/.build/android_arm64_release.args.gn" "$OUT_DIR/args.gn"
  ARGS_CHANGED=1
fi

if [[ ! -f "$OUT_DIR/build.ninja" ]] || (( ARGS_CHANGED )); then
  gn gen "$OUT_DIR"
else
  printf 'GN arguments unchanged; reusing the existing Ninja graph.\n'
fi

stage "Compiling chrome_public_apk"
# Use as much CPU as this low-memory WSL instance can safely sustain. A fresh
# run starts at five jobs; if swap is already busy, reduce concurrency instead
# of making the WSL service unresponsive.
CPU_COUNT=$(nproc)
SWAP_USED_MB=$(free -m | awk '/^Swap:/ { print $3 }')
BUILD_JOBS=5
if (( SWAP_USED_MB >= 6144 )); then
  BUILD_JOBS=2
elif (( SWAP_USED_MB >= 3072 )); then
  BUILD_JOBS=3
fi
if (( CPU_COUNT < BUILD_JOBS )); then
  BUILD_JOBS=$CPU_COUNT
fi
printf 'Ninja concurrency: %s jobs (%s CPUs, %s MB swap currently used).\n' \
  "$BUILD_JOBS" "$CPU_COUNT" "$SWAP_USED_MB"
autoninja -C "$OUT_DIR" -j "$BUILD_JOBS" chrome_public_apk

BUILT_APK="$OUT_DIR/apks/ChromePublic.apk"
if [[ ! -f "$BUILT_APK" ]]; then
  BUILT_APK=$(find "$OUT_DIR" -type f -path '*/apks/*.apk' -name '*Public*.apk' | head -n 1)
fi
if [[ -z "${BUILT_APK:-}" || ! -f "$BUILT_APK" ]]; then
  printf 'Compilation completed but no Chrome public APK was found.\n' >&2
  exit 4
fi

stage "Signing the release APK"
KEYSTORE="$RESULT_DIR/kiwi-release.keystore"
PASSWORD_FILE="$RESULT_DIR/.keystore-password.txt"
KEY_ALIAS="kiwi-release"

if [[ ! -f "$KEYSTORE" ]]; then
  if [[ ! -f "$PASSWORD_FILE" ]]; then
    openssl rand -hex 24 > "$PASSWORD_FILE"
  fi
  KEYSTORE_PASSWORD=$(tr -d '\r\n' < "$PASSWORD_FILE")
  keytool -genkeypair -noprompt \
    -keystore "$KEYSTORE" \
    -storepass "$KEYSTORE_PASSWORD" \
    -keypass "$KEYSTORE_PASSWORD" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -dname 'CN=Kiwi Browser Local Release, OU=Android, O=Local Build, L=Local, C=VN'
elif [[ ! -f "$PASSWORD_FILE" ]]; then
  printf 'The keystore exists but %s is missing. Restore that password file before rebuilding.\n' "$PASSWORD_FILE" >&2
  exit 5
fi

KEYSTORE_PASSWORD=$(tr -d '\r\n' < "$PASSWORD_FILE")
export KIWI_RELEASE_STORE_PASSWORD="$KEYSTORE_PASSWORD"
export KIWI_RELEASE_KEY_PASSWORD="$KEYSTORE_PASSWORD"
APKSIGNER=$(find "$SRC_ROOT/third_party/android_sdk" -type f -name apksigner | sort -V | tail -n 1)
ZIPALIGN=$(find "$SRC_ROOT/third_party/android_sdk" -type f -name zipalign | sort -V | tail -n 1)
if [[ -z "$APKSIGNER" || -z "$ZIPALIGN" ]]; then
  printf 'Could not locate apksigner/zipalign in the Chromium Android SDK.\n' >&2
  exit 6
fi

ALIGNED_APK="$RESULT_DIR/.KiwiBrowser-arm64-release-aligned.apk"
SIGNED_APK="$RESULT_DIR/.KiwiBrowser-arm64-release-signed.apk"
FINAL_APK="$RESULT_DIR/KiwiBrowser-arm64-release.apk"
# Chromium 105 stores crazy.libchrome.so uncompressed and loads it directly
# from the APK.  Plain 4-byte alignment is not enough for mmap/dlopen: native
# libraries must be page-aligned as well.  Without -p Android reports the
# library as "not found" even though the ZIP entry is present.
"$ZIPALIGN" -p -f 4 "$BUILT_APK" "$ALIGNED_APK"
"$ZIPALIGN" -p -c 4 "$ALIGNED_APK"
rm -f "$SIGNED_APK"
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KIWI_RELEASE_STORE_PASSWORD \
  --key-pass env:KIWI_RELEASE_KEY_PASSWORD \
  --out "$SIGNED_APK" "$ALIGNED_APK"
"$APKSIGNER" verify --verbose "$SIGNED_APK"
"$ZIPALIGN" -p -c 4 "$SIGNED_APK"
mv -f "$SIGNED_APK" "$FINAL_APK"
"$ZIPALIGN" -p -c 4 "$FINAL_APK"
unset KIWI_RELEASE_STORE_PASSWORD KIWI_RELEASE_KEY_PASSWORD
rm -f "$ALIGNED_APK" "$SIGNED_APK"

stage "Build complete"
ls -lh "$FINAL_APK"
printf 'APK: %s\n' "$FINAL_APK"
printf 'Keep kiwi-release.keystore and .keystore-password.txt safe; future updates must use the same key.\n'
