#!/usr/bin/env bash
set -euo pipefail

readonly CHROMIUM_ROOT="${CHROMIUM_ROOT:-/root/chromium154/src}"
readonly OVERLAY_ROOT="${OVERLAY_ROOT:-/mnt/c/Users/phuoc/Downloads/src.next}"
readonly PATCH_ROOT="${OVERLAY_ROOT}/.build/patches/chromium154"
readonly EXPECTED_REVISION="0fa6d91e2faf313da8332688a96bd98b9d983a4d"
readonly VIDEO_SOURCE_RELATIVE="chrome/android/java/src/org/chromium/chrome/browser/media/VideoAssistantController.java"
readonly TRANSLATE_CONTROLLER_RELATIVE="chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/adaptive/TranslateToolbarButtonController.java"
readonly CHROME_JAVA_SOURCES="${CHROMIUM_ROOT}/chrome/android/chrome_java_sources.gni"

if [[ ! -d "${CHROMIUM_ROOT}/.git" ]]; then
  echo "Chromium source was not found at ${CHROMIUM_ROOT}." >&2
  exit 1
fi

actual_revision="$(git -C "${CHROMIUM_ROOT}" rev-parse HEAD)"
if [[ "${actual_revision}" != "${EXPECTED_REVISION}" ]]; then
  echo "Expected Chromium ${EXPECTED_REVISION}, found ${actual_revision}." >&2
  exit 1
fi

# Chromium 154 already contains a maintained adaptive-toolbar translate provider and the native
# always-translate pipeline. Refuse to fall back to Kiwi 105's external translate-page URLs: those
# URLs are brittle and were the cause of the old "automatic translate does nothing" behavior.
translate_controller="${CHROMIUM_ROOT}/${TRANSLATE_CONTROLLER_RELATIVE}"
if [[ ! -f "${translate_controller}" ]] \
    || ! grep -q 'TranslateBridge.translateTabWhenReady(tab)' "${translate_controller}"; then
  echo "Chromium's native toolbar translate controller was not found." >&2
  exit 1
fi

# Kiwi-owned privacy helper is introduced by patch 0004. Register it mechanically so this source
# list remains stable even when nearby Chromium entries are reordered.
if ! grep -q 'SensitiveActivityReauthenticator.java' "${CHROME_JAVA_SOURCES}"; then
  perl -0pi -e 's#(  "java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings\.java",\n)#$1  "java/src/org/chromium/chrome/browser/privacy/settings/SensitiveActivityReauthenticator.java",\n#' "${CHROME_JAVA_SOURCES}"
fi

# The video assistant is a Kiwi-owned source file. Copy it into the clean tree, then migrate its
# imports and method calls to Chromium 154's public MediaSession API.
cp "${OVERLAY_ROOT}/${VIDEO_SOURCE_RELATIVE}" "${CHROMIUM_ROOT}/${VIDEO_SOURCE_RELATIVE}"
perl -pi -e 's/import android\.os\.Handler;/import android.os.Handler;\nimport android.os.Looper;/' \
  "${CHROMIUM_ROOT}/${VIDEO_SOURCE_RELATIVE}"
perl -pi -e 's/import org\.chromium\.content\.browser\.MediaSessionImpl;/import org.chromium.content_public.browser.MediaSession;\nimport org.chromium.media_session.mojom.MediaSession.SuspendType;/' \
  "${CHROMIUM_ROOT}/${VIDEO_SOURCE_RELATIVE}"
perl -pi -e 's/MediaSessionImpl/MediaSession/g; s/new Handler\(\)/new Handler(Looper.getMainLooper())/g; s/session\.suspend\(\)/session.suspend(SuspendType.UI)/g; s/session\.resume\(\)/session.resume(SuspendType.UI)/g' \
  "${CHROMIUM_ROOT}/${VIDEO_SOURCE_RELATIVE}"

readonly TAB_DELEGATE="${CHROMIUM_ROOT}/chrome/android/java/src/org/chromium/chrome/browser/tab/TabWebContentsDelegateAndroidImpl.java"
if ! grep -q 'VideoAssistantController.showForTab(mTab)' "${TAB_DELEGATE}"; then
  perl -0pi -e 's/(mDelegate\.enterFullscreenModeForTab\(\n\s+renderFrameHost, prefersNavigationBar, prefersStatusBar, displayId\);)/$1\n        VideoAssistantController.showForTab(mTab);/' "${TAB_DELEGATE}"
fi
if ! grep -q 'VideoAssistantController.hideForTab(mTab)' "${TAB_DELEGATE}"; then
  perl -0pi -e 's/(public void exitFullscreenModeForTab\(\) \{\n)/$1        VideoAssistantController.hideForTab(mTab);\n/' "${TAB_DELEGATE}"
fi

shopt -s nullglob
patches=("${PATCH_ROOT}"/*.patch)
if (( ${#patches[@]} == 0 )); then
  echo "No Chromium 154 feature patches found in ${PATCH_ROOT}." >&2
  exit 1
fi

is_patch_applied() {
  case "$1" in
    0001-lock-history-with-device-auth.patch)
      grep -q 'DeviceAuthSource.HISTORY' \
        "${CHROMIUM_ROOT}/chrome/android/java/src/org/chromium/chrome/browser/history/HistoryActivity.java"
      ;;
    0002-wire-video-assistant.patch)
      grep -q 'VideoAssistantController.showForTab(mTab)' "${TAB_DELEGATE}"
      ;;
    0003-keep-adaptive-toolbar-clickable-during-animation.patch)
      grep -q 'Keep the click listener active while the optional button animates' \
        "${CHROMIUM_ROOT}/chrome/browser/ui/android/toolbar/java/src/org/chromium/chrome/browser/toolbar/optional_button/OptionalButtonView.java"
      ;;
    0004-expanded-privacy-lock.patch)
      grep -q 'privacy_lock_bookmarks' \
        "${CHROMIUM_ROOT}/chrome/android/java/res/xml/privacy_preferences.xml"
      ;;
    0005-site-adblock-menu.patch)
      grep -q 'R.id.adblock_id' \
        "${CHROMIUM_ROOT}/chrome/android/java/src/org/chromium/chrome/browser/app/ChromeActivity.java"
      ;;
    *)
      return 1
      ;;
  esac
}

for patch_file in "${patches[@]}"; do
  patch_name="$(basename "${patch_file}")"
  if is_patch_applied "${patch_name}"; then
    echo "Already applied: ${patch_name}"
    continue
  fi
  if git -C "${CHROMIUM_ROOT}" apply --check "${patch_file}" 2>/dev/null; then
    echo "Applying ${patch_name}"
    git -C "${CHROMIUM_ROOT}" apply "${patch_file}"
  elif git -C "${CHROMIUM_ROOT}" apply --reverse --check "${patch_file}" 2>/dev/null; then
    echo "Already applied: ${patch_name}"
  else
    echo "Patch does not apply cleanly: ${patch_file}" >&2
    exit 1
  fi
done

git -C "${CHROMIUM_ROOT}" diff --check
echo "Chromium 154 Kiwi feature patches are applied."
