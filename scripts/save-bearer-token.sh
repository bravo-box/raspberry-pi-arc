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
echo "  Raspberry Pi Arc — Save Bearer Token to Key Vault"
echo "========================================================"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
KEYVAULT_NAME=""
CLUSTER_NAME=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

Usage: $0 [OPTIONS]

Required:
  --keyvault-name  <name>    Key Vault name where the token will be stored

Optional:
  --cluster-name   <name>    Kubernetes cluster name used as the secret key
                             (default: current kubectl context name)
  --help                     Show this help message

The bearer token is generated from a 'demo-user' service account (same
approach as create_bearer_token.sh) and stored in Key Vault as:
  secret name  = <cluster-name>
  secret value = <bearer-token>

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --keyvault-name) KEYVAULT_NAME="$2"; shift 2 ;;
    --cluster-name)  CLUSTER_NAME="$2";  shift 2 ;;
    --help|-h)       usage ;;
    *) die "Unknown option: $1  (run with --help for usage)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -n "$KEYVAULT_NAME" ]] || die "--keyvault-name is required."

# ---------------------------------------------------------------------------
# Resolve cluster name
# ---------------------------------------------------------------------------
if [[ -z "$CLUSTER_NAME" ]]; then
  step "No --cluster-name provided; detecting from kubectl context..."
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is not installed and --cluster-name was not provided."
  fi
  CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || true)
  [[ -n "$CLUSTER_NAME" ]] || die "Could not determine cluster name from kubectl context. Pass --cluster-name explicitly."
  info "Detected cluster name from context: '${CLUSTER_NAME}'"
fi

# ---------------------------------------------------------------------------
# Verify required tools
# ---------------------------------------------------------------------------
step "Verifying required tools..."
command -v kubectl >/dev/null 2>&1 || die "kubectl is required but not found."
command -v az     >/dev/null 2>&1 || die "Azure CLI (az) is required but not found."
info "kubectl and az are available."

# ---------------------------------------------------------------------------
# Verify Azure CLI authentication
# ---------------------------------------------------------------------------
step "Verifying Azure CLI authentication..."
if ! az account show >/dev/null 2>&1; then
  die "Not logged into Azure CLI. Run 'az login' first."
fi
info "Azure CLI is authenticated."

# ---------------------------------------------------------------------------
# Create service account and cluster role binding (idempotent)
# ---------------------------------------------------------------------------
step "Creating 'demo-user' service account in the default namespace..."
kubectl create serviceaccount demo-user -n default \
  --dry-run=client -o yaml | kubectl apply -f -
info "Service account 'demo-user' applied."

step "Binding 'demo-user' to the cluster-admin role..."
kubectl create clusterrolebinding demo-user-binding \
  --clusterrole cluster-admin \
  --serviceaccount default:demo-user \
  --dry-run=client -o yaml | kubectl apply -f -
info "ClusterRoleBinding 'demo-user-binding' applied."

# ---------------------------------------------------------------------------
# Create the service account token secret
# ---------------------------------------------------------------------------
step "Creating service account token secret 'demo-user-secret'..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: demo-user-secret
  annotations:
    kubernetes.io/service-account.name: demo-user
type: kubernetes.io/service-account-token
EOF
info "Secret 'demo-user-secret' applied."

# ---------------------------------------------------------------------------
# Extract bearer token (retry up to 10 times; token may not be immediately
# populated by the Kubernetes token controller after the secret is created)
# ---------------------------------------------------------------------------
step "Extracting bearer token from secret..."
TOKEN=""
for i in {1..10}; do
  TOKEN=$(kubectl get secret demo-user-secret -o jsonpath='{$.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [[ -n "$TOKEN" ]] && break
  warn "Token not yet available, retrying in 2 seconds... (${i}/10)"
  sleep 2
done

if [[ -z "$TOKEN" ]]; then
  die "Failed to extract token from secret 'demo-user-secret'."
fi
info "Bearer token extracted successfully."

# ---------------------------------------------------------------------------
# Save token to Key Vault
# ---------------------------------------------------------------------------
step "Saving bearer token to Key Vault '${KEYVAULT_NAME}' as secret '${CLUSTER_NAME}'..."
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name       "${CLUSTER_NAME}" \
  --value      "${TOKEN}" \
  --output table
info "Bearer token saved to Key Vault."

echo ""
info "✅  Bearer token stored in Key Vault '${KEYVAULT_NAME}' under secret name '${CLUSTER_NAME}'."
echo ""
echo "To retrieve the token later:"
echo "  az keyvault secret show --vault-name \"${KEYVAULT_NAME}\" --name \"${CLUSTER_NAME}\" --query value -o tsv"
