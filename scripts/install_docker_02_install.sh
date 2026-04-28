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
echo "  Docker Install — Step 2: Install Docker Engine"
echo "========================================================"

# ---------------------------------------------------------------------------
# Install Docker Engine and related packages
# ---------------------------------------------------------------------------
step "Installing Docker Engine, CLI, containerd, and plugins..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
info "Docker packages installed successfully."

# ---------------------------------------------------------------------------
# Add current user to the docker group
# ---------------------------------------------------------------------------
step "Adding '${USER}' to the 'docker' group..."
sudo usermod -aG docker "$USER"
info "User '${USER}' added to the 'docker' group."
warn "You must start a new shell session (or run 'newgrp docker') for the group change to take effect."

# ---------------------------------------------------------------------------
# Activate docker group for the current shell
# ---------------------------------------------------------------------------
step "Activating 'docker' group for the current shell session..."
newgrp docker

echo ""
info "✅  Docker Engine installed. Run install_docker_03_verify.sh to verify the installation."