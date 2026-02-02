#!/bin/bash
set -euo pipefail

# Build AAOS runner image, import to k3d, and deploy Buildbarn

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BB_DEPLOY="${BB_DEPLOY_DIR:-$REPO_DIR/../bb-deployments}"
CLUSTER_NAME="${CLUSTER_NAME:-buildbarn}"

# Build runner image
echo "Building aaos-runner image..."
docker build -t aaos-runner:local "$REPO_DIR/local-dev/docker/aaos-runner/"

# Import into k3d
echo "Importing aaos-runner image into k3d cluster '$CLUSTER_NAME'..."
sudo k3d image import aaos-runner:local -c "$CLUSTER_NAME"

# Clone upstream bb-deployments if not present
if [ ! -d "$BB_DEPLOY" ]; then
  echo "Cloning upstream bb-deployments..."
  git clone https://github.com/buildbarn/bb-deployments.git "$BB_DEPLOY"
fi

# Copy overlay into bb-deployments
echo "Copying local-dev overlay to $BB_DEPLOY/local-dev/..."
cp -r "$REPO_DIR/local-dev/" "$BB_DEPLOY/local-dev/"

# Apply with kustomize
echo "Applying Kustomize overlay..."
kubectl apply -k "$BB_DEPLOY/local-dev/"

echo ""
echo "Deployment applied. Watch pod status with:"
echo "  kubectl -n buildbarn get pods -w"
