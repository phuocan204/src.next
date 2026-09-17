#!/usr/bin/env bash
set -euo pipefail

readonly CHROMIUM_ROOT="${CHROMIUM_ROOT:-/root/chromium154/src}"
readonly OVERLAY_ROOT="${OVERLAY_ROOT:-/mnt/c/Users/phuoc/Downloads/src.next}"
readonly OUT_DIR="out/KiwiExtensionProbe"
readonly GN_ARGS_SOURCE="${OVERLAY_ROOT}/.build/android_arm64_extension_probe.args.gn"
readonly OUTPUT_DIR="${OVERLAY_ROOT}/release-apk/chromium154-extensions"
readonly LOG_FILE="${OUTPUT_DIR}/build.log"
readonly JOBS=5

mkdir -p "${OUTPUT_DIR}"

if [[ ! -d "${CHROMIUM_ROOT}/.git" ]]; then
  echo "Chromium 154 source was not found at ${CHROMIUM_ROOT}." >&2
  exit 1
fi
if [[ ! -f "${GN_ARGS_SOURCE}" ]]; then
  echo "Extension GN args were not found at ${GN_ARGS_SOURCE}." >&2
  exit 1
fi

if pgrep -f "ninja -C ${OUT_DIR}" >/dev/null; then
  echo "Another extension build is already using ${OUT_DIR}. Wait for it to finish first." >&2
  exit 3
fi

echo "==== Applying accepted Kiwi 154 feature patches ===="
env CHROMIUM_ROOT="${CHROMIUM_ROOT}" OVERLAY_ROOT="${OVERLAY_ROOT}" \
  "${OVERLAY_ROOT}/.build/apply_chromium154_patches.sh"

echo "==== Configuring Chromium 154 Desktop Android extensions ===="
mkdir -p "${CHROMIUM_ROOT}/${OUT_DIR}"
cp "${GN_ARGS_SOURCE}" "${CHROMIUM_ROOT}/${OUT_DIR}/args.gn"
cd "${CHROMIUM_ROOT}"
buildtools/linux64/gn gen "${OUT_DIR}" 2>&1 | tee "${LOG_FILE}"

echo "==== Building extension-enabled APK with -j${JOBS} ===="
set +e
third_party/ninja/ninja -C "${OUT_DIR}" -j "${JOBS}" chrome_public_apk 2>&1 | tee -a "${LOG_FILE}"
build_status=${PIPESTATUS[0]}
set -e

if (( build_status != 0 )); then
  echo "Build failed with exit code ${build_status}."
  echo "The completed Ninja outputs remain cached; run this file again after the error is fixed."
  echo "Log: ${LOG_FILE}"
  exit "${build_status}"
fi

apk_path="${CHROMIUM_ROOT}/${OUT_DIR}/apks/ChromePublic.apk"
if [[ ! -f "${apk_path}" ]]; then
  echo "Build completed but APK was not found at ${apk_path}." >&2
  exit 2
fi

cp -f "${apk_path}" "${OUTPUT_DIR}/Kiwi-Chromium154-Extensions-arm64.apk"
echo "==== Extension APK build completed ===="
echo "APK: ${OUTPUT_DIR}/Kiwi-Chromium154-Extensions-arm64.apk"
