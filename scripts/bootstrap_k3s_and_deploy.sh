#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-raspberry-pi-arc-demo:latest}"
K8S_DIR="${K8S_DIR:-k8s}"
TMP_IMAGE_TAR=""

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. k3s install will provide it." >&2
fi

if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | sh -
fi

docker build -t "${IMAGE_NAME}" .
TMP_IMAGE_TAR="$(mktemp --suffix=.tar)"
cleanup() {
  if [ -n "${TMP_IMAGE_TAR}" ] && [ -f "${TMP_IMAGE_TAR}" ]; then
    rm -f "${TMP_IMAGE_TAR}"
  fi
}
trap cleanup EXIT

docker save "${IMAGE_NAME}" -o "${TMP_IMAGE_TAR}"
sudo k3s ctr images import "${TMP_IMAGE_TAR}"

if [ ! -d "${K8S_DIR}" ]; then
  echo "Kubernetes manifest directory not found: ${K8S_DIR}" >&2
  exit 1
fi
sudo kubectl kustomize "${K8S_DIR}" >/dev/null

sudo kubectl apply -k "${K8S_DIR}"
sudo kubectl -n raspberry-pi-arc-demo rollout status deployment/log-writer

echo "Deployment completed. Logs are written to /var/lib/raspberry-pi-arc/logs/demo.log"
