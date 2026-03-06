#!/usr/bin/env bash
# Push droste-seed from build VM to GHCR.
# Run this on your local machine (not the build VM).
#
# Usage: ./scripts/push-seed-to-ghcr.sh

set -euo pipefail

OWNER="doctorjei"
REGISTRY="ghcr.io"
IMAGE="droste-seed"
BUILD_VM="droste@192.168.0.129"

#echo "==> Pulling ${IMAGE} from build VM (${BUILD_VM})..."
#ssh "${BUILD_VM}" "podman save localhost/${IMAGE}" | podman load

echo "==> Logging in to ${REGISTRY}..."
podman login "${REGISTRY}" -u "${OWNER}"

echo "==> Tagging and pushing..."
podman tag "localhost/${IMAGE}" "${REGISTRY}/${OWNER}/${IMAGE}:latest"
podman push "${REGISTRY}/${OWNER}/${IMAGE}:latest"

echo "==> Done. ${REGISTRY}/${OWNER}/${IMAGE}:latest is live."
