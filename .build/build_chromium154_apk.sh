#!/usr/bin/env bash
set -euo pipefail

readonly CHROMIUM_ROOT="${CHROMIUM_ROOT:-/root/chromium154/src}"
readonly OVERLAY_ROOT="${OVERLAY_ROOT:-/mnt/c/Users/phuoc/Downloads/src.next}"
readonly OUT_DIR="out/KiwiReleaseNinja"
readonly GN_ARGS_SOURCE="${OVERLAY_ROOT}/.build/android_arm64_latest.args.gn"
readonly APK_TARGET="chrome_public_apk"
readonly JOBS="${JOBS:-5}"
readonly APK_OUTPUT_DIR="${OVERLAY_ROOT}/release-apk/chromium154"
readonly LOG_FILE="${APK_OUTPUT_DIR}/build.log"
readonly LINUX_LOG_FILE="${CHROMIUM_ROOT}/${OUT_DIR}/kiwi-build.log"

mkdir -p "${APK_OUTPUT_DIR}"

# Keep the live log in WSL's ext4 filesystem to reduce cross-filesystem writes;
# export it to the Windows project folder only when this run finishes.
export_build_log() {
  local build_exit=$?
  trap - EXIT
  if [[ -f "${LINUX_LOG_FILE}" ]]; then
    {
      echo
      echo "==== Build process finished at $(date --iso-8601=seconds) ===="
      echo "Exit code: ${build_exit}"
      if (( build_exit != 0 )); then
        echo "---- Memory ----"
        free -h || true
        echo "---- Filesystems ----"
        df -h / "${OVERLAY_ROOT}" || true
        echo "---- Recent kernel memory/storage errors ----"
        dmesg 2>/dev/null | grep -Ei 'out of memory|oom|killed process|I/O error|ext4.*error' | tail -n 30 || true
      fi
    } >>"${LINUX_LOG_FILE}"
    cp -f "${LINUX_LOG_FILE}" "${LOG_FILE}" || true
  fi
  exit "${build_exit}"
}
trap export_build_log EXIT

if [[ ! -d "${CHROMIUM_ROOT}/.git" ]]; then
  echo "Chromium 154 source was not found at ${CHROMIUM_ROOT}." >&2
  exit 1
fi
if [[ ! -f "${GN_ARGS_SOURCE}" ]]; then
  echo "GN args were not found at ${GN_ARGS_SOURCE}." >&2
  exit 1
fi

if pgrep -f "ninja -C ${OUT_DIR}" >/dev/null; then
  echo "Another build is already using ${OUT_DIR}. Wait for it to finish first." >&2
  exit 3
fi

echo "==== Applying Kiwi features to Chromium 154 ===="
env CHROMIUM_ROOT="${CHROMIUM_ROOT}" OVERLAY_ROOT="${OVERLAY_ROOT}" \
  bash "${OVERLAY_ROOT}/.build/apply_chromium154_patches.sh"

echo "==== Configuring Chromium 154 full Kiwi feature build ===="
mkdir -p "${CHROMIUM_ROOT}/${OUT_DIR}"
cd "${CHROMIUM_ROOT}"
if [[ ! -f "${OUT_DIR}/build.ninja" ]] || ! cmp -s "${GN_ARGS_SOURCE}" "${OUT_DIR}/args.gn"; then
  cp "${GN_ARGS_SOURCE}" "${OUT_DIR}/args.gn"
  buildtools/linux64/gn gen "${OUT_DIR}" 2>&1 | tee "${LINUX_LOG_FILE}"
else
  echo "Reusing existing build configuration; Ninja will regenerate it if source dependencies changed." | tee "${LINUX_LOG_FILE}"
fi

{
  echo "Build started: $(date --iso-8601=seconds)"
  echo "Jobs: ${JOBS}"
  echo "Target: ${APK_TARGET}"
} | tee -a "${LINUX_LOG_FILE}"

echo "==== Building Chromium 154 Android ARM64 APK with -j${JOBS} ===="
set +e
# Keep Ninja attached to the real build process. The previous pseudo-terminal
# wrapper could exit immediately and print NUL (^@) characters on Windows.
NINJA_STATUS='[%f/%t | %w] ' \
  third_party/ninja/ninja -C "${OUT_DIR}" -j "${JOBS}" "${APK_TARGET}" 2>&1 | tee -a "${LINUX_LOG_FILE}"
build_status=${PIPESTATUS[0]}
set -e

if (( build_status != 0 )); then
  echo "Build failed with exit code ${build_status}."
  echo "Log: ${LOG_FILE}"
  exit "${build_status}"
fi

apk_path="${CHROMIUM_ROOT}/${OUT_DIR}/apks/ChromePublic.apk"
if [[ ! -f "${apk_path}" ]]; then
  echo "Build completed but APK was not found at ${apk_path}." >&2
  exit 2
fi

cp -f "${apk_path}" "${APK_OUTPUT_DIR}/Kiwi-Chromium154-arm64.apk"

echo "==== Build completed ===="
echo "APK: ${APK_OUTPUT_DIR}/Kiwi-Chromium154-arm64.apk"
