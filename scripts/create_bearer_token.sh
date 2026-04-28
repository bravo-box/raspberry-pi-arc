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
echo "  Raspberry Pi Arc — Create Bearer Token"
echo "========================================================"

# ---------------------------------------------------------------------------
# Create service account and cluster role binding
# ---------------------------------------------------------------------------
step "Creating 'demo-user' service account in the default namespace..."
kubectl create serviceaccount demo-user -n default
info "Service account 'demo-user' created."

step "Binding 'demo-user' to the cluster-admin role..."
kubectl create clusterrolebinding demo-user-binding --clusterrole cluster-admin --serviceaccount default:demo-user
info "ClusterRoleBinding 'demo-user-binding' created."

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
# Extract and output the bearer token
# ---------------------------------------------------------------------------
step "Extracting bearer token from secret..."
TOKEN=$(kubectl get secret demo-user-secret -o jsonpath='{$.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
  die "Failed to extract token from secret 'demo-user-secret'."
fi

info "Bearer token extracted successfully."
echo ""
echo "$TOKEN"