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

echo "========================================================"
echo "  Docker Install — Step 1: Set Up Repository"
echo "========================================================"

# ---------------------------------------------------------------------------
# Install prerequisites
# ---------------------------------------------------------------------------
step "Updating package lists and installing ca-certificates and curl..."
sudo apt update
sudo apt install -y ca-certificates curl
info "Prerequisites installed."

# ---------------------------------------------------------------------------
# Add Docker's official GPG key
# ---------------------------------------------------------------------------
step "Installing Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
info "Docker GPG key installed at /etc/apt/keyrings/docker.asc."

# ---------------------------------------------------------------------------
# Add the Docker APT repository
# ---------------------------------------------------------------------------
step "Adding Docker APT repository..."
# shellcheck source=/dev/null   # /etc/os-release path is dynamic; static analysis cannot follow it
OS_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
DPKG_ARCH=$(dpkg --print-architecture)
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${OS_CODENAME}
Components: stable
Architectures: ${DPKG_ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
info "Docker APT repository added."

# ---------------------------------------------------------------------------
# Refresh package lists
# ---------------------------------------------------------------------------
step "Refreshing package lists..."
sudo apt update
info "Package lists updated."

echo ""
info "✅  Docker repository configured. Run install_docker_02_install.sh to install Docker."