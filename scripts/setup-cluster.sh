#!/bin/bash
set -euo pipefail

# Create k3d cluster for Buildbarn RBE
#
# Port mappings:
#   8980 -> 8980  gRPC frontend (reproxy connects here)
#   8081 -> 80    bb-browser web UI

CLUSTER_NAME="${CLUSTER_NAME:-buildbarn}"

if sudo k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists. Delete with: sudo k3d cluster delete $CLUSTER_NAME"
  exit 1
fi

echo "Creating k3d cluster '$CLUSTER_NAME'..."
sudo k3d cluster create "$CLUSTER_NAME" \
  -p "8980:8980@loadbalancer" \
  -p "8081:80@loadbalancer"

echo "Cluster '$CLUSTER_NAME' created successfully."
echo "  gRPC frontend: localhost:8980"
echo "  bb-browser UI: http://localhost:8081"
