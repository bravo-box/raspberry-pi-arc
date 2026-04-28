#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${LOCATION:?Set LOCATION}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${CLOUD:=AzureCloud}"
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

export KUBECONFIG

# Ensure helm is available and architecture-compatible
if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required. Installing ${HELM_ARCH}-compatible helm..." >&2
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Get the actual helm path
HELM_PATH=$(command -v helm)
echo "Using helm at: $HELM_PATH"

# Create wrapper at the location Azure CLI expects to bypass the cached binary
AZURE_HELM_PATH="${HOME}/.azure/helm/v3.12.2/${HELM_ARCH}"
mkdir -p "${AZURE_HELM_PATH}"
cat > "${AZURE_HELM_PATH}/helm" << HELM_WRAPPER
#!/bin/bash
exec ${HELM_PATH} "\$@"
HELM_WRAPPER
chmod +x "${AZURE_HELM_PATH}/helm"
echo "Created helm wrapper at: ${AZURE_HELM_PATH}/helm"

echo "Setting Azure cloud to: ${CLOUD}" >&2
az cloud set --name "${CLOUD}"
az account set --subscription "${SUBSCRIPTION_ID}"

echo "Adding Azure Arc extensions..." >&2
az extension add --name connectedk8s --yes
az extension add --name k8s-extension --yes
az extension add --name k8s-configuration --yes

echo "Connecting cluster to Azure Arc..." >&2
az connectedk8s connect \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --location "${LOCATION}"

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
