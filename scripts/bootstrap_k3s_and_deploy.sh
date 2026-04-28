#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Colour / logging helpers  (consistent with arc-scripts/configure-arc.sh)
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }
step()  { echo -e "\n${CYAN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IMAGE_NAME="${IMAGE_NAME:-raspberry-pi-arc-demo:latest}"
K8S_DIR="${K8S_DIR:-k8s}"
TMP_IMAGE_TAR=""

echo "========================================================"
echo "  Raspberry Pi Arc — Bootstrap k3s and Deploy"
echo "========================================================"

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
step "Detecting operating system..."
# shellcheck source=/dev/null
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
  info "Detected OS: ${OS}"
else
  OS="unknown"
  warn "Could not detect OS from /etc/os-release; proceeding as 'unknown'."
fi

# ---------------------------------------------------------------------------
# Check / install required tools
# ---------------------------------------------------------------------------
step "Checking required tools..."

if ! command -v curl >/dev/null 2>&1; then
  warn "curl not found. Attempting to install..."
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ] || [ "$OS" = "raspbian" ]; then
    sudo apt-get update && sudo apt-get install -y curl
    info "curl installed successfully."
  else
    die "Unable to auto-install curl on '${OS}'. Please install it manually."
  fi
else
  info "curl is available."
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "docker not found. Attempting to install Docker..."
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ] || [ "$OS" = "raspbian" ]; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
    # Add current user to docker group
    sudo usermod -aG docker "$USER" || true
    info "Docker installed. You may need to log out and back in for group changes to take effect."
  else
    die "Unable to auto-install Docker on '${OS}'. Please install it manually."
  fi
else
  info "docker is available."
fi

if ! command -v kubectl >/dev/null 2>&1; then
  warn "kubectl not found. k3s installation will provide it."
fi

if ! command -v k3s >/dev/null 2>&1; then
  step "Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
  info "k3s installed successfully."
else
  info "k3s is already installed."
fi

if ! command -v az >/dev/null 2>&1; then
  step "Installing Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  info "Azure CLI installed successfully."
else
  info "Azure CLI is already installed."
fi

# ---------------------------------------------------------------------------
# Build and import Docker image
# ---------------------------------------------------------------------------
step "Building Docker image: ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" .
info "Docker image built successfully."

TMP_IMAGE_TAR="$(mktemp).tar"
cleanup() {
  if [ -n "${TMP_IMAGE_TAR}" ] && [ -f "${TMP_IMAGE_TAR}" ]; then
    rm -f "${TMP_IMAGE_TAR}"
  fi
}
trap cleanup EXIT

step "Saving Docker image to temporary archive..."
docker save "${IMAGE_NAME}" -o "${TMP_IMAGE_TAR}"
info "Image saved to ${TMP_IMAGE_TAR}."

step "Importing image into k3s container runtime..."
sudo k3s ctr images import "${TMP_IMAGE_TAR}"
info "Image imported into k3s."

# ---------------------------------------------------------------------------
# Apply Kubernetes manifests
# ---------------------------------------------------------------------------
step "Validating Kubernetes manifests in '${K8S_DIR}'..."
if [ ! -d "${K8S_DIR}" ]; then
  die "Kubernetes manifest directory not found: ${K8S_DIR}"
fi
# Validate manifests render successfully before applying.
sudo kubectl kustomize "${K8S_DIR}" >/dev/null
info "Manifests validated successfully."

step "Applying Kubernetes manifests..."
sudo kubectl apply -k "${K8S_DIR}"
info "Manifests applied."

step "Waiting for log-writer deployment to be ready..."
sudo kubectl -n raspberry-pi-arc-demo rollout status deployment/log-writer
info "Deployment is ready."

step "Setting permissions on kubeconfig..."
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
info "Kubeconfig permissions updated."

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "✅  Deployment completed successfully!"
info "✅  Logs are written to /var/lib/raspberry-pi-arc/logs/demo.log"
echo ""
echo "To view logs:"
echo "  sudo tail -f /var/lib/raspberry-pi-arc/logs/demo.log"
