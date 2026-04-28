#!/usr/bin/env bash
set -euo pipefail

: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${CLUSTER_NAME:?Set CLUSTER_NAME}"
: "${LOCATION:?Set LOCATION}"
: "${ACR_NAME:?Set ACR_NAME}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${CLOUD:=AzureUSGovernment}"
: "${KUBECONFIG:=/etc/rancher/k3s/k3s.yaml}"

echo "=== Azure Container Registry Replication Setup ==="
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Cluster Name: ${CLUSTER_NAME}"
echo "ACR Name: ${ACR_NAME}"
echo "Cloud: ${CLOUD}"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="$ID"
else
  OS="unknown"
fi

# Check for required tools
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
  exit 1
fi

# Verify kubectl can reach the cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Unable to connect to cluster using kubeconfig: ${KUBECONFIG}" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "You must be logged into Azure CLI. Run 'az login --cloud AzureUSGovernment' first." >&2
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

# Verify the cluster is connected to Arc
echo "Verifying cluster is Arc-enabled..."
if ! az connectedk8s show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "Error: Cluster '${CLUSTER_NAME}' is not connected to Azure Arc." >&2
  echo "Please run setup_arc_k8s.sh first to onboard the cluster to Arc." >&2
  exit 1
fi
echo "✓ Cluster is Arc-enabled"

# Check if ACR exists
echo ""
echo "Checking Azure Container Registry '${ACR_NAME}'..."
if ! az acr show --resource-group "${RESOURCE_GROUP}" --name "${ACR_NAME}" >/dev/null 2>&1; then
  echo "ACR '${ACR_NAME}' not found. Creating..."
  az acr create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${ACR_NAME}" \
    --sku Standard \
    --location "${LOCATION}"
  echo "✓ ACR created: ${ACR_NAME}"
else
  echo "✓ ACR already exists: ${ACR_NAME}"
fi

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --query loginServer -o tsv)
echo "ACR Login Server: ${ACR_LOGIN_SERVER}"

# Create service principal for ACR access if it doesn't exist
echo ""
echo "Setting up service principal for ACR access..."
SP_NAME="acr-pull-push-${CLUSTER_NAME}"
EXISTING_SP=$(az ad sp list --filter "displayName eq '${SP_NAME}'" --query "[].appId" -o tsv 2>/dev/null || echo "")

if [ -z "${EXISTING_SP}" ]; then
  echo "Creating service principal '${SP_NAME}'..."
  SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "${SP_NAME}" \
    --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${ACR_NAME}" \
    --role acrpush \
    --query "{appId:appId, password:password}" \
    -o json)
  
  SP_APP_ID=$(echo "${SP_OUTPUT}" | grep -o '"appId":"[^"]*' | cut -d'"' -f4)
  SP_PASSWORD=$(echo "${SP_OUTPUT}" | grep -o '"password":"[^"]*' | cut -d'"' -f4)
  echo "✓ Service principal created: ${SP_APP_ID}"
else
  echo "⚠ Service principal '${SP_NAME}' already exists (appId: ${EXISTING_SP})"
  echo "  If you need to reset credentials, delete it manually:"
  echo "  az ad sp delete --id ${EXISTING_SP}"
  echo "  Using existing service principal..."
  SP_APP_ID="${EXISTING_SP}"
  # For existing SP, you would need to reset password separately
  echo "  Note: You must provide the password for the existing SP to configure k3s credentials"
  exit 1
fi

# Create Kubernetes secret for ACR authentication
echo ""
echo "Creating Kubernetes secret for ACR authentication..."
kubectl create namespace arc-registry-replication --dry-run=client -o yaml | kubectl apply -f -

# Create docker registry secret
kubectl create secret docker-registry acr-secret \
  --docker-server="${ACR_LOGIN_SERVER}" \
  --docker-username="${SP_APP_ID}" \
  --docker-password="${SP_PASSWORD}" \
  --docker-email="arc-admin@example.com" \
  --namespace=arc-registry-replication \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Kubernetes secret created in arc-registry-replication namespace"

# Create config map for k3s registry mirroring
echo ""
echo "Configuring k3s registry mirroring..."

# Create k3s registry config
K3S_REGISTRY_CONFIG="/etc/rancher/k3s/registries.yaml"
K3S_REGISTRY_CONFIG_DIR="/etc/rancher/k3s"

