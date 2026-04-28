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
: "${LOCATION:?Set LOCATION}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${CLOUD:=AzureUSGovernment}"
: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"

echo "========================================================"
echo "  Raspberry Pi Arc — Arc-enabled Kubernetes Setup"
echo "========================================================"

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------
step "Detecting operating system and architecture..."
# shellcheck source=/dev/null
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
else
  OS="unknown"
  warn "Could not detect OS from /etc/os-release; proceeding as 'unknown'."
fi

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  HELM_ARCH="linux-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  HELM_ARCH="linux-amd64"
else
  HELM_ARCH="linux-${ARCH}"
fi
info "OS: ${OS} | Architecture: ${ARCH} (${HELM_ARCH})"

# ---------------------------------------------------------------------------
# Check / install required tools
# ---------------------------------------------------------------------------
step "Checking required tools..."

if ! command -v az >/dev/null 2>&1; then
  warn "Azure CLI is not installed. Attempting to install..."
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ] || [ "$OS" = "raspbian" ]; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    info "Azure CLI installed successfully."
  else
    error "Unable to auto-install Azure CLI on '${OS}'. Please install manually."
    die "See: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
  fi
else
  info "Azure CLI is available."
fi

if ! command -v kubectl >/dev/null 2>&1; then
  die "kubectl is required but not found. Install k3s or kubectl before running this script."
fi
info "kubectl is available."

# Validate kubeconfig exists and is readable
if [ ! -f "${KUBECONFIG}" ]; then
  error "Kubeconfig file not found: ${KUBECONFIG}"
  error "Set KUBECONFIG to point to your cluster's kubeconfig."
  die   "Example: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
fi
info "Kubeconfig found: ${KUBECONFIG}"

# Verify kubectl can reach the cluster
step "Verifying cluster connectivity..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  error "Unable to connect to cluster using kubeconfig: ${KUBECONFIG}"
  die   "Please verify the cluster is running and kubeconfig is valid."
fi
info "Cluster is reachable."

# ---------------------------------------------------------------------------
# Verify Azure CLI login and cloud
# ---------------------------------------------------------------------------
step "Verifying Azure CLI authentication..."
if ! az account show >/dev/null 2>&1; then
  die "Not logged into Azure CLI. Run 'az login' first."
fi
info "Azure CLI is authenticated."

CURRENT_CLOUD=$(az cloud show --query name -o tsv 2>/dev/null || echo "")
if [ "${CURRENT_CLOUD}" != "AzureUSGovernment" ]; then
  error "You are logged into '${CURRENT_CLOUD}', but this script requires Azure Government (AzureUSGovernment)."
  die   "Please log out and log in again with: az login --cloud AzureUSGovernment"
fi
info "Azure cloud: ${CURRENT_CLOUD}"

export KUBECONFIG

# ---------------------------------------------------------------------------
# Ensure helm is available and architecture-compatible
# ---------------------------------------------------------------------------
step "Checking helm..."
if ! command -v helm >/dev/null 2>&1; then
  warn "helm not found. Installing ${HELM_ARCH}-compatible helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  info "helm installed successfully."
fi

HELM_PATH=$(command -v helm)
HELM_FILE_TYPE=$(file "$HELM_PATH" 2>/dev/null || echo "")
info "Using helm at: ${HELM_PATH}"
info "Helm binary type: ${HELM_FILE_TYPE}"

