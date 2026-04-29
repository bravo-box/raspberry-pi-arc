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
echo "  Raspberry Pi Arc — Create Fleet Resource Group"
echo "========================================================"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
LOCATION="usgovvirginia"
CLOUD="AzureUSGovernment"
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
KEYVAULT_NAME=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

Usage: $0 [OPTIONS]

Required:
  --resource-group   <name>    Azure resource group name
  --subscription-id  <id>      Azure Government subscription ID
  --keyvault-name    <name>    Key Vault name (3-24 alphanumeric chars and dashes)

Optional:
  --location         <region>  Azure Government region (default: usgovvirginia)
                               Supported: usgovvirginia | usgovarizona | usgovtexas
  --help                       Show this help message

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --resource-group)  RESOURCE_GROUP="$2";  shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --keyvault-name)   KEYVAULT_NAME="$2";   shift 2 ;;
    --location)        LOCATION="$2";        shift 2 ;;
    --help|-h)         usage ;;
    *) die "Unknown option: $1  (run with --help for usage)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -n "$RESOURCE_GROUP"  ]] || die "--resource-group is required."
[[ -n "$SUBSCRIPTION_ID" ]] || die "--subscription-id is required."
[[ -n "$KEYVAULT_NAME"   ]] || die "--keyvault-name is required."

# ---------------------------------------------------------------------------
# Verify Azure CLI is installed and authenticated
# ---------------------------------------------------------------------------
step "Verifying Azure CLI..."
command -v az >/dev/null 2>&1 || die "Azure CLI (az) is not installed. Please install it first."

if ! az account show >/dev/null 2>&1; then
  die "Not logged into Azure CLI. Run 'az login' first."
fi
info "Azure CLI is authenticated."

# ---------------------------------------------------------------------------
# Set cloud and subscription
# ---------------------------------------------------------------------------
step "Configuring Azure cloud: ${CLOUD}..."
az cloud set --name "${CLOUD}"
az account set --subscription "${SUBSCRIPTION_ID}"
info "Cloud set to '${CLOUD}', subscription '${SUBSCRIPTION_ID}' selected."

# ---------------------------------------------------------------------------
# Create resource group
# ---------------------------------------------------------------------------
step "Creating resource group '${RESOURCE_GROUP}' in '${LOCATION}'..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output table
info "Resource group '${RESOURCE_GROUP}' is ready."

# ---------------------------------------------------------------------------
# Create Key Vault
# ---------------------------------------------------------------------------
step "Creating Key Vault '${KEYVAULT_NAME}' in resource group '${RESOURCE_GROUP}'..."
az keyvault create \
  --name "${KEYVAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output table
info "Key Vault '${KEYVAULT_NAME}' created."

# ---------------------------------------------------------------------------
# Grant the signed-in user full secrets administration on the Key Vault
# ---------------------------------------------------------------------------
step "Retrieving signed-in user object ID..."
SIGNED_IN_USER_OID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)

if [[ -z "$SIGNED_IN_USER_OID" ]]; then
  warn "Could not determine signed-in user object ID via 'az ad signed-in-user show'."
  warn "You may need to set the Key Vault access policy manually."
else
  info "Signed-in user object ID: ${SIGNED_IN_USER_OID}"

  step "Assigning Key Vault secrets admin policy to the signed-in user..."
  az keyvault set-policy \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --object-id "${SIGNED_IN_USER_OID}" \
    --secret-permissions get list set delete recover backup restore purge \
    --output table
  info "Secrets admin policy applied to user '${SIGNED_IN_USER_OID}'."
fi

# ---------------------------------------------------------------------------
# Output Arc configuration snippet
# ---------------------------------------------------------------------------
echo ""
echo "========================================================"
echo "  Arc Configuration — copy and paste the block below"
echo "========================================================"
cat <<SNIPPET

# ---------------------------------------------------------------
# Environment variables for Azure Arc / GitOps setup
# ---------------------------------------------------------------
export CLOUD="${CLOUD}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export KEYVAULT_NAME="${KEYVAULT_NAME}"

# Set a unique name for your cluster before running setup_arc_k8s.sh
export CLUSTER_NAME="<your-cluster-name>"

# ---------------------------------------------------------------
# Connect the cluster to Azure Arc
# ---------------------------------------------------------------
./scripts/setup_arc_k8s.sh

# ---------------------------------------------------------------
# (Optional) Save the bearer token to Key Vault after onboarding
# ---------------------------------------------------------------
./scripts/save-bearer-token.sh \\
  --keyvault-name "${KEYVAULT_NAME}" \\
  --cluster-name  "\${CLUSTER_NAME}"

SNIPPET

info "✅  Fleet resource group setup complete."
