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
echo "  Docker Install — Step 3: Verify Installation"
echo "========================================================"

# ---------------------------------------------------------------------------
# Run the hello-world container to verify Docker is working
# ---------------------------------------------------------------------------
step "Running Docker hello-world container..."
if sudo docker run hello-world; then
  echo ""
  info "✅  Docker is installed and working correctly."
else
  die "Docker hello-world test failed. Check the Docker daemon status with: sudo systemctl status docker"
fi