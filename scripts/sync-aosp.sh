#!/bin/bash
set -euo pipefail

# Initialize and sync Android 15 AOSP source tree.
#
# This requires ~300GB of disk space and a fast internet connection.
# The initial sync downloads ~100GB of git data.

AOSP_DIR="${1:-aosp}"
BRANCH="${AOSP_BRANCH:-android-15.0.0_r1}"
JOBS="${SYNC_JOBS:-$(nproc)}"

if [ -d "$AOSP_DIR/.repo" ]; then
  echo "Repo already initialized in '$AOSP_DIR'. Running sync only."
  cd "$AOSP_DIR"
  repo sync -c -j"$JOBS" --no-tags --no-clone-bundle
  exit 0
fi

# Install repo tool if not present
if ! command -v repo &>/dev/null; then
  echo "Installing repo tool..."
  mkdir -p ~/.local/bin
  curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
  chmod a+x ~/.local/bin/repo
  export PATH="$HOME/.local/bin:$PATH"
  echo "Installed repo to ~/.local/bin/repo"
  echo "Add to your shell profile: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

mkdir -p "$AOSP_DIR"
cd "$AOSP_DIR"

echo "Initializing AOSP repo (branch: $BRANCH)..."
repo init -u https://android.googlesource.com/platform/manifest -b "$BRANCH"

echo "Syncing AOSP source (jobs: $JOBS)..."
repo sync -c -j"$JOBS" --no-tags --no-clone-bundle

echo ""
echo "AOSP source synced to: $(pwd)"
echo "Next steps:"
echo "  cd $(pwd)"
echo "  source build/envsetup.sh"
echo "  lunch sdk_car_x86_64-trunk_staging-userdebug"
