#!/bin/bash
set -euo pipefail

# Tear down the Buildbarn k3d cluster and clean up resources.
#
# This deletes the k3d cluster (and all Kubernetes resources within it),
# removes the aaos-runner Docker image, and optionally cleans up reproxy state.

CLUSTER_NAME="${CLUSTER_NAME:-buildbarn}"

echo "Tearing down Buildbarn RBE environment..."

# Delete k3d cluster
if sudo k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  echo "Deleting k3d cluster '$CLUSTER_NAME'..."
  sudo k3d cluster delete "$CLUSTER_NAME"
else
  echo "Cluster '$CLUSTER_NAME' not found, skipping."
fi

# Remove Docker image
if docker image inspect aaos-runner:local &>/dev/null; then
  echo "Removing aaos-runner:local Docker image..."
  docker rmi aaos-runner:local
else
  echo "aaos-runner:local image not found, skipping."
fi

# Clean up stale reproxy state
if ls /tmp/reproxy* /tmp/RBE* 2>/dev/null | head -1 &>/dev/null; then
  echo "Cleaning up reproxy temp files..."
  rm -f /tmp/reproxy* /tmp/RBE*
fi

echo ""
echo "Teardown complete."
echo "Note: The bb-deployments clone and AOSP source tree are not removed."
echo "Remove them manually if no longer needed."
