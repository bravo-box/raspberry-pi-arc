#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-raspberry-pi-arc-demo:latest}"
K8S_DIR="${K8S_DIR:-k8s}"
TMP_IMAGE_TAR=""

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
else
  OS="unknown"
fi

# Check for required tools
if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found. Installing..." >&2
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt-get update && sudo apt-get install -y curl
  elif [ "$OS" = "raspbian" ]; then
    sudo apt-get update && sudo apt-get install -y curl
  else
    echo "Unable to auto-install curl on $OS. Please install manually." >&2
    exit 1
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Installing Docker..." >&2
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    # Add current user to docker group
    sudo usermod -aG docker "$USER" || true
    echo "Docker installed. You may need to log out and log back in for group changes to take effect." >&2
  elif [ "$OS" = "raspbian" ]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker "$USER" || true
    echo "Docker installed. You may need to log out and log back in for group changes to take effect." >&2
  else
    echo "Unable to auto-install docker on $OS. Please install manually." >&2
    exit 1
  fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. k3s install will provide it." >&2
fi

if ! command -v k3s >/dev/null 2>&1; then
  echo "Installing k3s..." >&2
  curl -sfL https://get.k3s.io | sh -
fi

docker build -t "${IMAGE_NAME}" .
TMP_IMAGE_TAR="$(mktemp).tar"
cleanup() {
  if [ -n "${TMP_IMAGE_TAR}" ] && [ -f "${TMP_IMAGE_TAR}" ]; then
    rm -f "${TMP_IMAGE_TAR}"
  fi
}
trap cleanup EXIT

echo "Saving Docker image..." >&2
docker save "${IMAGE_NAME}" -o "${TMP_IMAGE_TAR}"

echo "Importing image into k3s..." >&2
sudo k3s ctr images import "${TMP_IMAGE_TAR}"

if [ ! -d "${K8S_DIR}" ]; then
  echo "Kubernetes manifest directory not found: ${K8S_DIR}" >&2
  exit 1
fi

echo "Validating Kubernetes manifests..." >&2
# Validate manifests render successfully before applying.
sudo kubectl kustomize "${K8S_DIR}" >/dev/null

echo "Applying Kubernetes manifests..." >&2
sudo kubectl apply -k "${K8S_DIR}"

echo "Waiting for log-writer deployment to be ready..." >&2
sudo kubectl -n raspberry-pi-arc-demo rollout status deployment/log-writer

echo ""
echo "✓ Deployment completed successfully!"
echo "✓ Logs are written to /var/lib/raspberry-pi-arc/logs/demo.log"
echo ""
echo "To view logs:"
echo "  sudo tail -f /var/lib/raspberry-pi-arc/logs/demo.log"
