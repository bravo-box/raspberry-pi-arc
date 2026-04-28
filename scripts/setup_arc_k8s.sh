#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${LOCATION:?Set LOCATION}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${CLOUD:=AzureUSGovernment}"
: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
else
  OS="unknown"
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  HELM_ARCH="linux-arm64"
elif [ "$ARCH" = "x86_64" ]; then
  HELM_ARCH="linux-amd64"
else
  HELM_ARCH="linux-${ARCH}"
fi

echo "Detected OS: $OS, Architecture: $ARCH ($HELM_ARCH)"

# Check for Azure CLI
if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is required. Installing..." >&2
  if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ] || [ "$OS" = "raspbian" ]; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  else
    echo "Unable to auto-install Azure CLI on $OS. Please install manually." >&2
    echo "See: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli" >&2
    exit 1
  fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

# Validate kubeconfig exists and is readable
if [ ! -f "${KUBECONFIG}" ]; then
  echo "Kubeconfig file not found: ${KUBECONFIG}" >&2
  echo "Set KUBECONFIG environment variable to point to your cluster's kubeconfig" >&2
  echo "Example: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >&2
  exit 1
fi

# Verify kubectl can reach the cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Unable to connect to cluster using kubeconfig: ${KUBECONFIG}" >&2
  echo "Please verify the cluster is running and kubeconfig is valid" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "You must be logged into Azure CLI. Run 'az login' first." >&2
  exit 1
fi

# Verify we're using Azure Government
CURRENT_CLOUD=$(az cloud show --query name -o tsv 2>/dev/null || echo "")
if [ "${CURRENT_CLOUD}" != "AzureUSGovernment" ]; then
  echo "Error: You are logged into '${CURRENT_CLOUD}', but this script requires Azure Government (AzureUSGovernment)." >&2
  echo "Please log out and log in again with: az login --cloud AzureUSGovernment" >&2
  exit 1
fi

export KUBECONFIG

# Ensure helm is available and architecture-compatible
if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required. Installing ${HELM_ARCH}-compatible helm..." >&2
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Verify helm is executable and correct architecture
HELM_PATH=$(command -v helm)
HELM_FILE_TYPE=$(file "$HELM_PATH" 2>/dev/null || echo "")
echo "Using helm at: $HELM_PATH"
echo "Helm architecture: $HELM_FILE_TYPE" >&2

# Azure CLI connectedk8s extension may download its own helm binary
# We need to ensure the cached binary is the correct architecture
AZURE_HELM_CACHE="${HOME}/.azure/helm/v3.12.2"
if [ -d "${AZURE_HELM_CACHE}" ]; then
  echo "Ensuring Azure CLI helm cache has correct architecture..." >&2
  
  # If we're on ARM and x86-64 binary exists, replace it with ARM binary
  if [ "${HELM_ARCH}" = "linux-arm64" ] && [ -f "${AZURE_HELM_CACHE}/linux-amd64/helm" ]; then
    FILE_TYPE=$(file "${AZURE_HELM_CACHE}/linux-amd64/helm" 2>/dev/null || echo "")
    if echo "$FILE_TYPE" | grep -q "x86-64"; then
      echo "Detected incompatible x86-64 helm at ${AZURE_HELM_CACHE}/linux-amd64/helm" >&2
      echo "Downloading ARM64-compatible helm to replace it..." >&2
      
      HELM_VERSION=$(helm version --template='{{.Version}}' 2>/dev/null || echo "v3.12.2")
      HELM_VERSION=${HELM_VERSION#v}  # Remove 'v' prefix if present
      HELM_URL="https://get.helm.sh/helm-v${HELM_VERSION}-linux-arm64.tar.gz"
      
      # Download and extract ARM64 helm binary
      TEMP_DIR=$(mktemp -d)
      trap "rm -rf $TEMP_DIR" EXIT
      if curl -fsSL "$HELM_URL" -o "$TEMP_DIR/helm.tar.gz" 2>/dev/null; then
        tar -xzf "$TEMP_DIR/helm.tar.gz" -C "$TEMP_DIR" && \
        cp "$TEMP_DIR/linux-arm64/helm" "${AZURE_HELM_CACHE}/linux-amd64/helm" && \
        chmod +x "${AZURE_HELM_CACHE}/linux-amd64/helm" && \
        echo "Replaced with ARM64-compatible helm binary" >&2
      else
        echo "Failed to download helm from $HELM_URL, using fallback..." >&2
        cp "$HELM_PATH" "${AZURE_HELM_CACHE}/linux-amd64/helm"
        chmod +x "${AZURE_HELM_CACHE}/linux-amd64/helm"
      fi
    fi
  fi
fi

echo "Setting Azure cloud to: ${CLOUD}" >&2
az cloud set --name "${CLOUD}"
az account set --subscription "${SUBSCRIPTION_ID}"

echo "Adding Azure Arc extensions..." >&2
az extension add --name connectedk8s --yes
az extension add --name k8s-extension --yes
az extension add --name k8s-configuration --yes

# Ensure kubeconfig file exists and is readable
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "Error: k3s.yaml not found at $KUBECONFIG_PATH" >&2
  exit 1
fi

sudo chmod 644 "$KUBECONFIG_PATH"

# Export kubeconfig for Azure CLI to use
export KUBECONFIG="$KUBECONFIG_PATH"

# Verify kubeconfig is valid
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "Error: Failed to connect to cluster with kubeconfig. Verify k3s is running." >&2
  exit 1
fi

echo "Connecting cluster to Azure Arc..." >&2
az connectedk8s connect \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --location "${LOCATION}" \
  --kube-config "$KUBECONFIG_PATH"

# Azure Monitor extension for container log collection/aggregation from Arc-enabled K8s.
echo "Installing Azure Monitor extension..." >&2
az k8s-extension create \
  --cluster-type connectedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name azuremonitor-containers \
  --extension-type Microsoft.AzureMonitor.Containers \
  --auto-upgrade true \
  --release-train stable

echo ""
echo "✓ Arc onboarding complete for cluster ${CLUSTER_NAME}."
echo ""
echo "Next steps:"
echo "  1. Create a bearer token: ./scripts/create_bearer_token.sh"
echo "  2. Configure GitOps: ./scripts/arc_gitops_deploy.sh"
