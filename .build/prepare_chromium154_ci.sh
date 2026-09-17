#!/usr/bin/env bash
set -Eeuo pipefail

: "${CHROMIUM_ROOT:?CHROMIUM_ROOT must point to the Chromium src directory}"
: "${DEPOT_TOOLS:?DEPOT_TOOLS must point to depot_tools}"
: "${CHROMIUM_REVISION:?CHROMIUM_REVISION is required}"

build_root="$(dirname "${CHROMIUM_ROOT}")"
mkdir -p "${build_root}" "$(dirname "${DEPOT_TOOLS}")"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl git git-lfs lsb-release ninja-build python3 rsync

if [[ ! -d "${DEPOT_TOOLS}/.git" ]]; then
  git clone --depth=1 \
    https://chromium.googlesource.com/chromium/tools/depot_tools.git \
    "${DEPOT_TOOLS}"
else
  git -C "${DEPOT_TOOLS}" pull --ff-only
fi
export PATH="${DEPOT_TOOLS}:${PATH}"

if [[ ! -d "${CHROMIUM_ROOT}/.git" ]]; then
  mkdir -p "${CHROMIUM_ROOT}"
  git -C "${CHROMIUM_ROOT}" init
  git -C "${CHROMIUM_ROOT}" remote add origin \
    https://chromium.googlesource.com/chromium/src.git
fi

git -C "${CHROMIUM_ROOT}" fetch --depth=1 --filter=blob:none origin \
  "${CHROMIUM_REVISION}"
git -C "${CHROMIUM_ROOT}" reset --hard
git -C "${CHROMIUM_ROOT}" clean -ffd
git -C "${CHROMIUM_ROOT}" checkout --force --detach FETCH_HEAD

cat >"${build_root}/.gclient" <<EOF
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["android"]
EOF

(
  cd "${build_root}"
  gclient sync --no-history --nohooks --delete_unversioned_trees \
    --revision "src@${CHROMIUM_REVISION}"
)

cd "${CHROMIUM_ROOT}"
sudo ./build/install-build-deps.sh --android --no-prompt
gclient runhooks

actual_revision="$(git rev-parse HEAD)"
if [[ "${actual_revision}" != "${CHROMIUM_REVISION}" ]]; then
  echo "Expected ${CHROMIUM_REVISION}, found ${actual_revision}." >&2
  exit 1
fi