# Check if we have permission to modify k3s config
if [ ! -w "${K3S_REGISTRY_CONFIG_DIR}" ]; then
  echo "⚠ Cannot write to k3s config directory without sudo. Using sudo for configuration..."
  USE_SUDO=true
else
  USE_SUDO=false
fi

# Create the registries configuration
REGISTRY_CONFIG=$(cat <<EOF
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
  "${ACR_LOGIN_SERVER}":
    endpoint:
      - "https://${ACR_LOGIN_SERVER}"
configs:
  "${ACR_LOGIN_SERVER}":
    auth:
      username: "${SP_APP_ID}"
      password: "${SP_PASSWORD}"
EOF
)

if [ "${USE_SUDO}" = "true" ]; then
  echo "${REGISTRY_CONFIG}" | sudo tee "${K3S_REGISTRY_CONFIG}" > /dev/null
else
  echo "${REGISTRY_CONFIG}" > "${K3S_REGISTRY_CONFIG}"
fi

echo "✓ k3s registry configuration updated"

# Restart k3s to apply the new configuration
echo ""
echo "Restarting k3s to apply registry configuration..."
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart k3s || true
else
  echo "⚠ Unable to determine restart method. Please restart k3s manually:"
  echo "  sudo systemctl restart k3s"
fi

# Wait for cluster to stabilize
echo ""
echo "Waiting for cluster to stabilize..."
sleep 10

# Verify k3s connection is still active
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "⚠ Warning: kubectl cluster connection may have been temporarily interrupted."
  echo "  Waiting for cluster to fully restart..."
  sleep 15
fi

# Create a ConfigMap for replication configuration in the Arc-enabled cluster
echo ""
echo "Setting up Arc-managed registry replication configuration..."
kubectl create namespace arc-configuration --dry-run=client -o yaml | kubectl apply -f -

# Create a ConfigMap with replication metadata
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: acr-replication-config
  namespace: arc-configuration
data:
  acr-login-server: "${ACR_LOGIN_SERVER}"
  acr-resource-group: "${RESOURCE_GROUP}"
  acr-name: "${ACR_NAME}"
  service-principal-app-id: "${SP_APP_ID}"
  cluster-name: "${CLUSTER_NAME}"
  replication-enabled: "true"
  local-registry-endpoint: "localhost:5000"
EOF

echo "✓ Registry replication configuration deployed"

# Test connectivity to ACR
echo ""
echo "Testing connectivity to Azure Container Registry..."
if docker login -u "${SP_APP_ID}" -p "${SP_PASSWORD}" "${ACR_LOGIN_SERVER}" >/dev/null 2>&1; then
  echo "✓ Successfully authenticated with ACR"
  docker logout "${ACR_LOGIN_SERVER}" >/dev/null 2>&1 || true
else
  echo "⚠ Warning: Could not authenticate with ACR. Please verify credentials."
fi

# Verify local k3s registry is accessible
echo ""
echo "Verifying local k3s registry..."
if kubectl get pods -A | grep -q "registry"; then
  echo "✓ k3s registry appears to be running"
else
  echo "⚠ Warning: k3s registry may not be running. Check with: kubectl get pods -A | grep registry"
fi

# Display summary
echo ""
echo "=== Registry Replication Setup Complete ==="
echo ""
echo "Configuration Summary:"
echo "  ACR Name: ${ACR_NAME}"
echo "  ACR Login Server: ${ACR_LOGIN_SERVER}"
echo "  Service Principal: ${SP_APP_ID}"
echo "  K3s Registry Config: ${K3S_REGISTRY_CONFIG}"
echo "  Kubernetes Secret: acr-secret (in arc-registry-replication namespace)"
echo "  Configuration ConfigMap: acr-replication-config (in arc-configuration namespace)"
echo ""
echo "To verify replication is working:"
echo "  1. Push an image to your k3s registry:"
echo "     docker push localhost:5000/test-image:latest"
echo ""
echo "  2. Check if image appears in ACR:"
echo "     az acr repository list --name ${ACR_NAME}"
echo ""
echo "  3. View replication logs:"
echo "     kubectl logs -f -n arc-registry-replication -l app=registry"
echo ""
echo "To push images to ACR from the cluster:"
echo "  docker login ${ACR_LOGIN_SERVER} -u ${SP_APP_ID} -p <password>"
echo ""
echo "For manual image replication, use Azure CLI:"
echo "  az acr import --resource-group ${RESOURCE_GROUP} --name ${ACR_NAME} --source localhost:5000/image:tag --image replicated-image:tag"
echo ""
