#!/bin/bash
set -euo pipefail

# Start AAOS build with RBE enabled.
# Run this script from your AOSP source root, or set AOSP_ROOT.
#
# Soong does not load buildbarn.json automatically — these env vars must
# be exported before the build. The critical ones are:
#   RBE_service                             (Buildbarn frontend address)
#   RBE_use_application_default_credentials (must be false)
#   RBE_credential_file                     (empty protobuf file)

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
fi
if [ ! -f "$RBE_CONFIG_DEST/empty_creds.json" ] || [ -s "$RBE_CONFIG_DEST/empty_creds.json" ]; then
  echo "Creating empty credentials file (0-byte, valid empty protobuf)..."
  truncate -s 0 "$RBE_CONFIG_DEST/empty_creds.json"
fi

# RBE environment — soong reads these directly, NOT from buildbarn.json
export USE_RBE=1
export NINJA_REMOTE_NUM_JOBS="${NINJA_REMOTE_NUM_JOBS:-72}"

# Connection to Buildbarn frontend (no grpc:// prefix — reproxy adds it)
export RBE_service=localhost:8980
export RBE_service_no_auth=true
export RBE_service_no_security=true

# Authentication: disable ADC, use empty credential file
# Without RBE_use_application_default_credentials=false, soong defaults
# to ADC which fails on non-Google environments.
export RBE_use_application_default_credentials=false
export RBE_credential_file=build/soong/rbe_config/empty_creds.json

# Action types and execution strategy
export RBE_CXX=1
export RBE_JAVAC=1
export RBE_R8=1
export RBE_D8=1
export RBE_instance=""
export RBE_DIR=prebuilts/remoteexecution-client/live
export RBE_CXX_EXEC_STRATEGY=remote_local_fallback
export RBE_JAVAC_EXEC_STRATEGY=remote_local_fallback
export RBE_R8_EXEC_STRATEGY=remote_local_fallback
export RBE_D8_EXEC_STRATEGY=remote_local_fallback

echo "Starting AAOS build with RBE (NINJA_REMOTE_NUM_JOBS=$NINJA_REMOTE_NUM_JOBS)..."

cd "$AOSP_ROOT"

# AOSP scripts reference unset variables — disable -u for sourcing
set +u
source build/envsetup.sh
lunch sdk_car_x86_64-trunk_staging-userdebug
m
