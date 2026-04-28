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
# Required environment variables
# ---------------------------------------------------------------------------
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${CONFIG_NAME:=raspberry-pi-arc-demo-config}"
: "${GIT_REPO_URL:?Set GIT_REPO_URL}"
: "${GIT_BRANCH:=main}"
: "${MANIFEST_PATH:=./k8s}"

echo "========================================================"
echo "  Raspberry Pi Arc — Arc GitOps Deployment"
echo "========================================================"
info "Resource Group : ${RESOURCE_GROUP}"
info "Cluster Name   : ${CLUSTER_NAME}"
info "Config Name    : ${CONFIG_NAME}"
info "Git Repo URL   : ${GIT_REPO_URL}"
info "Git Branch     : ${GIT_BRANCH}"
info "Manifest Path  : ${MANIFEST_PATH}"

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
step "Checking prerequisites..."
if ! command -v az >/dev/null 2>&1; then
  die "Azure CLI is required but not found. Please install it before running this script."
fi
info "Azure CLI is available."

# ---------------------------------------------------------------------------
# Create / update GitOps configuration
# ---------------------------------------------------------------------------
step "Creating / updating Arc GitOps Flux configuration '${CONFIG_NAME}'..."
az k8s-configuration flux create \
  --cluster-type connectedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CONFIG_NAME}" \
  --namespace flux-system \
  --scope cluster \
  --url "${GIT_REPO_URL}" \
  --branch "${GIT_BRANCH}" \
  --kustomization name=raspberry-pi-arc-demo path="${MANIFEST_PATH}" prune=true interval=3m

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "✅  Arc GitOps deployment configuration created/updated successfully."