# Azure CLI connectedk8s extension may download its own helm binary;
# ensure the cached binary matches this machine's architecture.
AZURE_HELM_CACHE="${HOME}/.azure/helm/v3.12.2"
if [ -d "${AZURE_HELM_CACHE}" ]; then
  step "Ensuring Azure CLI helm cache has the correct architecture..."
  if [ "${HELM_ARCH}" = "linux-arm64" ] && [ -f "${AZURE_HELM_CACHE}/linux-amd64/helm" ]; then
    FILE_TYPE=$(file "${AZURE_HELM_CACHE}/linux-amd64/helm" 2>/dev/null || echo "")
    if echo "$FILE_TYPE" | grep -q "x86-64"; then
      warn "Detected incompatible x86-64 helm at ${AZURE_HELM_CACHE}/linux-amd64/helm"
      info "Downloading ARM64-compatible helm to replace it..."

      HELM_VERSION=$(helm version --template='{{.Version}}' 2>/dev/null || echo "v3.12.2")
      HELM_VERSION=${HELM_VERSION#v}  # Remove 'v' prefix if present
      HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-linux-arm64.tar.gz"

      TEMP_DIR=$(mktemp -d)
      # SC2064: intentionally expand TEMP_DIR now (at trap-set time) so the
      # correct directory path is captured, not re-evaluated at signal time.
      # shellcheck disable=SC2064
      trap "rm -rf ${TEMP_DIR}" EXIT
      if curl -fsSL "$HELM_URL" -o "$TEMP_DIR/helm.tar.gz" 2>/dev/null; then
        tar -xzf "$TEMP_DIR/helm.tar.gz" -C "$TEMP_DIR" && \
        cp "$TEMP_DIR/linux-arm64/helm" "${AZURE_HELM_CACHE}/linux-amd64/helm" && \
        chmod +x "${AZURE_HELM_CACHE}/linux-amd64/helm"
        info "Replaced cached helm with ARM64-compatible binary."
      else
        warn "Failed to download helm from ${HELM_URL}. Falling back to system helm binary."
        cp "$HELM_PATH" "${AZURE_HELM_CACHE}/linux-amd64/helm"
        chmod +x "${AZURE_HELM_CACHE}/linux-amd64/helm"
      fi
    else
      info "Cached helm binary is already the correct architecture."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Configure Azure CLI cloud and subscription
# ---------------------------------------------------------------------------
step "Setting Azure cloud to: ${CLOUD}..."
az cloud set --name "${CLOUD}"
az account set --subscription "${SUBSCRIPTION_ID}"
info "Azure cloud and subscription configured."

step "Adding required Azure Arc CLI extensions..."
az extension add --name connectedk8s --yes
az extension add --name k8s-extension --yes
az extension add --name k8s-configuration --yes
info "Azure Arc CLI extensions are ready."

# ---------------------------------------------------------------------------
# Validate kubeconfig for Azure CLI
# ---------------------------------------------------------------------------
step "Preparing kubeconfig for Azure CLI..."
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
if [ ! -f "$KUBECONFIG_PATH" ]; then
  die "k3s.yaml not found at ${KUBECONFIG_PATH}. Verify k3s is installed and running."
fi

sudo chmod 644 "$KUBECONFIG_PATH"
export KUBECONFIG="$KUBECONFIG_PATH"
info "Kubeconfig permissions set and exported."

if ! kubectl cluster-info >/dev/null 2>&1; then
  die "Failed to connect to cluster using kubeconfig. Verify k3s is running."
fi
info "Cluster connectivity re-confirmed."

# ---------------------------------------------------------------------------
# Connect to Azure Arc
# ---------------------------------------------------------------------------
step "Connecting cluster '${CLUSTER_NAME}' to Azure Arc..."
az connectedk8s connect \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --location "${LOCATION}" \
  --kube-config "$KUBECONFIG_PATH"
info "Arc connection established."

# Azure Monitor extension for container log collection/aggregation from Arc-enabled K8s.
step "Installing Azure Monitor extension..."
az k8s-extension create \
  --cluster-type connectedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name azuremonitor-containers \
  --extension-type Microsoft.AzureMonitor.Containers \
  --auto-upgrade true \
  --release-train stable
info "Azure Monitor extension installed."

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "✅  Arc onboarding complete for cluster '${CLUSTER_NAME}'."
echo ""
echo "Next steps:"
echo "  1. Create a bearer token: ./scripts/create_bearer_token.sh"
echo "  2. Configure GitOps:      ./scripts/arc_gitops_deploy.sh"
