#!/bin/bash
set -euo pipefail

# Start AAOS build with RBE enabled.
# Run this script from your AOSP source root, or set AOSP_ROOT.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
AOSP_ROOT="${AOSP_ROOT:-.}"

if [ ! -f "$AOSP_ROOT/build/envsetup.sh" ]; then
  echo "Error: build/envsetup.sh not found."
  echo "Run this script from your AOSP source root, or set AOSP_ROOT."
  exit 1
fi

# Copy RBE config files if not present
RBE_CONFIG_DEST="$AOSP_ROOT/build/soong/rbe_config"
if [ ! -f "$RBE_CONFIG_DEST/buildbarn.json" ]; then
  echo "Copying RBE config files to $RBE_CONFIG_DEST/..."
  cp "$REPO_DIR/local-dev/rbe_config/buildbarn.json" "$RBE_CONFIG_DEST/"
  cp "$REPO_DIR/local-dev/rbe_config/empty_creds.json" "$RBE_CONFIG_DEST/"
fi

export USE_RBE=1
export NINJA_REMOTE_NUM_JOBS="${NINJA_REMOTE_NUM_JOBS:-72}"

echo "Starting AAOS build with RBE (NINJA_REMOTE_NUM_JOBS=$NINJA_REMOTE_NUM_JOBS)..."

cd "$AOSP_ROOT"
source build/envsetup.sh
lunch sdk_car_x86_64-trunk_staging-userdebug
m
